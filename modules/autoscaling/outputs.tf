output "ollama_autoscaling_target_id" { value = aws_appautoscaling_target.ollama.id }
output "web_autoscaling_target_id"    { value = aws_appautoscaling_target.web.id }
