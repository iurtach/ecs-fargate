# ============================================================
# Root Variables
# ============================================================

# ── General ──────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "llm-app"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

# ── VPC (reuse from previous task) ───────────────────────────
variable "vpc_id" {
  description = "Existing VPC ID from previous infrastructure"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (2 AZs) — for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (2 AZs) — for ECS tasks"
  type        = list(string)
}

# ── Admin access ──────────────────────────────────────────────
variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed to access Grafana/Prometheus via ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── Existing PostgreSQL ───────────────────────────────────────
variable "db_host" {
  description = "Existing PostgreSQL host (private IP or DNS)"
  type        = string
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "vectordb"
}

variable "db_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL password — stored in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "db_security_group_id" {
  description = "Security group ID of the existing PostgreSQL instance"
  type        = string
}

# ── Telegram ──────────────────────────────────────────────────
variable "telegram_bot_token" {
  description = "Telegram bot token for Alertmanager"
  type        = string
  sensitive   = true
}

variable "telegram_chat_id" {
  description = "Telegram chat/group ID for alerts"
  type        = string
}

# ── Grafana ───────────────────────────────────────────────────
variable "grafana_admin_password" {
  description = "Grafana admin password — stored in Secrets Manager"
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

# ── Container image tags ──────────────────────────────────────
variable "ollama_image_tag" {
  description = "Ollama ECR image tag"
  type        = string
  default     = "latest"
}

variable "web_image_tag" {
  description = "Web service ECR image tag"
  type        = string
  default     = "latest"
}

variable "prometheus_image_tag" {
  description = "Prometheus ECR image tag"
  type        = string
  default     = "latest"
}

variable "grafana_image_tag" {
  description = "Grafana ECR image tag"
  type        = string
  default     = "latest"
}

variable "alertmanager_image_tag" {
  description = "Alertmanager ECR image tag"
  type        = string
  default     = "latest"
}

# ── Resource sizing ───────────────────────────────────────────
variable "ollama_cpu" {
  description = "Ollama task CPU units (1024 = 1 vCPU)"
  type        = number
  default     = 4096
}

variable "ollama_memory" {
  description = "Ollama task memory in MiB"
  type        = number
  default     = 16384
}

variable "web_cpu" {
  description = "Web service task CPU units"
  type        = number
  default     = 512
}

variable "web_memory" {
  description = "Web service task memory in MiB"
  type        = number
  default     = 1024
}

variable "prometheus_cpu" {
  description = "Prometheus task CPU units"
  type        = number
  default     = 1024
}

variable "prometheus_memory" {
  description = "Prometheus task memory in MiB"
  type        = number
  default     = 2048
}

variable "grafana_cpu" {
  description = "Grafana task CPU units"
  type        = number
  default     = 512
}

variable "grafana_memory" {
  description = "Grafana task memory in MiB"
  type        = number
  default     = 1024
}

# ── Auto-scaling ──────────────────────────────────────────────
variable "ollama_min_capacity" {
  type    = number
  default = 1
}

variable "ollama_max_capacity" {
  type    = number
  default = 3
}

variable "web_min_capacity" {
  type    = number
  default = 1
}

variable "web_max_capacity" {
  type    = number
  default = 5
}

# ── Common tags ───────────────────────────────────────────────
variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
