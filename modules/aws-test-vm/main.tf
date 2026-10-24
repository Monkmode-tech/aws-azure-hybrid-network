###############################################################################
# AWS test VM
#
# Amazon Linux 2023 (Graviton) in a private subnet with no public IP. It serves
# a one-line web page on port 80 so Azure can prove it reaches it over the
# tunnel, and is administered only through SSM Session Manager.
###############################################################################

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-test-vm"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-test-vm"
  role = aws_iam_role.this.name
}

resource "aws_security_group" "this" {
  name        = "${var.name}-test-vm"
  description = "Test VM: reachable from Azure only; egress to Azure and the SSM endpoints"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-test-vm" }
}

resource "aws_vpc_security_group_ingress_rule" "from_azure" {
  for_each = { ssh = 22, http = 80 }

  security_group_id = aws_security_group.this.id
  description       = "${upper(each.key)} from the Azure VNet over the VPN"
  cidr_ipv4         = var.azure_vnet_cidr
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
}

resource "aws_vpc_security_group_ingress_rule" "icmp_from_azure" {
  security_group_id = aws_security_group.this.id
  description       = "Ping from the Azure VNet"
  cidr_ipv4         = var.azure_vnet_cidr
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
}

resource "aws_vpc_security_group_egress_rule" "to_azure" {
  security_group_id = aws_security_group.this.id
  description       = "Anything to the Azure VNet (tests: ping, HTTP, SSH)"
  cidr_ipv4         = var.azure_vnet_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "to_endpoints" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to the SSM interface endpoints"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  monitoring             = true
  ebs_optimized          = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    mkdir -p /opt/hello
    echo "hello from AWS ($(hostname -I | awk '{print $1}'))" > /opt/hello/index.html
    cat > /etc/systemd/system/hello.service <<'UNIT'
    [Unit]
    Description=Cross-cloud test endpoint
    After=network-online.target
    [Service]
    ExecStart=/usr/bin/python3 -m http.server 80 --directory /opt/hello
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now hello.service
  EOF

  tags = { Name = "${var.name}-test-vm" }

  lifecycle {
    ignore_changes = [ami]
  }
}
