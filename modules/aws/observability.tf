# --------------------------------------------------------------------------------
# Observability
#
# Default path (use_managed_observability = true): Amazon Managed Prometheus (AMP)
# receives metrics via an ADOT collector sidecar in the rag-service task (see
# main.tf), and Amazon Managed Grafana (AMG) reads from AMP. Nothing to patch or
# scale — the trade-off is AMG requires IAM Identity Center (AWS SSO) enabled in the
# account; swap authentication_providers to ["SAML"] if you use an external IdP
# instead.
#
# Alternative path (use_managed_observability = false): self-hosted Prometheus +
# Grafana as ECS Fargate services, mirroring modules/local-docker's shape 1:1 on
# AWS. Config/dashboards are held on EFS instead of a local bind mount — populate
# the access points once before starting these services (see README.md).
# --------------------------------------------------------------------------------

locals {
  adot_collector_config = <<-YAML
    receivers:
      prometheus:
        config:
          global:
            scrape_interval: 15s
          scrape_configs:
            - job_name: 'rag-service'
              metrics_path: /metrics
              static_configs:
                - targets: ['localhost:${var.rag_service_port}']

    exporters:
      prometheusremotewrite:
        endpoint: "${var.use_managed_observability ? "${aws_prometheus_workspace.this[0].prometheus_endpoint}api/v1/remote_write" : ""}"
        auth:
          authenticator: sigv4auth

    extensions:
      sigv4auth:
        region: "${local.region}"
        service: "aps"

    service:
      extensions: [sigv4auth]
      pipelines:
        metrics:
          receivers: [prometheus]
          exporters: [prometheusremotewrite]
  YAML
}

# --------------------------------------------------------------------------------
# Managed path: AMP + AMG
# --------------------------------------------------------------------------------

resource "aws_prometheus_workspace" "this" {
  count = var.use_managed_observability ? 1 : 0

  alias = "${var.name_prefix}-amp"
  tags  = var.tags
}

resource "aws_grafana_workspace" "this" {
  count = var.use_managed_observability ? 1 : 0

  name                     = "${var.name_prefix}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["PROMETHEUS"]

  tags = var.tags
}

# --------------------------------------------------------------------------------
# Self-hosted path: Prometheus + Grafana on ECS Fargate, config on EFS
# --------------------------------------------------------------------------------

resource "aws_security_group" "observability" {
  count = var.use_managed_observability ? 0 : 1

  name_prefix = "${var.name_prefix}-observability-"
  description = "Self-hosted Prometheus/Grafana ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description = "Prometheus UI (demo simplicity - put behind an ALB/SSO for anything long-lived)"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
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

resource "aws_security_group" "efs" {
  count = var.use_managed_observability ? 0 : 1

  name_prefix = "${var.name_prefix}-efs-"
  description = "NFS from self-hosted observability ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.observability[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_efs_file_system" "observability_config" {
  count = var.use_managed_observability ? 0 : 1

  encrypted = true
  tags      = merge(var.tags, { Name = "${var.name_prefix}-observability-config" })
}

resource "aws_efs_mount_target" "observability_config" {
  for_each = var.use_managed_observability ? {} : { for idx, subnet_id in var.subnet_ids : idx => subnet_id }

  file_system_id  = aws_efs_file_system.observability_config[0].id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_efs_access_point" "prometheus_config" {
  count = var.use_managed_observability ? 0 : 1

  file_system_id = aws_efs_file_system.observability_config[0].id

  root_directory {
    path = "/prometheus"
    creation_info {
      owner_gid   = 65534
      owner_uid   = 65534
      permissions = "755"
    }
  }

  tags = var.tags
}

resource "aws_efs_access_point" "grafana_provisioning" {
  count = var.use_managed_observability ? 0 : 1

  file_system_id = aws_efs_file_system.observability_config[0].id

  root_directory {
    path = "/grafana"
    creation_info {
      owner_gid   = 472
      owner_uid   = 472
      permissions = "755"
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "observability" {
  count = var.use_managed_observability ? 0 : 1

  name              = "/ecs/${var.name_prefix}-observability"
  retention_in_days = 14

  tags = var.tags
}

resource "aws_ecs_task_definition" "prometheus" {
  count = var.use_managed_observability ? 0 : 1

  family                   = "${var.name_prefix}-prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "prometheus-config"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability_config[0].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.prometheus_config[0].id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "prometheus"
      image     = "prom/prometheus:${var.prometheus_image_tag}"
      essential = true
      portMappings = [
        { containerPort = 9090, protocol = "tcp" }
      ]
      mountPoints = [
        {
          sourceVolume  = "prometheus-config"
          containerPath = "/etc/prometheus"
          readOnly      = true
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability[0].name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "prometheus" {
  count = var.use_managed_observability ? 0 : 1

  name            = "${var.name_prefix}-prometheus"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.prometheus[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.observability[0].id]
    assign_public_ip = true
  }

  depends_on = [aws_efs_mount_target.observability_config]

  tags = var.tags
}

resource "aws_ecs_task_definition" "grafana" {
  count = var.use_managed_observability ? 0 : 1

  family                   = "${var.name_prefix}-grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "grafana-provisioning"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability_config[0].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.grafana_provisioning[0].id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = "grafana/grafana:${var.grafana_image_tag}"
      essential = true
      portMappings = [
        { containerPort = 3000, protocol = "tcp" }
      ]
      environment = [
        { name = "GF_SECURITY_ADMIN_USER", value = var.grafana_admin_user },
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = var.grafana_admin_password },
        { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
      ]
      mountPoints = [
        {
          sourceVolume  = "grafana-provisioning"
          containerPath = "/etc/grafana/provisioning"
          readOnly      = true
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability[0].name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "grafana" {
  count = var.use_managed_observability ? 0 : 1

  name            = "${var.name_prefix}-grafana"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.grafana[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.observability[0].id]
    assign_public_ip = true
  }

  depends_on = [aws_efs_mount_target.observability_config]

  tags = var.tags
}
