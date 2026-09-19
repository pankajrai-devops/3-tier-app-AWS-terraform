resource "aws_vpc" "cde_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "cde-environment-vpc" }
}

resource "aws_subnet" "public_pub" {
  vpc_id            = aws_vpc.cde_vpc.id
  cidr_block        = var.public_pub_cidr
  availability_zone = "eu-west-2a"
  tags              = { Name = "cde-public-pub" }
}

resource "aws_subnet" "firewall_sub" {
  vpc_id            = aws_vpc.cde_vpc.id
  cidr_block        = var.firewall_cidr
  availability_zone = "eu-west-2a"
  tags              = { Name = "cde-firewall-subnet" }
}

resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.cde_vpc.id
  cidr_block        = var.private_app_cidr
  availability_zone = "eu-west-2a"
  tags              = { Name = "cde-private-app" }
}

resource "aws_subnet" "private_db" {
  vpc_id            = aws_vpc.cde_vpc.id
  cidr_block        = var.private_db_cidr
  availability_zone = "eu-west-2a"
  tags              = { Name = "cde-private-db" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cde_vpc.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_pub.id
}

# ================================================================================================================
# AWS NETWORK FIREWALL CONFIGURATION (DOMAIN FILTERING for example.com and secureweb.com)
# ================================================================================================================
# 1. THE STATEFUL RULE GROUP LAYER
resource "aws_networkfirewall_rule_group" "domain_whitelist" {
  capacity = 100
  name     = "cde-outbound-domain-whitelist"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = [".example.com", ".secureweb.com"]
      }
    }
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [var.vpc_cidr]
        }
      }
    }
  }
}

# 2. THE POLICY LAYER (Fixed Parameter Argument)
resource "aws_networkfirewall_firewall_policy" "fw_policy" {
  name = "cde-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_stateful"]
    stateless_fragment_default_actions = ["aws:forward_to_stateful"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.domain_whitelist.arn
    }
  }
}

# 3. THE FIREWALL ENGINE LAYER
resource "aws_networkfirewall_firewall" "cde_firewall" {
  name                = "cde-egress-firewall"
  vpc_id              = aws_vpc.cde_vpc.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.fw_policy.arn

  subnet_mapping {
    subnet_id = aws_subnet.firewall_sub.id
  }
}

locals {
  fw_endpoint_id = element([
    for sync_state in aws_networkfirewall_firewall.cde_firewall.firewall_status[0].sync_states : 
    sync_state.attachment[0].endpoint_id 
    if sync_state.attachment[0].subnet_id == aws_subnet.firewall_sub.id
  ], 0)
}

# ========================================================
# ROUTING TABLES and ASSOCIATIONS
# ========================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cde_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_pub.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "firewall_rt" {
  vpc_id = aws_vpc.cde_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "fw_assoc" {
  subnet_id      = aws_subnet.firewall_sub.id
  route_table_id = aws_route_table.firewall_rt.id
}

resource "aws_route_table" "private_app_rt" {
  vpc_id = aws_vpc.cde_vpc.id
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = local.fw_endpoint_id
  }
}

resource "aws_route_table_association" "app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_app_rt.id
}

resource "aws_route_table" "private_db_rt" {
  vpc_id = aws_vpc.cde_vpc.id
}

resource "aws_route_table_association" "db_assoc" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private_db_rt.id
}

# ========================================================================================================================================================================
# NACL to control inbound traffic to whitelisted IP and the NAT Gateway destination ports for response back from example.com and secureweb.com
# ========================================================================================================================================================================

resource "aws_network_acl" "pub_nacl" {
  vpc_id     = aws_vpc.cde_vpc.id
  subnet_ids = [aws_subnet.public_pub.id]
  tags       = { Name = "cde-pub-nacl" }

  # DYNAMIC INBOUND INTERFACE 1: Loops whitelisted IPs over Port 443 for ALB (HTTPS) and doesnt allow port 80 for secure architecture
  dynamic "ingress" {
    for_each = toset(var.whitelisted_ips)
    content {
      protocol   = "tcp"
      rule_no    = 100 + index(var.whitelisted_ips, ingress.value) # e.g., 100, 101, 102
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 443
      to_port    = 443
    }
  }

  # This is for NAT GW's ports from internet for outbound's response back from example.com and secureweb.com
  ingress {
    protocol   = "tcp"
    rule_no    = 500
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Explicit Deny All Rule
  ingress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # ------------------------------------------------------
  # OUTBOUND EGRESS RULES
  # ------------------------------------------------------
  #rule 100 for comm from ALB to python pyodbc app running on port 8443 on app ec2
  #rule 110 allows NAT GW to push traffic to internet to 443 of example.com and secureweb.com
  #rule 120 onwards allows return response traffic from ALB to listening dynamic port of whitelisted clients 
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.private_app_cidr
    from_port  = 8443
    to_port    = 8443
  }
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443 
  }
  dynamic "egress" {
    for_each = toset(var.whitelisted_ips)
    content {
      protocol   = "tcp"
      rule_no    = 120 + index(var.whitelisted_ips, egress.value)
      action     = "allow"
      cidr_block = egress.value
      from_port  = 1024
      to_port    = 65535
    }
  }
  egress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# NACL for the Firewall Subnet
resource "aws_network_acl" "fw_nacl" {
  vpc_id     = aws_vpc.cde_vpc.id
  subnet_ids = [aws_subnet.firewall_sub.id]
  tags       = { Name = "cde-firewall-nacl" }

  # ------------------------------------------------------
  # INBOUND RULES (INGRESS)
  # ------------------------------------------------------

  # Rule 100: Allow HTTPS requests from the Private App Subnet to pass into the Firewall
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.private_app_cidr
    from_port  = 443
    to_port    = 443
  }

  # Rule 120: MANDATORY Return Traffic path from the Internet (NAT GW interface hook)
  # This allows example.com / secureweb.com to send responses back to the firewall endpoint
  # MUST be 0.0.0.0/0 because internet destination IPs are dynamic and then dynamic ports of example.com and secureweb.com but if we know fixed port than it can be restricted
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0" 
    from_port  = 1024
    to_port    = 65535 
  }

  # EXPLICIT INBOUND CATCH-ALL DENY
  ingress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # ------------------------------------------------------
  # FW NACL OUTBOUND RULES (EGRESS)
  # ------------------------------------------------------
  
  # Rule 100: Allow the firewall to push Port 443 traffic out toward the NAT Gateway / Internet
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0" # Needed because destination web IPs are dynamic
    from_port  = 443
    to_port    = 443
  }

  # Rule 120: Allow the firewall to push response payloads back to Application Subnet on Ephemeral Ports from the NAT GW
  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.private_app_cidr
    from_port  = 1024
    to_port    = 65535
  }

  # EXPLICIT OUTBOUND CATCH-ALL DENY
  egress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}


resource "aws_network_acl" "app_nacl" {
  vpc_id     = aws_vpc.cde_vpc.id
  subnet_ids = [aws_subnet.private_app.id]
  tags       = { Name = "cde-app-nacl" }
  # number 100 rule is for allowing the inbound connection from ALB for listening the Application
  # number 110 covers inbound connection response back from Database and also the response back from example.com and secureweb.com via the NAT GW and our app using dynamic port for response
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.public_pub_cidr
    from_port  = 8443
    to_port    = 8443
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  ingress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ##100 is for connection to database from app ec2 and 110 for 443 connection to firewall subnet 
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.private_db_cidr
    from_port  = 3306
    to_port    = 3306
  }
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.firewall_cidr
    from_port  = 443
    to_port    = 443
  }
  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.public_pub_cidr
    from_port  = 1024
    to_port    = 65535
  }
  egress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

resource "aws_network_acl" "db_nacl" {
  vpc_id     = aws_vpc.cde_vpc.id
  subnet_ids = [aws_subnet.private_db.id]
  tags       = { Name = "cde-db-nacl" }

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.private_app_cidr
    from_port  = 3306
    to_port    = 3306
  }
  ingress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.private_app_cidr
    from_port  = 1024
    to_port    = 65535
  }
  egress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}