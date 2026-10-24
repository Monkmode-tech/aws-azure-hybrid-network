###############################################################################
# AWS side: a private-only VPC
#
# - No internet gateway and no NAT: nothing in this VPC can reach, or be
#   reached from, the internet. The only way in or out is the IPsec VPN.
# - Administration goes through SSM Session Manager over VPC interface
#   endpoints, so there is no SSH exposure and no bastion host.
# - Routes to Azure are learned over BGP and propagated from the virtual
#   private gateway into the private route table.
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Two /24s for workloads; the rest of the /21 is reserved for growth.
  private_subnets = {
    (local.azs[0]) = cidrsubnet(var.vpc_cidr, 3, 0)
    (local.azs[1]) = cidrsubnet(var.vpc_cidr, 3, 1)
  }

  ssm_endpoints = toset(["ssm", "ssmmessages", "ec2messages"])
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-deny-all" }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name}-private-${each.key}", Tier = "private" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

#------------------------------------------------------------------------------
# Virtual private gateway (the AWS end of the VPN) + BGP route propagation
#------------------------------------------------------------------------------
resource "aws_vpn_gateway" "this" {
  vpc_id          = aws_vpc.this.id
  amazon_side_asn = var.amazon_side_asn

  tags = { Name = "${var.name}-vgw" }
}

resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.this.id
  route_table_id = aws_route_table.private.id
}

#------------------------------------------------------------------------------
# SSM interface endpoints (private administration, no internet needed)
#------------------------------------------------------------------------------
resource "aws_security_group" "endpoints" {
  name        = "${var.name}-ssm-endpoints"
  description = "HTTPS from inside the VPC to the SSM interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-ssm-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  # One AZ keeps the lab cheap; production would place endpoints in every AZ.
  subnet_ids         = [aws_subnet.private[local.azs[0]].id]
  security_group_ids = [aws_security_group.endpoints.id]

  tags = { Name = "${var.name}-${each.key}-endpoint" }
}

#------------------------------------------------------------------------------
# Flow logs (KMS-encrypted) - shows every flow that crossed the tunnel
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "logs_key" {
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "logs" {
  description             = "${var.name} - VPC flow logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.logs_key.json
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60
}
