output "task_execution_role_arn"  { value = aws_iam_role.task_execution.arn }
output "ollama_task_role_arn"     { value = aws_iam_role.ollama_task.arn }
output "web_task_role_arn"        { value = aws_iam_role.web_task.arn }
output "monitoring_task_role_arn" { value = aws_iam_role.monitoring_task.arn }
