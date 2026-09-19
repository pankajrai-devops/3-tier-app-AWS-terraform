output "cde_perimeter_alb_dns" {
  value       = module.compute.alb_dns_name
  description = "ALB's DNS Address"
}

output "nat_gateway_public_ip" {
  value       = module.networking.nat_public_ip
  description = "OUTBOUND IP that need whitelisting at secureweb.com and example.com"
}