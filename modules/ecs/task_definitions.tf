# ── Ollama Task Definition ────────────────────────────────────
resource "aws_ecs_task_definition" "ollama" {
  family                   = "${var.project_name}-${var.environment}-ollama"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ollama_cpu
  memory                   = var.ollama_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.ollama_task_role_arn

  container_definitions = jsonencode([{
    name         = "ollama"
    image        = "${var.ollama_repository_url}:${var.ollama_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 11434, hostPort = 11434, protocol = "tcp" }]
    environment = [
      { name = "OLLAMA_HOST", value = "0.0.0.0" },
      { name = "OLLAMA_ORIGINS", value = "*" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ollama"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -sf http://localhost:11434/api/version || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 5
      startPeriod = 300
    }
  }])

  tags = { Service = "ollama" }
}

# ── Web Task Definition ───────────────────────────────────────
resource "aws_ecs_task_definition" "web" {
  family                   = "${var.project_name}-${var.environment}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.web_task_role_arn

  container_definitions = jsonencode([{
    name         = "web"
    image        = "${var.web_repository_url}:${var.web_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080, hostPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "OLLAMA_API_URL", value = "http://ollama.${var.service_discovery_namespace_name}:11434" },
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_PORT", value = tostring(var.db_port) },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USER", value = var.db_username },
      { name = "PORT", value = "8080" }
    ]
    secrets = [{ name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "web"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
  }])

  tags = { Service = "web" }
}

# ── Prometheus Task Definition ────────────────────────────────
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.project_name}-${var.environment}-prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.prometheus_cpu
  memory                   = var.prometheus_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.monitoring_task_role_arn

  container_definitions = jsonencode([
    {
      name         = "prometheus"
      image        = "${var.prometheus_repository_url}:${var.prometheus_image_tag}"
      essential    = true
      portMappings = [{ containerPort = 9090, hostPort = 9090, protocol = "tcp" }]
      command = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--storage.tsdb.retention.time=30d",
        "--web.enable-lifecycle",
        "--web.external-url=http://localhost:9090/prometheus",
        "--web.route-prefix=/prometheus"
      ]
      environment = [
        { name = "OLLAMA_HOST", value = "ollama.${var.service_discovery_namespace_name}" },
        { name = "WEB_HOST", value = "web.${var.service_discovery_namespace_name}" },
        { name = "GRAFANA_HOST", value = "grafana.${var.service_discovery_namespace_name}" },
        { name = "DB_HOST", value = var.db_host }
      ]
      mountPoints = [{
        sourceVolume  = "prometheus-data"
        containerPath = "/prometheus"
        readOnly      = false
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prometheus"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:9090/prometheus/-/healthy || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    {
      name         = "alertmanager"
      image        = "${var.alertmanager_repository_url}:${var.alertmanager_image_tag}"
      essential    = false
      portMappings = [{ containerPort = 9093, hostPort = 9093, protocol = "tcp" }]
      environment  = [{ name = "TELEGRAM_CHAT_ID", value = var.telegram_chat_id }]
      secrets      = [{ name = "TELEGRAM_BOT_TOKEN", valueFrom = var.telegram_secret_arn }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "alertmanager"
        }
      }
    },
    {
      # blackbox_exporter sidecar — probes HTTP endpoints (e.g. Ollama /api/version)
      # Prometheus scrapes it at localhost:9115 with ?target=<url>&module=http_2xx
      name         = "blackbox-exporter"
      image        = "prom/blackbox-exporter:v0.25.0"
      essential    = false
      portMappings = [{ containerPort = 9115, hostPort = 9115, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "blackbox-exporter"
        }
      }
    },
    {
      # postgres_exporter sidecar — exposes PostgreSQL metrics on localhost:9187
      # Prometheus scrapes it via static_config localhost:9187 (same task network)
      name         = "postgres-exporter"
      image        = "prometheuscommunity/postgres_exporter:v0.15.0"
      essential    = false
      portMappings = [{ containerPort = 9187, hostPort = 9187, protocol = "tcp" }]
      environment = [
        { name = "DATA_SOURCE_URI", value = "${var.db_host}:${var.db_port}/${var.db_name}?sslmode=disable" },
        { name = "DATA_SOURCE_USER", value = var.db_username }
      ]
      secrets = [
        { name = "DATA_SOURCE_PASS", valueFrom = var.db_password_secret_arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "postgres-exporter"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:9187/metrics | grep -q 'pg_up' || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  volume {
    name = "prometheus-data"
    efs_volume_configuration {
      file_system_id     = var.prometheus_efs_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.prometheus_efs_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  tags = { Service = "prometheus" }
}

# ── Grafana Task Definition ───────────────────────────────────
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-${var.environment}-grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.grafana_cpu
  memory                   = var.grafana_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.monitoring_task_role_arn

  container_definitions = jsonencode([{
    name         = "grafana"
    image        = "${var.grafana_repository_url}:${var.grafana_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 3000, hostPort = 3000, protocol = "tcp" }]
    environment = [
      { name = "GF_SERVER_ROOT_URL", value = "%(protocol)s://%(domain)s/grafana/" },
      { name = "GF_SERVER_SERVE_FROM_SUB_PATH", value = "true" },
      { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },
      { name = "GF_SECURITY_ADMIN_USER", value = "admin" },
      { name = "PROMETHEUS_URL", value = "http://prometheus.${var.service_discovery_namespace_name}:9090/prometheus" },
      { name = "GF_DATABASE_TYPE", value = "sqlite3" },
      { name = "GF_DATABASE_PATH", value = "/var/lib/grafana/grafana.db" }
    ]
    secrets = [
      { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = var.grafana_password_secret_arn }
    ]
    mountPoints = [{
      sourceVolume  = "grafana-data"
      containerPath = "/var/lib/grafana"
      readOnly      = false
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "grafana"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000/grafana/api/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  volume {
    name = "grafana-data"
    efs_volume_configuration {
      file_system_id     = var.grafana_efs_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.grafana_efs_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  tags = { Service = "grafana" }
}
