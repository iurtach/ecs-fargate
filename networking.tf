# ============================================================
# Networking — Private subnets + NAT Gateway
#
# The existing VPC (10.0.0.0/24) is fully occupied by two
# public subnets. A secondary CIDR block (10.1.0.0/24) is
# added to create dedicated private subnets for ECS tasks
# and EFS mount targets. Must be from a different /16 than
# the primary CIDR (10.0.0.0/16) due to AWS restrictions.
#
# Traffic flow:
#   Internet → IGW → ALB (public subnets)
#             → NAT GW → ECS tasks (private subnets) → ECR/AWS APIs
# ============================================================

# ── Secondary CIDR block ──────────────────────────────────────
resource "aws_vpc_ipv4_cidr_block_association" "private" {
  vpc_id     = var.vpc_id
  cidr_block = "10.1.0.0/24"
}

# ── Private Subnets ───────────────────────────────────────────
resource "aws_subnet" "private_a" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.1.0.0/25"
  availability_zone = "${var.aws_region}a"

  depends_on = [aws_vpc_ipv4_cidr_block_association.private]

  tags = { Name = "${var.project_name}-${var.environment}-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.1.0.128/25"
  availability_zone = "${var.aws_region}b"

  depends_on = [aws_vpc_ipv4_cidr_block_association.private]

  tags = { Name = "${var.project_name}-${var.environment}-private-b" }
}

# ── NAT Gateway ───────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-${var.environment}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.public_subnet_ids[0]

  depends_on = [aws_eip.nat]

  tags = { Name = "${var.project_name}-${var.environment}-nat-gw" }
}

# ── Route Table for private subnets ───────────────────────────
resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${var.project_name}-${var.environment}-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
