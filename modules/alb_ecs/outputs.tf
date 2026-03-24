output "alb_dns_name" { value = aws_lb.this.dns_name }
output "alb_zone_id" { value = aws_lb.this.zone_id }
output "alb_arn" { value = aws_lb.this.arn }
output "alb_sg_id" { value = aws_security_group.alb.id }
output "web_target_group_arn" { value = aws_lb_target_group.web.arn }
output "ollama_target_group_arn" { value = aws_lb_target_group.ollama.arn }
output "grafana_target_group_arn" { value = aws_lb_target_group.grafana.arn }
output "prometheus_target_group_arn" { value = aws_lb_target_group.prometheus.arn }
