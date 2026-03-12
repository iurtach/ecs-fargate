# ============================================================
# ECS Auto-Scaling — Target tracking for Ollama and Web
# ============================================================

# ── Ollama ────────────────────────────────────────────────────
resource "aws_appautoscaling_target" "ollama" {
  max_capacity       = var.ollama_max_capacity
  min_capacity       = var.ollama_min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${var.ollama_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ollama_cpu" {
  name               = "${var.project_name}-${var.environment}-ollama-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ollama.resource_id
  scalable_dimension = aws_appautoscaling_target.ollama.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ollama.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "ollama_memory" {
  name               = "${var.project_name}-${var.environment}-ollama-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ollama.resource_id
  scalable_dimension = aws_appautoscaling_target.ollama.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ollama.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ── Web Service ───────────────────────────────────────────────
resource "aws_appautoscaling_target" "web" {
  max_capacity       = var.web_max_capacity
  min_capacity       = var.web_min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${var.web_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "web_cpu" {
  name               = "${var.project_name}-${var.environment}-web-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
