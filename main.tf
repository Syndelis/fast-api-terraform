terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
  profile = "brenno"
}

resource "aws_key_pair" "warpgate" {
  key_name   = "warpgate-key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAVlR5iMTJxzh4Wbijs+YYg/4p0/GKtuynbTU7MH3CVp brenno@warpgate"
}

resource "aws_security_group" "seguranca_total" {
  name = "seguranca_total"

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
}

resource "aws_instance" "app_server" {
  ami                         = "ami-04b70fa74e45c3917"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.warpgate.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.seguranca_total.id]

  tags = {
    Name = "ExampleAppServerInstance"
  }
}

