# ECS Fargate LLM Platform

A production-grade LLM chat platform deployed on AWS ECS Fargate with self-hosted monitoring.
Built as Task 3 of a DevOps learning path.

## Architecture

```
Internet
   │
   ▼
[ALB] ── path-based routing ──────────────────────────────────
   │  /api/*       → Ollama  :11434  (LLM inference)
   │  /grafana/*   → Grafana :3000   (dashboards)
   │  /prometheus/*→ Prometheus :9090 (metrics, admin-only)
   │  /*           → Web     :8080   (chat UI)
   │
   ▼ (Private subnets 10.0.2.0/24)
[ECS Fargate Tasks]
   │
   ├─ ollama        (llama3.2:1b, 4 vCPU / 16 GB)
   ├─ web           (FastAPI chat UI, 0.5 vCPU / 1 GB)
   ├─ prometheus    (metrics, 1 vCPU / 2 GB)
   │   └─ alertmanager sidecar (Telegram alerts)
   └─ grafana       (dashboards, 0.5 vCPU / 1 GB)
        │
        ▼
[EFS] ── persistent storage for Prometheus + Grafana data
        │
        ▼
[PostgreSQL EC2] ── vectordb + pgvector for chat history
```

### Network Layout

| Subnet | CIDR | Purpose |
|--------|------|---------|
| Public A (eu-north-1a) | 10.0.0.0/25 | ALB, NAT Gateway |
| Public B (eu-north-1b) | 10.0.0.128/25 | ALB |
| Private A (eu-north-1a) | 10.0.2.0/25 | ECS tasks, EFS mounts |
| Private B (eu-north-1b) | 10.0.2.128/25 | ECS tasks, EFS mounts |

ECS tasks sit in **private subnets** — no public IPs. Outbound traffic (ECR pulls, AWS API calls) routes through the **NAT Gateway** in the public subnet.

## Services

| Service | Image | Port | Description |
|---------|-------|------|-------------|
| ollama | ECR/ecs-fargate/ollama | 11434 | Self-hosted LLM (llama3.2:1b) |
| web | ECR/ecs-fargate/web | 8080 | FastAPI chat UI with pgvector |
| prometheus | ECR/ecs-fargate/prometheus | 9090 | Metrics collection (30-day retention) |
| alertmanager | ECR/ecs-fargate/alertmanager | 9093 | Alert routing to Telegram (sidecar) |
| grafana | ECR/ecs-fargate/grafana | 3000 | Monitoring dashboards |

## URLs (after terraform apply)

| Service | URL |
|---------|-----|
| Web Chat | `http://<alb-dns>/` |
| Grafana | `http://<alb-dns>/grafana` (admin / see Secrets Manager) |
| Prometheus | `http://<alb-dns>/prometheus` (admin IP only) |
| Ollama API | `http://<alb-dns>/api/version` |

Run `terraform output alb_dns_name` to get the ALB DNS.

## Prerequisites

- AWS CLI configured (`aws configure` or profile `terraform-oauth2`)
- Terraform >= 1.5.0
- Existing VPC with two public subnets (from previous task)
- GitHub repo with Actions secrets configured (see below)

## Quick Start

```bash
# 1. Configure secrets
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Deploy infrastructure
terraform init
terraform plan
terraform apply

# 3. Push Docker images (triggers CI/CD)
git push origin main
# GitHub Actions builds all 5 images and deploys them
```

## Terraform State

Remote state stored in S3 with DynamoDB locking:

| Resource | Name |
|----------|------|
| S3 bucket | `ecs-fargate-terraform-state-<account-id>` |
| DynamoDB table | `terraform-locks` |

> **Note:** The DynamoDB table is exclusively for **Terraform state locking** — it prevents two concurrent `terraform apply` runs from corrupting the state file. It has no connection to the LLM application or chat history.

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/deploy.yml`):

```
push to main
  └─ test          (terraform fmt + validate)
  └─ build-and-push (matrix: 5 services × ECR push)
       └─ image tag: <registry>/<project>/<service>:<7-char-sha>
       └─ Trivy vulnerability scan
  └─ deploy        (aws ecs update-service --force-new-deployment × 4)
       └─ Telegram notification (success/failure)

pull_request to main
  └─ terraform-plan (posts plan as PR comment)
```

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `DB_PASSWORD` | PostgreSQL password |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `GRAFANA_DB_PASSWORD` | Grafana DB password (reserved) |
| `TELEGRAM_BOT_TOKEN` | Alertmanager Telegram bot |
| `TELEGRAM_CHAT_ID` | Telegram chat/group ID |

## Monitoring

### Prometheus Scrape Targets

| Job | Target | Metrics |
|-----|--------|---------|
| prometheus | localhost:9090 | Prometheus self-metrics |
| web | web.ecs-fargate.local:8080 | HTTP requests, LLM calls, active connections |
| grafana | grafana.ecs-fargate.local:3000 | Grafana internal metrics |
| ollama | ollama.ecs-fargate.local:11434 | LLM inference metrics |
| alertmanager | localhost:9093 | Alert routing metrics |

### Grafana Dashboards

| Dashboard | Description |
|-----------|-------------|
| 01 Service Health & Resource Utilization | All services up/down, request rates, connections |
| 02 LLM Service Performance | Request rate, latency percentiles (P50/P90/P95/P99), error rate |
| 03 Web Service Usage Statistics | Traffic by endpoint, response times, 4xx/5xx rates |
| 04 Database Performance | Application-level DB health indicators |

### Alerts (Telegram)

| Alert | Condition | Severity |
|-------|-----------|----------|
| ServiceDown | Any service `up == 0` for 2m | critical |
| OllamaHighLatency | P95 > 30s for 5m | warning |
| OllamaNoRequests | No requests for 15m | info |
| WebHighErrorRate | 5xx > 5% | warning |
| HighMemoryUsage | Memory > 90% | warning |

## Auto-Scaling

| Service | Min | Max | Trigger |
|---------|-----|-----|---------|
| web | 1 | 4 | CPU > 60% |
| ollama | 1 | 2 | CPU > 70%, Memory > 80% |

## Security

- **IAM least privilege**: separate task roles per service (ollama, web, monitoring)
- **Secrets Manager**: all passwords injected at container start, never in code or env files
- **Private subnets**: ECS tasks have no public IPs — only reachable via ALB
- **NAT Gateway**: tasks reach ECR/AWS APIs outbound without public exposure
- **Security groups**: ECS tasks accept traffic only from ALB; PostgreSQL accepts only from ECS SG
- **ECR scanning**: Trivy CRITICAL/HIGH scan on every image push
- **GitHub Actions OIDC**: passwordless AWS auth — no long-lived keys in CI/CD

## Persistent Storage

EFS (`ecs-fargate-monitoring-efs`) with two access points:

| Access Point | Path | UID/GID | Used by |
|---|---|---|---|
| prometheus-ap | /prometheus | 65534 (nobody) | Prometheus TSDB (30-day retention) |
| grafana-ap | /grafana | 472 (grafana) | Grafana SQLite database |

## Module Structure

```
.
├── networking.tf           # Private subnets, NAT Gateway, route tables
├── main.tf                 # Root orchestration, secrets, Cloud Map
├── github_actions_iam.tf   # OIDC provider + GitHub Actions IAM role
├── variables.tf / outputs.tf
├── modules/
│   ├── ecr/                # 5 ECR repositories with lifecycle policies
│   ├── iam_ecs/            # Task execution + 3 task roles
│   ├── alb_ecs/            # ALB, target groups, path-based listener rules
│   ├── ecs/                # Cluster, task definitions, services, service discovery
│   ├── efs/                # Shared EFS with 2 access points
│   └── autoscaling/        # Target-tracking scaling for web + ollama
└── docker/
    ├── web/                # FastAPI + pgvector chat UI
    ├── ollama/             # Ollama LLM server with model pull on startup
    ├── prometheus/         # Prometheus + alerting rules
    ├── alertmanager/       # Telegram alert routing
    └── grafana/            # Grafana with provisioned datasource + 4 dashboards
```

## Troubleshooting

**ECS task stuck in PENDING**
```bash
aws ecs describe-tasks --cluster ecs-fargate-prod-cluster --tasks <arn>
# Check stoppedReason field
```

**Service unhealthy in ALB**
```bash
aws elbv2 describe-target-health --target-group-arn <arn>
```

**View container logs**
```bash
aws logs tail /ecs/ecs-fargate-prod --log-stream-name-prefix ecs/<service>
```

**Force redeploy**
```bash
aws ecs update-service --cluster ecs-fargate-prod-cluster \
  --service ecs-fargate-prod-<service> --force-new-deployment
```
