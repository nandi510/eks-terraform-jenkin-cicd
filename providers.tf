
# provider
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }

  # S3 backend for remote state — Jenkins will use this
  backend "s3" {
    bucket         = "your-terraform-state-bucket510"   # ← change this
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"                     # ← change this
    dynamodb_table = "terraform-state-lock"          # ← change this (or remove if not using lock)
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  # No access_key / secret_key — Jenkins EC2 IAM role is used automatically
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = module.eks.cluster_token
}
