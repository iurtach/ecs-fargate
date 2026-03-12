output "cluster_name"        { value = aws_ecs_cluster.this.name }
output "cluster_arn"         { value = aws_ecs_cluster.this.arn }
output "ecs_tasks_sg_id"     { value = aws_security_group.ecs_tasks.id }
output "ollama_service_name" { value = aws_ecs_service.ollama.name }
output "web_service_name"    { value = aws_ecs_service.web.name }
