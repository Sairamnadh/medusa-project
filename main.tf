terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Create a new IAM role for ECS execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsExecutionRole1"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "ecsExecutionRole1"
  }
}

# Attach the execution role policy to the new role
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS cluster definition
resource "aws_ecs_cluster" "medusa_cluster" {
  name = "medusa-cluster"
}

# Create a new ECR repository
resource "aws_ecr_repository" "medusa_ecr" {
  name = "medusa-repository"

  tags = {
    Name = "medusa-repository"
  }
}

# ECS task definition using the new IAM role and ECR repository
resource "aws_ecs_task_definition" "medusa_task" {
  family                   = "medusa-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn  # Reference new IAM role

  container_definitions = jsonencode([{
    name      = "medusa-container"
    image     = "${aws_ecr_repository.medusa_ecr.repository_url}:latest"  # Reference new ECR repository
    cpu       = 0
    memory    = 512
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]
  }])

  tags = {
    Name = "medusa-task"
  }
}

# ECS service definition
resource "aws_ecs_service" "medusa_service" {
  name            = "medusa-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
    security_groups  = [aws_security_group.ecs_security_group.id]
    assign_public_ip = true
  }

  # Ignore changes to prevent issues with idempotency
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition
    ]
  }

  tags = {
    Name = "medusa-service"
  }
}

# VPC definition
resource "aws_vpc" "medusa_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "medusa-vpc"
  }
}

# Subnet definitions
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.medusa_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "medusa-subnet-1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.medusa_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "medusa-subnet-2"
  }
}

# Security group definition
resource "aws_security_group" "ecs_security_group" {
  vpc_id = aws_vpc.medusa_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "medusa-security-group"
  }
}
