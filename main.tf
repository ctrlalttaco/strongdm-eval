terraform {
  required_version = "0.13.2"

  required_providers {
    random = {
      version = "~> 2.3.0"
      source  = "hashicorp/random"
    }

    aws = {
      version = "~> 3.5.0"
      source  = "hashicorp/aws"
    }

    tls = {
      version = "~> 2.2.0"
      source  = "hashicorp/tls"
    }

    local = {
      version = "~> 1.4.0"
      source  = "hashicorp/local"
    }
  }
}

variable "region" {
  default = "us-east-1"
}

resource "random_pet" "name" {}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${random_pet.name.id}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "${var.region}a"
  cidr_block        = "10.0.0.0/24"

  tags = {
    Name = "${random_pet.name.id}-public-subnet"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "${var.region}a"
  cidr_block        = "10.0.1.0/24"

  tags = {
    Name = "${random_pet.name.id}-private1-subnet"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "${var.region}b"
  cidr_block        = "10.0.2.0/24"

  tags = {
    Name = "${random_pet.name.id}-private2-subnet"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_vpc.main.main_route_table_id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_vpc.main.main_route_table_id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_vpc.main.main_route_table_id
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${random_pet.name.id}-igw"
  }
}

resource "aws_route" "igw" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${random_pet.name.id}-ssh-key"
  public_key = tls_private_key.main.public_key_openssh

  tags = {
    Name = "${random_pet.name.id}-ssh-key"
  }
}

resource "local_file" "ssh_private_key" {
    content         = tls_private_key.main.private_key_pem
    filename        = "${path.module}/ssh_rsa"
    file_permission = 0600
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_security_group" "gateway" {
  name        = "${random_pet.name.id}-gateway"
  description = "Allow gateway ingress traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${random_pet.name.id}-gateway-sg"
  }
}

resource "aws_security_group_rule" "gateway_ingress" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.gateway.id
}

resource "aws_security_group_rule" "gateway_ingress_sdm" {
  type              = "ingress"
  from_port         = 5000
  to_port           = 5000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.gateway.id
}

resource "aws_security_group_rule" "gateway_egress" {
  type              = "egress"
  from_port         = -1
  to_port           = -1
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.gateway.id
}

resource "aws_instance" "gateway" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.main.key_name

  tags = {
    Name = "${random_pet.name.id}-gateway"
  }
}

resource "aws_network_interface_sg_attachment" "gateway_sg" {
  security_group_id    = aws_security_group.gateway.id
  network_interface_id = aws_instance.gateway.primary_network_interface_id
}

resource "aws_security_group" "server" {
  name        = "${random_pet.name.id}-server"
  description = "Allow server ingress traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${random_pet.name.id}-server-sg"
  }
}

resource "aws_security_group_rule" "server_ingress" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  source_security_group_id = aws_security_group.gateway.id
  security_group_id = aws_security_group.server.id
}

resource "aws_security_group_rule" "server_egress" {
  type              = "egress"
  from_port         = -1
  to_port           = -1
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.server.id
}

resource "aws_instance" "server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_1.id
  associate_public_ip_address = false
  key_name                    = aws_key_pair.main.key_name

  tags = {
    Name = "${random_pet.name.id}-server"
  }
}

resource "aws_network_interface_sg_attachment" "server_sg" {
  security_group_id    = aws_security_group.server.id
  network_interface_id = aws_instance.server.primary_network_interface_id
}

resource "aws_security_group" "db" {
  name        = "${random_pet.name.id}-db"
  description = "Allow db ingress traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${random_pet.name.id}-db-sg"
  }
}

resource "aws_security_group_rule" "db_ingress" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  source_security_group_id = aws_security_group.gateway.id
  security_group_id = aws_security_group.db.id
}

resource "aws_security_group_rule" "db_egress" {
  type              = "egress"
  from_port         = -1
  to_port           = -1
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}

resource "random_password" "db" {
  length = 64
  special = false
}

resource "aws_db_subnet_group" "db" {
  name       = "${random_pet.name.id}-db-sng"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
    Name = "${random_pet.name.id}-db-sng"
  }
}

resource "aws_db_instance" "db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "12.3"
  instance_class       = "db.t2.micro"
  name                 = "testdb"
  username             = "sdm"
  password             = random_password.db.result
  db_subnet_group_name = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]

  tags = {
    Name = "${random_pet.name.id}-db"
  }
}

resource "local_file" "ssh_config" {
  filename        = "${path.module}/ssh_config"
  file_permission = 0640

  content = <<EOF
StrictHostKeyChecking no
ServerAliveInterval 10

Host gateway
  User ubuntu
  HostName ${aws_instance.gateway.public_ip}
  IdentityFile ${local_file.ssh_private_key.filename}
  ForwardAgent yes

Host server
  User ubuntu
  HostName ${aws_instance.server.private_ip}
  IdentityFile ${local_file.ssh_private_key.filename}
  ProxyJump gateway

EOF
}

output "db_address" {
  value = aws_db_instance.db.address
}

output "db_password" {
  value = random_password.db.result
}

output "server_address" {
  value = aws_instance.server.private_ip
}