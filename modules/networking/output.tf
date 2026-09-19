output "vpc_id" {
  value       = aws_vpc.cde_vpc.id
  description = "Unique identification mapping key for the established CDE core VPC"
}

output "public_pub_id" {
  value       = aws_subnet.public_pub.id
  description = "Unique target string pointer for public boundary mapping"
}

output "private_app_id" {
  value       = aws_subnet.private_app.id
  description = "Unique pointer reference linking downstream compute rules to App subnets"
}

output "private_db_id" {
  value       = aws_subnet.private_db.id
  description = "Target interface reference code tracking the Database tier"
}

output "nat_public_ip" {
  value       = aws_eip.nat_eip.public_ip
  description = "Static public transaction IP endpoint assigned to the egress NAT Gateway module"
}