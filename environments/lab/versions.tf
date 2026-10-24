terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State lives in the AWS bootstrap bucket (see backend.hcl.example).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "aws-azure-hybrid-network"
      ManagedBy  = "terraform"
      Repository = "github.com/Monkmode-tech/aws-azure-hybrid-network"
      Owner      = var.owner
    }
  }
}

# Authenticates with your Azure CLI login (az login) - no secrets in code.
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}
