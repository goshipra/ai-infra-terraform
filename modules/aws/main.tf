# ------------------------------------------------------------------------------------
# ai-infra-terraform / modules/aws
#
# Documents the same stack's shape on AWS: rag-service on ECS Fargate behind an ALB,
# Qdrant on EC2 (or Qdrant Cloud), Prometheus/Grafana either fully managed (AMP/AMG,
# the default) or self-hosted on ECS. See README.md in this directory for the "why" —
# in short: this module is validated for syntax but intentionally NOT applied, to
# avoid running up AWS cost for a portfolio piece.
#
# Bring your own VPC/subnets (see variables.tf) — this module provisions the AI stack,
# not the network underneath it.
# ------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id
}

# --------------------------------------------------------------------------------
# ECS cluster
# --------------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

# --------------------------------------------------------------------------------
# Optional ECR repository for rag-service
# --------------------------------------------------------------------------------

resource "aws_ecr_repository" "rag_service" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = "${var.name_prefix}-rag-service"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# --------------------------------------------------------------------------------
# Networking: security groups + ALB in front of rag-service
# --------------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Ingress for the rag-service ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere (put this behind TLS/WAF before real use)"
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

  tags = var.tags
}

resource "aws_security_group" "rag_service" {
  name_prefix = "${var.name_prefix}-rag-service-"
  description = "rag-service ECS tasks: allow from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "rag-service port from ALB"
    from_port       = var.rag_service_port
    to_port         = var.rag_service_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_lb" "rag_service" {
  name               = "${var.name_prefix}-rag-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  tags = var.tags
}

resource "aws_lb_target_group" "rag_service" {
  name        = "${var.name_prefix}-rag-tg"
  port        = var.rag_service_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = var.tags
}

resource "aws_lb_listener" "rag_service" {
  load_balancer_arn = aws_lb.rag_service.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rag_service.arn
  }
}

# --------------------------------------------------------------------------------
# CloudWatch log group + ECS task definition/service for rag-service
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "rag_service" {
  name              = "/ecs/${var.name_prefix}-rag-service"
  retention_in_days = 14

  tags = var.tags
}

resource "aws_ecs_task_definition" "rag_service" {
  family                   = "${var.name_prefix}-rag-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.rag_service_cpu
  memory                   = var.rag_service_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode(concat(
    [
      {
        name      = "rag-service"
        image     = var.rag_service_image
        essential = true
        portMappings = [
          {
            containerPort = var.rag_service_port
            protocol      = "tcp"
          }
        ]
        environment = [
          for k, v in var.rag_service_env : { name = k, value = v }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.rag_service.name
            "awslogs-region"        = local.region
            "awslogs-stream-prefix" = "rag-service"
          }
        }
      }
    ],
    # ADOT sidecar: scrapes rag-service's /metrics and remote-writes into Amazon
    # Managed Prometheus. Only present when using managed observability — the
    # self-hosted path (modules/aws/observability.tf) has its own Prometheus
    # pulling the same endpoint directly instead.
    var.use_managed_observability ? [
      {
        name      = "adot-collector"
        image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
        essential = false
        environment = [
          {
            name  = "AOT_CONFIG_CONTENT"
            value = local.adot_collector_config
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.rag_service.name
            "awslogs-region"        = local.region
            "awslogs-stream-prefix" = "adot-collector"
          }
        }
      }
    ] : []
  ))

  tags = var.tags
}

resource "aws_ecs_service" "rag_service" {
  name            = "${var.name_prefix}-rag-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.rag_service.arn
  desired_count   = var.rag_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.rag_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rag_service.arn
    container_name   = "rag-service"
    container_port   = var.rag_service_port
  }

  depends_on = [aws_lb_listener.rag_service]

  tags = var.tags
}
