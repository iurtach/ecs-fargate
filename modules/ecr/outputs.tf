output "repository_arns" {
  value = [for r in aws_ecr_repository.services : r.arn]
}

output "ollama_repository_url" { value = aws_ecr_repository.services["ollama"].repository_url }
output "web_repository_url" { value = aws_ecr_repository.services["web"].repository_url }
output "prometheus_repository_url" { value = aws_ecr_repository.services["prometheus"].repository_url }
output "grafana_repository_url" { value = aws_ecr_repository.services["grafana"].repository_url }

output "ollama_image_uri" { value = "${aws_ecr_repository.services["ollama"].repository_url}:latest" }
output "web_image_uri" { value = "${aws_ecr_repository.services["web"].repository_url}:latest" }
output "prometheus_image_uri" { value = "${aws_ecr_repository.services["prometheus"].repository_url}:latest" }
output "grafana_image_uri" { value = "${aws_ecr_repository.services["grafana"].repository_url}:latest" }
output "alertmanager_repository_url" { value = aws_ecr_repository.services["alertmanager"].repository_url }
