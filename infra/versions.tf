terraform {
  required_version = ">= 1.8.0" # OpenTofu

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Estado local (infra/terraform.tfstate, fuera de git).
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "livecam"
      managed_by = "opentofu"
    }
  }
}
