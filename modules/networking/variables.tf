variable "vpc_cidr" {
  type        = string
  description = "Base network block passed down from root configurations"
}

variable "public_pub_cidr" {
  type        = string
  description = "Target public routing block mask"
}

variable "firewall_cidr" {
  type        = string
  description = "Dedicated firewall checkpoint mask mapping parameters"
}

variable "private_app_cidr" {
  type        = string
  description = "Internal payload handling boundary maps"
}

variable "private_db_cidr" {
  type        = string
  description = "Backend secure repository block masks"
}

variable "whitelisted_ips" {
  type        = list(string)
  description = "Client consumer verification network addresses"
}