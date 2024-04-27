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

# NETWORK #################################################

resource "aws_vpc" "app_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.1.1.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.1.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id
}

resource "aws_eip" "app_eip" {
  vpc = true
}

resource "aws_nat_gateway" "app_ngw" {
  subnet_id     = aws_subnet.public.id
  allocation_id = aws_eip.app_eip.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app_vpc.id
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.app_igw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###########################################################

resource "aws_key_pair" "warpgate" {
  key_name   = "warpgate-key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAVlR5iMTJxzh4Wbijs+YYg/4p0/GKtuynbTU7MH3CVp brenno@warpgate"
}

resource "aws_security_group" "seguranca_total" {
  name   = "seguranca_total"
  vpc_id = aws_vpc.app_vpc.id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = -1
    to_port     = 0
  }
}

resource "aws_ecs_cluster" "app_cluster" {
  name = "app_cluster"
}

resource "aws_ecs_cluster_capacity_providers" "app_cluster" {
  cluster_name = aws_ecs_cluster.app_cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "app_docker_image" {
  family                   = "service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  container_definitions = jsonencode([
    {
      name      = "fast-api"
      image     = "ghcr.io/syndelis/fast-api-terraform:latest"
      cpu       = 1024
      memory    = 2048
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "app"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_docker_image.arn
  desired_count   = 1

  network_configuration {
    security_groups  = [aws_security_group.seguranca_total.id]
    subnets          = [aws_subnet.public.id]
    assign_public_ip = true
  }
}

resource "aws_instance" "app_server" {
  ami                         = "ami-04b70fa74e45c3917"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.warpgate.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.seguranca_total.id]
  subnet_id                   = aws_subnet.public.id

  tags = {
    Name = "ExampleAppServerInstance"
  }
}

# DEPLOY PERMISSIONS ######################################

data "aws_caller_identity" "current" {}

locals {
  iam_task_role_arn      = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_ecs_task_definition.app_docker_image.task_role_arn}"
  iam_execution_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_ecs_task_definition.app_docker_image.execution_role_arn}"
  ecs_service_arn        = "arn:aws:ecs:us-east-1:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.app_cluster.name}/${aws_ecs_service.app.name}"
}

data "aws_iam_policy_document" "minimum_required_deploy_permissions" {
  statement {
    sid       = "RegisterTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "DescribeTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "PassRolesInTaskDefinition"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.iam_task_role_arn, local.iam_execution_role_arn]
  }

  statement {
    sid       = "DeployService"
    effect    = "Allow"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [local.ecs_service_arn]
  }
}

resource "aws_iam_policy" "ecs_deploy_task_definition" {
  name        = "ecs_deploy_task_definition"
  description = "Taken from Action: Amazon ECS 'Deploy Task Definition' Action for GitHub Actions"
  policy      = data.aws_iam_policy_document.minimum_required_deploy_permissions.json

}

resource "aws_iam_user" "github_actions" {
  name = "github_actions"
}

###########################################################
