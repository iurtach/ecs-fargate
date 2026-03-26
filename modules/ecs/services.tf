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

  # 0/100: stop old task before starting new one.
  # Prometheus locks its EFS data directory — two instances running simultaneously
  # will fight over the lock and the new one will fail to start.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

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
    ignore_changes = [desired_count]
  }
}

# ── PostgreSQL Service ────────────────────────────────────
resource "aws_ecs_service" "postgres" {
  name            = "${var.project_name}-${var.environment}-postgres"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # 0/100: stop old task before starting new one.
  # PostgreSQL with a single EFS volume must never have two instances running
  # at the same time — concurrent writes would corrupt data.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [var.private_subnet_ids[0]]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.postgres.arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ── Grafana Service ───────────────────────────────────────────
resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-${var.environment}-grafana"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # 0/100: stop old task before starting new one.
  # Grafana uses SQLite on EFS — concurrent access corrupts the database.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

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
