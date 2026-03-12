output "efs_id"                     { value = aws_efs_file_system.monitoring.id }
output "efs_arn"                    { value = aws_efs_file_system.monitoring.arn }
output "prometheus_efs_id"          { value = aws_efs_file_system.monitoring.id }
output "grafana_efs_id"             { value = aws_efs_file_system.monitoring.id }
output "prometheus_access_point_id" { value = aws_efs_access_point.prometheus.id }
output "grafana_access_point_id"    { value = aws_efs_access_point.grafana.id }
