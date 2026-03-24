variable "project_name" { type = string }
variable "environment" { type = string }
variable "db_password_secret_arn" { type = string }
variable "telegram_secret_arn" { type = string }
variable "grafana_password_secret_arn" { type = string }
variable "grafana_db_password_secret_arn" { type = string }
variable "log_group_arn" { type = string }
