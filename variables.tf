variable "aws_region" {
  type        = string
  description = "Target AWS Deployment Region"
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  type        = string
  description = "Base VPC Network Mask"
  default     = "10.0.0.0/16"
}

variable "public_pub_cidr" {
  type        = string
  description = "Subnet block for external-facing entry points (Public Subnet Tier)"
  default     = "10.0.1.0/24"
}

variable "private_app_cidr" {
  type        = string
  description = "Subnet block containing CDE Applications"
  default     = "10.0.2.0/24"
}

variable "private_db_cidr" {
  type        = string
  description = "Subnet block hosting secured databases"
  default     = "10.0.3.0/24"
}

variable "firewall_cidr" {
  type        = string
  description = "Subnet block dedicated exclusively to the AWS Network Firewall Endpoint"
  default     = "10.0.4.0/24"
}

variable "whitelisted_ips" {
  type        = list(string)
  description = "Finite list of User base that can access application"
  default     = ["199.0.113.0/24", "198.51.100.0/24"]
}

variable "app_ami" {
  type        = string
  description = "Target Operating System Image for App Layer (Ensure availability in eu-west-2)"
  default     = "ami-0a1234567890"
}

variable "db_ami" {
  type        = string
  description = "Target Operating System Image for DB Layer (Ensure availability in eu-west-2)"
  default     = "ami-0b0987654321"
}

variable "instance_type" {
  type        = string
  description = "Compute scale profile allocation"
  default     = "t3.medium"
}

variable "domain_name" {
  type        = string
  description = "The target root apex domain for the CDE Infrastructure"
  default     = "paymentstartupcde.com"
}