# VPC privada para RDS y para las Lambdas que hablan con la base de datos.
# No hay NAT: el tráfico a S3 sale por un Gateway Endpoint y el de Secrets Manager
# por un Interface Endpoint. La firma de presigned URLs es local (no requiere red).

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${local.name}-private-${count.index + 1}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security groups ---------------------------------------------------------

resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda-sg"
  description = "Lambdas dentro de la VPC"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Salida hacia RDS, endpoints y S3"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "MySQL solo accesible desde las Lambdas"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL desde Lambdas"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}

resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints-sg"
  description = "Interface endpoints (HTTPS desde Lambdas)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS desde Lambdas"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}

# --- VPC endpoints -----------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "${local.name}-s3-endpoint" }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "${local.name}-secrets-endpoint" }
}
