# --------------------------------------------------------------------------------
# IAM: ECS execution/task roles, plus (conditionally) the Grafana workspace role.
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: what ECS itself needs (pull image, write logs).
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: what the application code inside the container is allowed to call.
resource "aws_iam_role" "ecs_task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "ecs_task_permissions" {
  # AMP remote-write, only relevant when the ADOT sidecar is present.
  dynamic "statement" {
    for_each = var.use_managed_observability ? [1] : []
    content {
      sid = "AMPRemoteWrite"
      actions = [
        "aps:RemoteWrite",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata",
      ]
      resources = [aws_prometheus_workspace.this[0].arn]
    }
  }

  # S3 access to the RAG corpus bucket, only when it exists.
  dynamic "statement" {
    for_each = var.create_corpus_bucket ? [1] : []
    content {
      sid = "CorpusBucketReadWrite"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
      ]
      resources = [
        aws_s3_bucket.corpus[0].arn,
        "${aws_s3_bucket.corpus[0].arn}/*",
      ]
    }
  }

  # EFS client mount/write, only needed for the self-hosted Prometheus/Grafana
  # tasks (main.tf's rag-service task never mounts EFS).
  dynamic "statement" {
    for_each = var.use_managed_observability ? [] : [1]
    content {
      sid = "ObservabilityEfsAccess"
      actions = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:DescribeMountTargets",
      ]
      resources = [aws_efs_file_system.observability_config[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "ecs_task_permissions" {
  # Always non-empty: exactly one of the AMP-remote-write or EFS-client statements
  # above is present depending on use_managed_observability, plus S3 when enabled.
  name   = "${var.name_prefix}-ecs-task-permissions"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_permissions.json
}

# --------------------------------------------------------------------------------
# Amazon Managed Grafana workspace role (only needed for the managed path).
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "grafana_assume" {
  count = var.use_managed_observability ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  count = var.use_managed_observability ? 1 : 0

  name               = "${var.name_prefix}-grafana-workspace"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "grafana_amp_read" {
  count = var.use_managed_observability ? 1 : 0

  statement {
    sid = "AMPRead"
    actions = [
      "aps:QueryMetrics",
      "aps:GetSeries",
      "aps:GetLabels",
      "aps:GetMetricMetadata",
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "grafana_amp_read" {
  count = var.use_managed_observability ? 1 : 0

  name   = "${var.name_prefix}-grafana-amp-read"
  role   = aws_iam_role.grafana[0].id
  policy = data.aws_iam_policy_document.grafana_amp_read[0].json
}
