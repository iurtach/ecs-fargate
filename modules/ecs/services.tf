# ── Ollama Service ────────────────────────────────────────────
resource "aws_ecs_service" "ollama" {
  name            = "${var.project_name}-${var.environment}-ollama"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.ollama.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.ollama_target_group_arn
    container_name   = "ollama"
    container_port   = 11434
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ollama.arn
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# ── Web Service ───────────────────────────────────────────────
resource "aws_ecs_service" "web" {
  name            = "${var.project_name}-${var.environment}-web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.web_target_group_arn
    container_name   = "web"
    container_port   = 8080
  }

  service_registries {
    registry_arn = aws_service_discovery_service.web.arn
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# ── Prometheus Service ────────────────────────────────────────
resource "aws_ecs_service" "prometheus" {
  name            = "${var.project_name}-${var.environment}-prometheus"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [var.private_subnet_ids[0]]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.prometheus_target_group_arn
    container_name   = "prometheus"
    container_port   = 9090
  }

  service_registries {
    registry_arn = aws_service_discovery_service.prometheus.arn
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# ── Grafana Service ───────────────────────────────────────────
resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-${var.environment}-grafana"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [var.private_subnet_ids[0]]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.grafana_target_group_arn
    container_name   = "grafana"
    container_port   = 3000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.grafana.arn
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}
