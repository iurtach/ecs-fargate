variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }

variable "ollama_target_group_arn" { type = string }
variable "web_target_group_arn" { type = string }
variable "grafana_target_group_arn" { type = string }
variable "prometheus_target_group_arn" { type = string }

variable "service_discovery_namespace_id" { type = string }
variable "service_discovery_namespace_name" { type = string }

variable "ollama_repository_url" { type = string }
variable "web_repository_url" { type = string }
variable "prometheus_repository_url" { type = string }
variable "grafana_repository_url" { type = string }
variable "alertmanager_repository_url" { type = string }
variable "postgres_exporter_repository_url" { type = string }
variable "postgres_repository_url" { type = string }

variable "ollama_image_tag" {
  type    = string
  default = "latest"
}
variable "web_image_tag" {
  type    = string
  default = "latest"
}
variable "prometheus_image_tag" {
  type    = string
  default = "latest"
}
variable "grafana_image_tag" {
  type    = string
  default = "latest"
}
variable "alertmanager_image_tag" {
  type    = string
  default = "latest"
}

variable "task_execution_role_arn" { type = string }
variable "ollama_task_role_arn" { type = string }
variable "web_task_role_arn" { type = string }
variable "monitoring_task_role_arn" { type = string }
variable "postgres_task_role_arn" { type = string }

variable "prometheus_efs_id" { type = string }
variable "prometheus_efs_access_point_id" { type = string }
variable "grafana_efs_id" { type = string }
variable "grafana_efs_access_point_id" { type = string }
variable "postgres_efs_id" { type = string }
variable "postgres_efs_access_point_id" { type = string }

variable "ollama_cpu" {
  type    = number
  default = 4096
}
variable "ollama_memory" {
  type    = number
  default = 16384
}
variable "web_cpu" {
  type    = number
  default = 512
}
variable "web_memory" {
  type    = number
  default = 1024
}
variable "prometheus_cpu" {
  type    = number
  default = 1024
}
variable "prometheus_memory" {
  type    = number
  default = 2048
}
variable "grafana_cpu" {
  type    = number
  default = 512
}
variable "grafana_memory" {
  type    = number
  default = 1024
}

variable "db_port" { type = number }
variable "db_name" { type = string }
variable "db_username" { type = string }
variable "db_password_secret_arn" { type = string }

variable "telegram_chat_id" { type = string }
variable "telegram_secret_arn" { type = string }

variable "grafana_password_secret_arn" { type = string }
variable "grafana_db_password_secret_arn" { type = string }

variable "log_group_name" { type = string }
