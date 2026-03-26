terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "ecs-fargate-terraform-state-745247897380"
    key     = "prod/terraform.tfstate"
    region  = "eu-north-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    })
  }
}

# ── Data sources ──────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── CloudWatch Log Group ──────────────────────────────────────
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 30
}

# ── Secrets Manager ───────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "/${var.project_name}/${var.environment}/db-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

resource "aws_secretsmanager_secret" "telegram_bot_token" {
  name                    = "/${var.project_name}/${var.environment}/telegram-bot-token"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "telegram_bot_token" {
  secret_id     = aws_secretsmanager_secret.telegram_bot_token.id
  secret_string = var.telegram_bot_token
}

resource "aws_secretsmanager_secret" "grafana_admin_password" {
  name                    = "/${var.project_name}/${var.environment}/grafana-admin-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = var.grafana_admin_password
}

resource "aws_secretsmanager_secret" "grafana_db_password" {
  name                    = "/${var.project_name}/${var.environment}/grafana-db-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "grafana_db_password" {
  secret_id     = aws_secretsmanager_secret.grafana_db_password.id
  secret_string = var.grafana_db_password
}

# ── AWS Cloud Map (Service Discovery) ─────────────────────────
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "${var.project_name}.local"
  description = "Private DNS namespace for ECS service discovery"
  vpc         = var.vpc_id
}

# ── Modules ───────────────────────────────────────────────────

module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
  account_id   = data.aws_caller_identity.current.account_id
}

module "iam_ecs" {
  source                         = "./modules/iam_ecs"
  project_name                   = var.project_name
  environment                    = var.environment
  db_password_secret_arn         = aws_secretsmanager_secret.db_password.arn
  telegram_secret_arn            = aws_secretsmanager_secret.telegram_bot_token.arn
  grafana_password_secret_arn    = aws_secretsmanager_secret.grafana_admin_password.arn
  grafana_db_password_secret_arn = aws_secretsmanager_secret.grafana_db_password.arn
  log_group_arn                  = aws_cloudwatch_log_group.ecs.arn
}

module "efs" {
  source             = "./modules/efs"
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = var.vpc_id
  private_subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  ecs_sg_id          = module.ecs.ecs_tasks_sg_id
}

module "alb_ecs" {
  source            = "./modules/alb_ecs"
  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  admin_cidr_blocks = var.admin_cidr_blocks
}

module "ecs" {
  source       = "./modules/ecs"
  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # Networking
  vpc_id             = var.vpc_id
  private_subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  alb_sg_id          = module.alb_ecs.alb_sg_id

  # ALB Target Groups
  ollama_target_group_arn     = module.alb_ecs.ollama_target_group_arn
  web_target_group_arn        = module.alb_ecs.web_target_group_arn
  grafana_target_group_arn    = module.alb_ecs.grafana_target_group_arn
  prometheus_target_group_arn = module.alb_ecs.prometheus_target_group_arn

  # Service Discovery
  service_discovery_namespace_id   = aws_service_discovery_private_dns_namespace.this.id
  service_discovery_namespace_name = aws_service_discovery_private_dns_namespace.this.name

  # ECR image URLs
  ollama_repository_url       = module.ecr.ollama_repository_url
  web_repository_url          = module.ecr.web_repository_url
  prometheus_repository_url   = module.ecr.prometheus_repository_url
  grafana_repository_url      = module.ecr.grafana_repository_url
  alertmanager_repository_url      = module.ecr.alertmanager_repository_url
  postgres_exporter_repository_url = module.ecr.postgres_exporter_repository_url
  postgres_repository_url          = module.ecr.postgres_repository_url

  # Image tags
  ollama_image_tag       = var.ollama_image_tag
  web_image_tag          = var.web_image_tag
  prometheus_image_tag   = var.prometheus_image_tag
  grafana_image_tag      = var.grafana_image_tag
  alertmanager_image_tag = var.alertmanager_image_tag

  # IAM Roles
  task_execution_role_arn  = module.iam_ecs.task_execution_role_arn
  ollama_task_role_arn     = module.iam_ecs.ollama_task_role_arn
  web_task_role_arn        = module.iam_ecs.web_task_role_arn
  monitoring_task_role_arn = module.iam_ecs.monitoring_task_role_arn
  postgres_task_role_arn   = module.iam_ecs.postgres_task_role_arn

  # EFS
  prometheus_efs_id              = module.efs.prometheus_efs_id
  prometheus_efs_access_point_id = module.efs.prometheus_access_point_id
  grafana_efs_id                 = module.efs.grafana_efs_id
  grafana_efs_access_point_id    = module.efs.grafana_access_point_id
  postgres_efs_id                = module.efs.postgres_efs_id
  postgres_efs_access_point_id   = module.efs.postgres_access_point_id

  # Resource sizing
  ollama_cpu        = var.ollama_cpu
  ollama_memory     = var.ollama_memory
  web_cpu           = var.web_cpu
  web_memory        = var.web_memory
  prometheus_cpu    = var.prometheus_cpu
  prometheus_memory = var.prometheus_memory
  grafana_cpu       = var.grafana_cpu
  grafana_memory    = var.grafana_memory

  # Database
  db_port                = var.db_port
  db_name                = var.db_name
  db_username            = var.db_username
  db_password_secret_arn = aws_secretsmanager_secret.db_password.arn

  # Telegram
  telegram_chat_id    = var.telegram_chat_id
  telegram_secret_arn = aws_secretsmanager_secret.telegram_bot_token.arn

  # Grafana
  grafana_password_secret_arn    = aws_secretsmanager_secret.grafana_admin_password.arn
  grafana_db_password_secret_arn = aws_secretsmanager_secret.grafana_db_password.arn

  # Logging
  log_group_name = aws_cloudwatch_log_group.ecs.name
}

module "autoscaling" {
  source       = "./modules/autoscaling"
  project_name = var.project_name
  environment  = var.environment

  ecs_cluster_name    = module.ecs.cluster_name
  ollama_service_name = module.ecs.ollama_service_name
  ollama_min_capacity = var.ollama_min_capacity
  ollama_max_capacity = var.ollama_max_capacity
  web_service_name    = module.ecs.web_service_name
  web_min_capacity    = var.web_min_capacity
  web_max_capacity    = var.web_max_capacity
}

# PostgreSQL runs inside ECS — inter-task communication is already
# allowed by the self-referencing rule in the ecs_tasks security group.
