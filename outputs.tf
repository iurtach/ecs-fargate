output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb_ecs.alb_dns_name
}

output "web_url" {
  description = "URL of the web frontend"
  value       = "http://${module.alb_ecs.alb_dns_name}/"
}

output "grafana_url" {
  description = "URL of the Grafana dashboard"
  value       = "http://${module.alb_ecs.alb_dns_name}/grafana"
}

output "prometheus_url" {
  description = "URL of the Prometheus UI"
  value       = "http://${module.alb_ecs.alb_dns_name}/prometheus"
}

output "ollama_api_url" {
  description = "URL of the Ollama API"
  value       = "http://${module.alb_ecs.alb_dns_name}/api"
}

output "ecs_cluster_name" {
  description = "ECS Cluster name"
  value       = module.ecs.cluster_name
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    ollama       = module.ecr.ollama_repository_url
    web          = module.ecr.web_repository_url
    prometheus   = module.ecr.prometheus_repository_url
    grafana      = module.ecr.grafana_repository_url
    alertmanager = module.ecr.alertmanager_repository_url
  }
}

output "efs_id" {
  description = "EFS File System ID for monitoring data"
  value       = module.efs.efs_id
}