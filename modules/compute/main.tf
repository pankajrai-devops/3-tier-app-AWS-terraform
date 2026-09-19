# ========================================================
# SECURITY GROUPS
# ========================================================
resource "aws_security_group" "alb_sg" {
  name        = "cde-alb-sg"
  description = "Edge proxy ingress filter - Strict HTTPS Mode"
  vpc_id      = var.vpc_id
  tags        = { Name = "cde-alb-security-group" }
}

resource "aws_security_group" "app_sg" {
  name        = "cde-app-sg"
  description = "Application compute node rule profiles - Hardened End-to-End TLS"
  vpc_id      = var.vpc_id
  tags        = { Name = "cde-app-security-group" }
}

resource "aws_security_group" "db_sg" {
  name        = "cde-db-sg"
  description = "Database insulation framework"
  vpc_id      = var.vpc_id
  tags        = { Name = "cde-db-security-group" }
}

# --- ALB RULES ---
resource "aws_vpc_security_group_ingress_rule" "alb_in_443" {
  security_group_id = aws_security_group.alb_sg.id
  description       = "Allow TLS from finite corporate consumers"
  count             = length(var.whitelisted_ips)
  cidr_ipv4         = var.whitelisted_ips[count.index]
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_out_to_app" {
  security_group_id            = aws_security_group.alb_sg.id
  description                  = "Forward re-encrypted traffic strictly to App SG"
  referenced_security_group_id = aws_security_group.app_sg.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
}

# --- APP RULES ---
resource "aws_vpc_security_group_ingress_rule" "app_in_from_alb" {
  security_group_id            = aws_security_group.app_sg.id
  description                  = "Only accept proxy ingress payloads from ALB SG"
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_out_to_db" {
  security_group_id            = aws_security_group.app_sg.id
  description                  = "Restrict database connections strictly to DB SG"
  referenced_security_group_id = aws_security_group.db_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_out_to_fw" {
  security_group_id = aws_security_group.app_sg.id
  description       = "Restrict outbound internet traffic to Firewall Subnet"
  cidr_ipv4         = var.firewall_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# --- DB RULES ---
resource "aws_vpc_security_group_ingress_rule" "db_in_from_app" {
  security_group_id            = aws_security_group.db_sg.id
  description                  = "Accept MySQL queries strictly from App SG"
  referenced_security_group_id = aws_security_group.app_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

# ========================================================
# ACM Certificate Generation for TLS
# ========================================================
resource "aws_route53_zone" "primary" {
  name = "paymentstartupcde.com"
}


resource "aws_acm_certificate" "cde_cert" {
  domain_name               = var.domain_name
  validation_method         = "DNS"
  subject_alternative_names = ["*.${var.domain_name}"]

  tags = { Name = "cde-ssl-cert" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cde_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.primary.zone_id
}

resource "aws_acm_certificate_validation" "cert_verify" {
  certificate_arn         = aws_acm_certificate.cde_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ========================================================
# Application Load Balancer
# ========================================================
resource "aws_lb" "external_alb" {
  name               = "cde-perimeter-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [var.public_pub_id, var.public_pub_id] 
}

resource "aws_lb_target_group" "app_tg" {
  name     = "cde-app-target-group"
  port     = 8443
  protocol = "HTTPS"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTPS"
    port                = "8443"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.external_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2021-06"
  certificate_arn   = aws_acm_certificate_validation.cert_verify.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "app_attachment" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_server.id
  port             = 8443
}

resource "aws_route53_record" "apex_alias" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.external_alb.dns_name
    zone_id                = aws_lb.external_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wildcard_alias" {
  zone_id =  aws_route53_zone.primary.zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.external_alb.dns_name
    zone_id                = aws_lb.external_alb.zone_id
    evaluate_target_health = true
  }
}

# ========================================================
# STATIC PRIVATE IP FOR DB VIA PRIVATE ENI
# ========================================================

# Compute Targets
resource "aws_instance" "app_server" {
  ami                    = var.app_ami
  instance_type          = var.instance_type
  subnet_id              = var.private_app_id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  tags                   = { Name = "cde-app-node" }
  user_data = <<-EOF
              #!/bin/bash
              curl -kvvv https://example.com -o package.extension
              Command to start the application on port 8443
              EOF
}

resource "aws_network_interface" "db_private_interface" {
  subnet_id       = var.private_db_id
  private_ips     = ["10.0.3.50"] 
  security_groups = [aws_security_group.db_sg.id]
  tags            = { Name = "cde-db-static-eni" }
}

resource "aws_instance" "mysql_server" {
  ami           = var.db_ami
  instance_type = var.instance_type
  tags          = { Name = "cde-mysql-node" }
}

resource "aws_network_interface_attachment" "db_interface_attach" {
  instance_id          = aws_instance.mysql_server.id
  network_interface_id = aws_network_interface.db_private_interface.id
  device_index         = 0
}