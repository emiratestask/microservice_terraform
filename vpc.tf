
locals {
  vpc_name = "umsl-vpc-${var.aws_region}"
}

data "aws_availability_zones" "available_az" {}

# Create the VPC
resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = "${merge(var.tags, map("Name",local.vpc_name))}"

  lifecycle {
    ignore_changes = [tags]
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = "${merge(var.tags, map("Name","${local.vpc_name}-igw"))}"
}

# Create the two public subnets
resource "aws_subnet" "public_subnets" {
  count             = "${var.az_count * (var.enable_public_subnets == "true" ? 1 : 0)}"
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${cidrsubnet(var.vpc_cidr, 4, count.index + 0)}"
  availability_zone = "${data.aws_availability_zones.available_az.names[count.index]}"

  tags = "${merge(var.tags, map("Name","${local.vpc_name}-public-${count.index + 1}"))}"

  lifecycle {
    ignore_changes = [tags]
  }
}

# Create the two private subnets
resource "aws_subnet" "private_subnets" {
  count             = "${var.az_count * (var.enable_private_subnets == "true" ? 1 : 0)}"
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${cidrsubnet(var.vpc_cidr, 4, count.index + 3)}"
  availability_zone = "${data.aws_availability_zones.available_az.names[count.index]}"

  tags = "${merge(var.tags, map("Name","${local.vpc_name}-private-${count.index + 1}"))}"

  lifecycle {
    ignore_changes = [tags]
  }
}

# Create the route table, igw and associate it with the public subnets
resource "aws_route_table" "public_route" {
  vpc_id = "${aws_vpc.vpc.id}"
  count  = "${var.az_count * (var.enable_public_subnets == "true" ? 1 : 0)}"
  tags   = "${merge(var.tags, map("Name","${local.vpc_name}-public-rt-${count.index + 1}"))}"
}

resource "aws_route" "public_igw" {
  count                  = "${var.az_count * (var.enable_public_subnets == "true" ? 1 : 0)}"
  route_table_id         = "${element(aws_route_table.public_route.*.id,count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.igw.id}"
}

resource "aws_route_table_association" "public_route_assoc" {
  count          = "${var.az_count * (var.enable_public_subnets == "true" ? 1 : 0)}"
  subnet_id      = "${element(aws_subnet.public_subnets.*.id,count.index)}"
  route_table_id = "${element(aws_route_table.public_route.*.id,count.index)}"
}

# create the route tables and associate it with the private subnets
resource "aws_route_table" "private_route" {
  count  = "${var.az_count * (var.enable_private_subnets == "true" ? 1 : 0)}"
  vpc_id = "${aws_vpc.vpc.id}"
  tags   = "${merge(var.tags, map("Name","${local.vpc_name}-private-rt-${count.index + 1}"))}"
}

resource "aws_route_table_association" "private_route_assoc" {
  count          = "${var.az_count * (var.enable_private_subnets == "true" ? 1 : 0)}"
  subnet_id      = "${element(aws_subnet.private_subnets.*.id,count.index)}"
  route_table_id = "${element(aws_route_table.private_route.*.id,count.index)}"
}

# Create the NAT Gateway and atatch to the privae subnet
resource "aws_eip" "eip" {
  count = "${var.az_count * (var.enable_public_subnets == "true" ? 1 : 0)}"
  vpc   = true
  tags      = "${merge(var.tags, map("Name",local.vpc_name))}"
}

resource "aws_nat_gateway" "ngw" {
  count         = "${var.az_count * (var.enable_public_subnets == "true" ? 1 : 0)}"
  subnet_id     = "${element(aws_subnet.public_subnets.*.id,count.index)}"
  allocation_id = "${element(aws_eip.eip.*.id,count.index)}"
  tags          = "${merge(var.tags, map("Name",local.vpc_name))}"
}

resource "aws_route" "private_nat_gateway" {
  count                  = "${var.az_count * (var.enable_public_subnets == "true" ? 1 : 0)}"
  route_table_id         = "${element(aws_route_table.private_route.*.id,count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.ngw.*.id,count.index)}"
}

# Define the NACL for private
resource "aws_network_acl" "nacl-private" {
  count  = "${var.az_count * (var.enable_private_subnets == "true" ? 1 : 0)}"
  vpc_id     = "${aws_vpc.vpc.id}"
  subnet_ids = ["${element(aws_subnet.private_subnets.*.id,count.index)}"]
}

# accept inbound SSH requests
resource "aws_network_acl_rule" "private_ssh_in" {
  count  = "${var.az_count * (var.enable_private_subnets == "true" ? 1 : 0)}"
  network_acl_id = "${aws_network_acl.nacl-private[count.index].id}"
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "${var.vpc_cidr}"
  from_port      = 22
  to_port        = 22
}

# outbound response for resources over ephemeral ports
resource "aws_network_acl_rule" "private_ephemeral_out" {
  count  = "${var.az_count * (var.enable_private_subnets == "true" ? 1 : 0)}"
  network_acl_id = "${aws_network_acl.nacl-private[count.index].id}"
  rule_number    = 200
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "${var.vpc_cidr}"
  from_port      = 1024
  to_port        = 65535
}
