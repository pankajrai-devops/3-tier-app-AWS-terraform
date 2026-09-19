terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region                      = "eu-west-2"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    # 1. EKS (Elastic Kubernetes Service)
    eks = "http://localhost:5001"

    # 2. R53 (Route 53)
    route53 = "http://localhost:5001"

    # 3. AWS Network Firewall
    networkfirewall = "http://localhost:5001"

    # 4. ALB (Application Load Balancers / ELB v2)
    elbv2 = "http://localhost:5001"

    # 5, 6, 7. VPC, NACLs, and Security Groups (All handle by the EC2 service endpoint)
    ec2 = "http://localhost:5001"
  }
}


# VPC, Subnets, Routing, Firewall,IGW, NAT GW and Stateless NACLs
module "networking" {
  source           = "./modules/networking"
  vpc_cidr         = var.vpc_cidr
  public_pub_cidr  = var.public_pub_cidr
  firewall_cidr    = var.firewall_cidr
  private_app_cidr = var.private_app_cidr
  private_db_cidr  = var.private_db_cidr
  whitelisted_ips  = var.whitelisted_ips
}

# Compute & Security Groups ,ALB, ACM Certificate Validation, SGs, and EC2s
module "compute" {
  source              = "./modules/compute"
  vpc_id              = module.networking.vpc_id
  public_pub_id       = module.networking.public_pub_id
  private_app_id      = module.networking.private_app_id
  private_db_id       = module.networking.private_db_id
  private_app_cidr    = var.private_app_cidr
  private_db_cidr     = var.private_db_cidr
  firewall_cidr       = var.firewall_cidr
  whitelisted_ips     = var.whitelisted_ips
  app_ami             = var.app_ami
  db_ami              = var.db_ami
  instance_type       = var.instance_type
  domain_name         = var.domain_name
}