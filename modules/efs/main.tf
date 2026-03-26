resource "aws_efs_file_system" "monitoring" {
  creation_token   = "${var.project_name}-monitoring-efs"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = { Name = "${var.project_name}-monitoring-efs" }
}

# Mount targets in each private subnet
resource "aws_efs_mount_target" "monitoring" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.monitoring.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.ecs_sg_id]
}

# ─── Access Point: Prometheus data ───────────────────────
resource "aws_efs_access_point" "prometheus" {
  file_system_id = aws_efs_file_system.monitoring.id

  posix_user {
    gid = 65534 # nobody
    uid = 65534
  }

  root_directory {
    path = "/prometheus"
    creation_info {
      owner_gid   = 65534
      owner_uid   = 65534
      permissions = "755"
    }
  }
  tags = { Name = "${var.project_name}-prometheus-ap" }
}

# ─── Access Point: Grafana data ──────────────────────────
resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.monitoring.id

  posix_user {
    gid = 472 # grafana container gid
    uid = 472
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_gid   = 472
      owner_uid   = 472
      permissions = "755"
    }
  }
  tags = { Name = "${var.project_name}-grafana-ap" }
}

# ─── Access Point: PostgreSQL data ───────────────────────
# No posix_user block — the postgres container entrypoint runs as root,
# chowns the data directory to postgres user (UID 999 on Debian), then
# drops privileges. Enforcing a posix_user here blocks that chown.
resource "aws_efs_access_point" "postgres" {
  file_system_id = aws_efs_file_system.monitoring.id

  root_directory {
    path = "/postgres"
    creation_info {
      owner_gid   = 999 # postgres user in pgvector/pgvector:pg15 (Debian)
      owner_uid   = 999
      permissions = "755"
    }
  }
  tags = { Name = "${var.project_name}-postgres-ap" }
}

# ─── Backup Policy ───────────────────────────────────────
resource "aws_efs_backup_policy" "monitoring" {
  file_system_id = aws_efs_file_system.monitoring.id
  backup_policy {
    status = "ENABLED"
  }
}
