variable "vpc_id" {
  type        = string
  description = "Target identification tracking string for module security hooks"
}

variable "public_pub_id" {
  type        = string
  description = "Reference ID tracking target public perimeter subnets"
}

variable "private_app_id" {
  type        = string
  description = "Reference ID pointing to the private application runtime network"
}

variable "private_db_id" {
  type        = string
  description = "Reference ID mapping the private database persistence boundary network"
}

variable "private_app_cidr" {
  type        = string
  description = "Network address range matching application subnet routing constraints"
}

variable "private_db_cidr" {
  type        = string
  description = "Network address range matching database subnet routing constraints"
}

variable "whitelisted_ips" {
  type        = list(string)
  description = "Collection of client ingress corporate networks verified for passage"
}

variable "firewall_cidr" {
  type        = string
  description = "Dedicated firewall checkpoint mask mapping parameters"
}

variable "app_ami" {
  type        = string
  description = "Target system volume software image for application nodes"
}

variable "db_ami" {
  type        = string
  description = "Target system volume software image for data storage instances"
}

variable "instance_type" {
  type        = string
  description = "Assigned performance tier scale descriptor string"
}

variable "domain_name" {
  type        = string
  description = "System address identity root pointing to ACM registration objects"
}