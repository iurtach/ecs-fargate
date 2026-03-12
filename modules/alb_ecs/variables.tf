variable "project_name"      { type = string }
variable "environment"       { type = string }
variable "vpc_id"            { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "admin_cidr_blocks" { type = list(string) }
