provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "red_primaria" {
  cidr_block = var.VPC_IPS[0]
  tags = {
    Name = "Red Principal Terraform"
  }
}

resource "aws_vpc" "red_secundaria" {
  cidr_block = var.VPC_IPS[1]
  tags = {
    Name = "Red Secundaria Terraform"
  }
}

# Emparejamiento entre las dos VPC para permitir comunicación interna
resource "aws_vpc_peering_connection" "enlace_vpc" {
  vpc_id        = aws_vpc.red_primaria.id
  peer_vpc_id   = aws_vpc.red_secundaria.id
  auto_accept   = true

  tags = {
    Name = "Emparejamiento entre Red Principal y Secundaria"
  }
}

# Rutas para permitir tráfico entre ambas VPCs
resource "aws_route" "ruta_primaria_a_secundaria" {
  route_table_id            = aws_vpc.red_primaria.main_route_table_id
  destination_cidr_block    = aws_vpc.red_secundaria.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.enlace_vpc.id
}

resource "aws_route" "ruta_secundaria_a_primaria" {
  route_table_id            = aws_vpc.red_secundaria.main_route_table_id
  destination_cidr_block    = aws_vpc.red_primaria.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.enlace_vpc.id
}

# Gateway de Internet para la red principal
resource "aws_internet_gateway" "igw_red_primaria" {
  vpc_id = aws_vpc.red_primaria.id
  tags = {
    Name = "IGW Red Principal"
  }
}

# Gateway de Internet para la red secundaria
resource "aws_internet_gateway" "igw_red_secundaria" {
  vpc_id = aws_vpc.red_secundaria.id
  tags = {
    Name = "IGW Red Secundaria"
  }
}

# Subred pública en la red principal
resource "aws_subnet" "subred_publica_primaria" {
  vpc_id                  = aws_vpc.red_primaria.id
  cidr_block              = var.Subnet_VPC1
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "Subred Pública Principal"
  }
}

# Subred pública en la red secundaria
resource "aws_subnet" "subred_publica_secundaria" {
  vpc_id                  = aws_vpc.red_secundaria.id
  cidr_block              = var.Subnet_VPC2
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "Subred Pública Secundaria"
  }
}

# Subred privada en la red secundaria
resource "aws_subnet" "subred_privada_secundaria" {
  vpc_id            = aws_vpc.red_secundaria.id
  cidr_block        = var.Subnet_Private_VPC2
  availability_zone = "us-east-1a"
  tags = {
    Name = "Subred Privada Secundaria"
  }
}

# Tabla de enrutamiento pública para la red principal
resource "aws_route_table" "tabla_ruta_publica_primaria" {
  vpc_id = aws_vpc.red_primaria.id
  tags = {
    Name = "Tabla Ruta Pública Principal"
  }
}

# Tabla de enrutamiento pública para la red secundaria
resource "aws_route_table" "tabla_ruta_publica_secundaria" {
  vpc_id = aws_vpc.red_secundaria.id
  tags = {
    Name = "Tabla Ruta Pública Secundaria"
  }
}

# Ruta por defecto para acceso a Internet desde la red principal
resource "aws_route" "ruta_publica_primaria" {
  route_table_id         = aws_route_table.tabla_ruta_publica_primaria.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_red_primaria.id
}

# Ruta por defecto para acceso a Internet desde la red secundaria
resource "aws_route" "ruta_publica_secundaria" {
  route_table_id         = aws_route_table.tabla_ruta_publica_secundaria.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_red_secundaria.id
}

# Tabla de enrutamiento privada para la red secundaria
resource "aws_route_table" "tabla_ruta_privada_secundaria" {
  vpc_id = aws_vpc.red_secundaria.id
  tags = {
    Name = "Tabla Ruta Privada Secundaria"
  }
}

# Ruta para permitir comunicación entre la subred privada secundaria y la subred pública principal
resource "aws_route" "ruta_privada_secundaria_a_primaria" {
  route_table_id            = aws_route_table.tabla_ruta_privada_secundaria.id
  destination_cidr_block    = var.Subnet_VPC1
  vpc_peering_connection_id = aws_vpc_peering_connection.enlace_vpc.id
}

# Ruta para permitir comunicación desde la pública principal a la privada secundaria
resource "aws_route" "ruta_publica_primaria_a_privada_secundaria" {
  route_table_id            = aws_route_table.tabla_ruta_publica_primaria.id
  destination_cidr_block    = var.Subnet_Private_VPC2
  vpc_peering_connection_id = aws_vpc_peering_connection.enlace_vpc.id
}

# Asociación de tabla de rutas a la subred pública principal
resource "aws_route_table_association" "asociacion_subred_publica_primaria" {
  subnet_id      = aws_subnet.subred_publica_primaria.id
  route_table_id = aws_route_table.tabla_ruta_publica_primaria.id
}

# Asociación de tabla de rutas a la subred pública secundaria
resource "aws_route_table_association" "asociacion_subred_publica_secundaria" {
  subnet_id      = aws_subnet.subred_publica_secundaria.id
  route_table_id = aws_route_table.tabla_ruta_publica_secundaria.id
}

# Asociación de tabla de rutas a la subred privada secundaria
resource "aws_route_table_association" "asociacion_subred_privada_secundaria" {
  subnet_id      = aws_subnet.subred_privada_secundaria.id
  route_table_id = aws_route_table.tabla_ruta_privada_secundaria.id
}

# Elastic IP para NAT Gateway de la red secundaria
resource "aws_eip" "eip_nat_secundaria" {
  domain = "vpc"
  tags = {
    Name = "EIP NAT Secundaria"
  }
}

# NAT Gateway para la red secundaria
resource "aws_nat_gateway" "nat_gateway_secundaria" {
  allocation_id = aws_eip.eip_nat_secundaria.id
  subnet_id     = aws_subnet.subred_publica_secundaria.id

  tags = {
    Name = "NAT Gateway Secundaria"
  }
  depends_on = [aws_eip.eip_nat_secundaria]
}

# Ruta por defecto para la subred privada secundaria a través del NAT Gateway
resource "aws_route" "ruta_privada_secundaria_a_nat" {
  route_table_id         = aws_route_table.tabla_ruta_privada_secundaria.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_secundaria.id

  depends_on = [aws_nat_gateway.nat_gateway_secundaria]
}

# Recursos duplicados para compatibilidad
resource "aws_eip" "eip_nat_secundaria_extra" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway_secundaria_extra" {
  allocation_id = aws_eip.eip_nat_secundaria_extra.id
  subnet_id     = aws_subnet.subred_publica_secundaria.id
}