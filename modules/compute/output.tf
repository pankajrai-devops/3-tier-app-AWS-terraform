output "alb_dns_name" {
  value       = aws_lb.external_alb.dns_name
  description = "ALB's DNS Address"
}