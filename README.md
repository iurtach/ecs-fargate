# ECS Fargate — LLM Platform with Self-Hosted Monitoring

Migration of the LLM application from EC2 to AWS ECS Fargate with full observability stack.

## Architecture

```
Internet
    │
    ▼
┌───────────────────────────────────┐
│  Application Load Balancer (ALB)  │  Public Subnets (2 AZs)
│  path-based routing:              │
│  /         → Web UI (port 3000)   │
│  /grafana  → Grafana (port 3000)  │
│  /prometheus → Prometheus (9090)  │
└──────────┬────────────────────────┘
           │
           ▼ Private Subnets (2 AZs)
┌──────────────────────────────────────────────────────┐
│                  ECS Fargate Cluster                  │
│                                                       │
│  ┌──────────────┐   ┌──────────────┐                 │
│  │  Ollama      │   │  Web UI      │                 │
│  │  (4vCPU/16G) │   │  (0.5/1G)    │                 │
│  │  Port 11434  │◄──│  Port 3000   │                 │
│  └──────────────┘   └──────────────┘                 │
│                                                       │
│  ┌──────────────┐   ┌──────────────┐                 │
│  │  Prometheus  │   │  Grafana     │                 │
│  │  (1vCPU/2G)  │   │  (0.5/1G)    │                 │
│  │  Port 9090   │◄──│  Port 3000   │                 │
│  └──────┬───────┘   └──────────────┘                 │
│         │ scrape all services via CloudMap DNS        │
│         └─► Service Discovery: *.llm-platform.local  │
└──────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────┐    ┌─────────────────┐
│  EFS (persists  │    │  RDS PostgreSQL  │
│  Prometheus +   │    │  + pgvector      │
│  Grafana data)  │    │  (existing)      │
└─────────────────┘    └─────────────────┘
```

## Services

| Service    | Image           | CPU   | Memory | Port  | Scaling    |
|------------|-----------------|-------|--------|-------|------------|
| Ollama     | Custom (ECR)    | 4 vCPU| 16 GB  | 11434 | Manual     |
| Web UI     | Custom (ECR)    | 0.5   | 1 GB   | 3000  | Auto (1-4) |
| Prometheus | Custom (ECR)    | 1     | 2 GB   | 9090  | Fixed      |
| Grafana    | Custom (ECR)    | 0.5   | 1 GB   | 3000  | Fixed      |

## Prerequisites

- AWS CLI configured
- Terraform >= 1.5
- Docker
- Existing VPC with tags `Tier=private` / `Tier=public` on subnets
- Existing PostgreSQL RDS with identifier `${project_name}-postgres`
- Existing Secrets Manager secret `${project_name}/db/credentials`

## Quickstart

```bash
# 1. Clone & configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Create S3 state bucket + DynamoDB lock table (one-time)
aws s3 mb s3://your-terraform-state-bucket --region us-east-1
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# 3. Deploy infrastructure
terraform init
terraform plan
terraform apply

# 4. Build & push Docker images (or let CI/CD handle it)
aws ecr get-login-password | docker login --username AWS \
  --password-stdin $(terraform output -raw ecr_ollama_repository_url | cut -d/ -f1)

for svc in ollama web prometheus grafana; do
  docker build -t $(terraform output -raw ecr_${svc}_repository_url):latest ./docker/$svc
  docker push $(terraform output -raw ecr_${svc}_repository_url):latest
done

# 5. Access the platform
echo "Web UI:     http://$(terraform output -raw alb_dns_name)/"
echo "Grafana:    http://$(terraform output -raw alb_dns_name)/grafana"
echo "Prometheus: http://$(terraform output -raw alb_dns_name)/prometheus"
```

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/deploy.yml`) automates:

1. **Test** — Terraform format & validation checks on every push
2. **Build & Push** — Builds all 4 Docker images in parallel, pushes to ECR
3. **Security Scan** — Trivy vulnerability scan on every image
4. **Deploy** — Updates ECS task definitions and triggers rolling deployment
5. **Notifications** — Telegram messages for success/failure

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `TELEGRAM_BOT_TOKEN` | Alertmanager Telegram bot token |
| `TELEGRAM_CHAT_ID` | Telegram chat ID for notifications |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `ADMIN_CIDR` | CIDR allowed to access admin UIs |

### GitHub Actions IAM Role

Create an OIDC-connected IAM role for GitHub Actions:
```bash
# See modules/iam/github_actions_role.tf for the Terraform resource
```

## Monitoring

Prometheus scrapes all services via **AWS CloudMap DNS** (`*.llm-platform.local`).
Grafana is pre-provisioned with:
- ECS Fargate Overview dashboard
- Datasource auto-configured to Prometheus

**Alerts via Telegram** are configured in `docker/prometheus/alerting_rules.yml`:
- Service down
- High CPU / Memory
- Ollama latency
- PostgreSQL health

## Persistent Storage

Amazon EFS is used for monitoring data with separate access points:
- `/prometheus` — 30-day retention, TSDB storage
- `/grafana` — Dashboards and user data

Daily backups are enabled via AWS Backup integration.

## Security

- All tasks run in **private subnets** (no public IP)
- **Least-privilege IAM roles** per task
- Secrets stored in **AWS Secrets Manager** (injected at task start)
- ECR **image scanning** on every push
- **Security groups** follow deny-by-default principle
- EFS encrypted at rest + **TLS in transit**
