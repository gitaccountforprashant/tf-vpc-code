module "label_vpc" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  context    = module.base_label.context
  name       = "vpc"
  attributes = ["main"]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = module.label_vpc.tags
}

# =========================
# Create your subnets here
# =========================

module "label_public_subnet" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  context    = module.base_label.context
  name       = "subnet"
  attributes = ["public"]
}

module "label_private_subnet" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  context    = module.base_label.context
  name       = "subnet"
  attributes = ["private"]
}

# calculate CIDR
module "subnet_addrs" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = var.vpc_cidr
  networks = [
    {
      name     = "private_subnet"
      new_bits = 4
    },
    {
      name     = "public_subnet"
      new_bits = 4
    }
  ]

}

locals {
  az = join("", [var.aws_region, var.az_suffix])
}

# Subnets
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = module.subnet_addrs.network_cidr_blocks.private_subnet
  availability_zone = local.az
  tags              = module.label_private_subnet.tags
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = module.subnet_addrs.network_cidr_blocks.public_subnet
  availability_zone = local.az
  tags              = module.label_public_subnet.tags
}

resource "aws_internet_gateway" "int_gw" {
  vpc_id = aws_vpc.main.id
  tags   = module.label_vpc.tags

}

# Allow public access
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.int_gw.id
  }

  tags = module.label_public_subnet.tags
}


resource "aws_route_table_association" "public_subnet_asso" {

  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id

}

# Deny Public subnet to access private subnet
resource "aws_network_acl" "deny_from_public" {
  vpc_id = aws_vpc.main.id

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "deny"
    cidr_block = module.subnet_addrs.network_cidr_blocks.public_subnet
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = -1
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = module.label_private_subnet.tags
}


resource "aws_network_acl_association" "private_nacl_asso" {

  network_acl_id = aws_network_acl.deny_from_public.id
  subnet_id      = aws_subnet.private.id

}
