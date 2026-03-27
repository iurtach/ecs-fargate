# ============================================================
# IAM — Least-privilege roles for ECS tasks
# ============================================================

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ── Task Execution Role (shared by all tasks) ────────────────
resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-${var.environment}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_extra" {
  statement {
    sid = "ECRAuth"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
    resources = ["${var.log_group_arn}:*"]
  }

  statement {
    sid     = "SecretsManagerRead"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      var.db_password_secret_arn,
      var.telegram_secret_arn,
      var.grafana_password_secret_arn,
      var.grafana_db_password_secret_arn,
    ]
  }
}

resource "aws_iam_policy" "task_execution_extra" {
  name   = "${var.project_name}-${var.environment}-ecs-execution-extra"
  policy = data.aws_iam_policy_document.task_execution_extra.json
}

resource "aws_iam_role_policy_attachment" "task_execution_extra" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.task_execution_extra.arn
}

# ── Ollama Task Role ──────────────────────────────────────────
resource "aws_iam_role" "ollama_task" {
  name               = "${var.project_name}-${var.environment}-ollama-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ollama_task" {
  statement {
    sid       = "CloudWatchMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["${var.project_name}/Ollama"]
    }
  }

  statement {
    sid       = "ECSExec"
    actions   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ollama_task" {
  name   = "${var.project_name}-${var.environment}-ollama-task"
  policy = data.aws_iam_policy_document.ollama_task.json
}

resource "aws_iam_role_policy_attachment" "ollama_task" {
  role       = aws_iam_role.ollama_task.name
  policy_arn = aws_iam_policy.ollama_task.arn
}

# ── Web Task Role ─────────────────────────────────────────────
resource "aws_iam_role" "web_task" {
  name               = "${var.project_name}-${var.environment}-web-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_policy" "web_task" {
  name = "${var.project_name}-${var.environment}-web-task"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${var.log_group_arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "web_task" {
  role       = aws_iam_role.web_task.name
  policy_arn = aws_iam_policy.web_task.arn
}

# ── Monitoring Task Role (Prometheus + Grafana) ───────────────
resource "aws_iam_role" "monitoring_task" {
  name               = "${var.project_name}-${var.environment}-monitoring-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring_ec2_read" {
  role       = aws_iam_role.monitoring_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

data "aws_iam_policy_document" "monitoring_task" {
  statement {
    sid = "CloudWatchRead"
    actions = [
      "cloudwatch:ListMetrics", "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics", "cloudwatch:DescribeAlarms",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECSDescribe"
    actions = [
      "ecs:DescribeClusters", "ecs:DescribeTasks",
      "ecs:ListTasks", "ecs:ListServices", "ecs:DescribeServices",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECSExec"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "monitoring_task" {
  name   = "${var.project_name}-${var.environment}-monitoring-task"
  policy = data.aws_iam_policy_document.monitoring_task.json
}

resource "aws_iam_role_policy_attachment" "monitoring_task" {
  role       = aws_iam_role.monitoring_task.name
  policy_arn = aws_iam_policy.monitoring_task.arn
}

# ── PostgreSQL Task Role ──────────────────────────────────
resource "aws_iam_role" "postgres_task" {
  name               = "${var.project_name}-${var.environment}-postgres-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_policy" "postgres_task" {
  name = "${var.project_name}-${var.environment}-postgres-task"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${var.log_group_arn}:*"]
      },
      {
        # Required for ECS Exec (aws ecs execute-command)
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "postgres_task" {
  role       = aws_iam_role.postgres_task.name
  policy_arn = aws_iam_policy.postgres_task.arn
}
