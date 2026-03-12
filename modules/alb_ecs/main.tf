# ============================================================
# ALB — Application Load Balancer with path-based routing
#
#  /api/*        → Ollama   :11434
#  /grafana/*    → Grafana  :3000
#  /prometheus/* → Prometheus :9090  (admin CIDR only)
#  /*            → Web frontend :8080
# ============================================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB - allow HTTP from internet"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-alb-sg" }
}

resource "aws_lb" "this" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  tags = { Name = "${var.project_name}-${var.environment}-alb" }
}

# ── Target Groups ─────────────────────────────────────────────

resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30
}

resource "aws_lb_target_group" "ollama" {
  name        = "${var.project_name}-${var.environment}-ollama-tg"
  port        = 11434
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/api/version"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 60
}

resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-${var.environment}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/grafana/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30
}

resource "aws_lb_target_group" "prometheus" {
  name        = "${var.project_name}-${var.environment}-prom-tg"
  port        = 9090
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/prometheus/-/healthy"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30
}

# ── Listener + Rules ──────────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener_rule" "ollama" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ollama.arn
  }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  condition {
    path_pattern {
      values = ["/grafana", "/grafana/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_lb_listener_rule" "prometheus" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  condition {
    path_pattern {
      values = ["/prometheus", "/prometheus/*"]
    }
  }

  condition {
    source_ip {
      values = var.admin_cidr_blocks
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }
}
