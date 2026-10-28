terraform {
  # 1.10 brings the S3 backend's native lockfile, which every other stack uses.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # No backend: this stack creates the state bucket, so its own state stays
  # local. See docs/setup/aws-bootstrap.md for where to keep it.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "baby-sweepstake"
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
