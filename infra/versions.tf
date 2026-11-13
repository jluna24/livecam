terraform {
  required_version = ">= 1.8.0" # OpenTofu

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # hashicorp/aws no tiene recurso para el canal de señalización de KVS;
    # awscc (Cloud Control) sí: awscc_kinesisvideo_signaling_channel.
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
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

provider "awscc" {
  region = var.region
}
