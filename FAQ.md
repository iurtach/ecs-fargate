# ECS Fargate LLM Platform — FAQ & Architecture Guide

A complete reference explaining every architectural decision, tool, and configuration in this project.

---

## Table of Contents

1. [What does this project do?](#1-what-does-this-project-do)
2. [Why ECS Fargate instead of EC2?](#2-why-ecs-fargate-instead-of-ec2)
3. [Network Architecture — Why private subnets + NAT?](#3-network-architecture)
4. [What is the ALB and why path-based routing?](#4-application-load-balancer)
5. [What is ECS and how do tasks/services work?](#5-ecs-concepts)
6. [What is ECR and how are images tagged?](#6-ecr-and-image-tagging)
7. [What is EFS and why do we need it?](#7-efs-persistent-storage)
8. [What is AWS Cloud Map (Service Discovery)?](#8-service-discovery)
9. [How does PostgreSQL fit in?](#9-postgresql-and-pgvector)
10. [What does DynamoDB do in this project?](#10-dynamodb--terraform-state-locking)
11. [How does monitoring work?](#11-monitoring-stack)
12. [How are alerts sent to Telegram?](#12-alerting-with-telegram)
13. [How does the CI/CD pipeline work?](#13-cicd-pipeline)
14. [How does GitHub Actions authenticate to AWS without passwords?](#14-github-actions-oidc)
15. [How are secrets managed?](#15-secrets-management)
16. [How does auto-scaling work?](#16-auto-scaling)
17. [What is Terraform remote state?](#17-terraform-remote-state)
18. [Problems encountered and how they were solved](#18-problems-and-solutions)
19. [Infrastructure cost considerations](#19-cost-considerations)

---

## 1. What does this project do?

It runs a self-hosted LLM chat application on AWS. Users open a web page, type a message, and the backend sends it to Ollama (a self-hosted LLM engine running llama3.2:1b). The conversation is stored in PostgreSQL with pgvector for semantic search.

Everything runs in containers on ECS Fargate — no server management, no SSH, no OS patching.

---

## 2. Why ECS Fargate instead of EC2?

| Concern | EC2 | Fargate |
|---------|-----|---------|
| Server management | You manage the OS, patching, Docker | AWS manages everything |
| Scaling | Manual or ASG (slow) | Automatic, per-task |
| Paying for idle | Yes — instance runs 24/7 | No — pay per task-second |
| Deployment | SSH + docker pull | Register new task definition, ECS rolling deploys |
| High availability | Manual across AZs | Built-in across AZs |

Fargate is "serverless containers" — you define what to run (CPU, memory, image, env vars) and AWS handles where and how to run it.

---

## 3. Network Architecture

### Why private subnets + NAT Gateway?

**Security**: ECS tasks should never have public IPs. Exposing containers directly to the internet creates attack surface. The only entry point is the ALB.

**How it works:**
```
Internet → IGW → ALB (public subnets) → [route to private subnets]
                                                ↓
                                        ECS Tasks (private subnets)
                                                ↓
                               NAT Gateway (in public subnet)
                                                ↓
                               ECR / Secrets Manager / CloudWatch
```

- **Public subnets (10.0.0.0/25, 10.0.0.128/25)**: ALB and NAT Gateway only.
- **Private subnets (10.0.2.0/25, 10.0.2.128/25)**: ECS tasks and EFS mount targets.
- **NAT Gateway**: Allows private subnet resources to make outbound calls (to pull Docker images from ECR, write logs to CloudWatch, read secrets) without being reachable from the internet.

### Why a secondary VPC CIDR (10.0.2.0/24)?

The original VPC (10.0.0.0/24) was fully used by two /25 public subnets from the previous project. There was no space for private subnets. AWS allows adding a secondary CIDR block to an existing VPC — this is how `networking.tf` creates the private subnets without touching the existing infrastructure.

### Why two AZs?

If one AWS data center (Availability Zone) goes down, the ALB and ECS tasks in the other AZ keep running. AWS requires ALBs to span at least two AZs.

---

## 4. Application Load Balancer

### What does it do?

The ALB is the single entry point from the internet. It receives all HTTP traffic and routes it to the right container based on the URL path.

### Path-based routing rules

| Priority | Path | Target | Why |
|----------|------|--------|-----|
| 10 | `/api/*` | Ollama :11434 | LLM API calls |
| 20 | `/grafana/*` | Grafana :3000 | Monitoring UI |
| 30 | `/prometheus/*` | Prometheus :9090 | Metrics UI (admin IP restricted) |
| default | `/*` | Web :8080 | Chat frontend |

Priority matters — rules are evaluated in order. The most specific paths have lower numbers (higher priority).

### Why is Prometheus IP-restricted?

Prometheus exposes raw metrics including internal application data. It's restricted to admin IP addresses via the `admin_cidr_blocks` variable to prevent public access.

### Health checks

Each target group has a health check. The ALB probes each container on a specific path every 30 seconds. If a container fails 3 checks in a row, the ALB stops sending traffic to it and ECS replaces the task.

---

## 5. ECS Concepts

### Cluster
A logical grouping of tasks. All 4 services run in `ecs-fargate-prod-cluster`. Container Insights is enabled for CloudWatch metrics.

### Task Definition
A blueprint describing one or more containers: which image, how much CPU/memory, environment variables, secrets, volumes, health checks, and log configuration. Every `terraform apply` creates a new revision. Think of it as a versioned Docker Compose service spec.

### Service
Keeps N copies of a task definition running. If a container crashes, ECS restarts it. Services are connected to ALB target groups and service discovery.

### Circuit Breaker
If a new deployment causes tasks to repeatedly fail health checks, ECS automatically rolls back to the previous task definition revision. Prevents bad deploys from taking down a service.

### Deployment (rolling)
When you update a service, ECS starts new tasks first (up to 200% desired count), waits for health checks to pass, then stops old tasks (minimum 50% healthy). No downtime.

### FARGATE_SPOT
The cluster is configured with both `FARGATE` and `FARGATE_SPOT` capacity providers. Spot instances can be 70% cheaper but may be interrupted. Production services use standard Fargate; Spot is available as a capacity option.

---

## 6. ECR and Image Tagging

### What is ECR?

Amazon Elastic Container Registry — a private Docker registry in AWS. ECS pulls images from ECR when starting tasks. No DockerHub rate limits, stays within the AWS network.

### Image tagging strategy

Each image is tagged with the **7-character git commit SHA**:
```
<account>.dkr.ecr.eu-north-1.amazonaws.com/ecs-fargate/<service>:<7-char-sha>
```

Example: `745247897380.dkr.ecr.eu-north-1.amazonaws.com/ecs-fargate/web:a1b2c3d`

**Why short SHA instead of `:latest`?**
- `:latest` is mutable — you can't tell what code is running
- Short SHA is immutable and traceable — every image maps to an exact commit
- Makes rollbacks easy: just redeploy a previous SHA
- 7 chars is enough to uniquely identify a commit in any repo

### Lifecycle policy

Each ECR repo retains the **last 10 tagged images** and removes untagged images after 1 day. This controls storage costs.

---

## 7. EFS Persistent Storage

### Why EFS for Prometheus and Grafana?

Fargate tasks are ephemeral — when a task stops and restarts, all local disk data is lost. Without persistent storage:
- Prometheus loses all historical metrics on every restart
- Grafana loses dashboards, users, and settings

EFS (Elastic File System) is a managed NFS that can be mounted into Fargate tasks. Data persists independently of the container lifecycle.

### Access points

Two access points on a single EFS filesystem:

| Access Point | Mount path | UID | Used by |
|---|---|---|---|
| prometheus-ap | /prometheus | 65534 | Prometheus TSDB |
| grafana-ap | /grafana | 472 | Grafana SQLite DB |

Access points enforce both the directory path and the Linux UID/GID, so each container gets its own isolated directory on the shared filesystem with the correct ownership.

### Why not EFS for the web service?

The web service is stateless — it has no local data to persist. State lives in PostgreSQL.

---

## 8. Service Discovery

### What is AWS Cloud Map?

A managed DNS service for internal service-to-service communication. Each ECS service registers its task IP addresses as DNS records under the namespace `ecs-fargate.local`.

| DNS name | Resolves to | Used by |
|----------|-------------|---------|
| `ollama.ecs-fargate.local` | Ollama task IP(s) | Web service, Prometheus |
| `web.ecs-fargate.local` | Web task IP(s) | Prometheus |
| `grafana.ecs-fargate.local` | Grafana task IP | Prometheus |
| `prometheus.ecs-fargate.local` | Prometheus task IP | Grafana datasource |

### Why not hardcode IPs?

Fargate task IPs change every time a task restarts or scales. Cloud Map automatically updates DNS when tasks start or stop. Services always reach each other by name, not IP.

---

## 9. PostgreSQL and pgvector

### What is it used for?

The web service stores chat conversation history and vector embeddings in PostgreSQL. The `pgvector` extension enables semantic similarity search — finding relevant past context when answering new questions.

### Where does it run?

On an EC2 instance running `postgres:15-alpine` in a Docker container. Two databases:
- `vectordb` — used by the web service for chat history and embeddings
- `grafana` — reserved (Grafana currently uses SQLite on EFS)

### Why EC2 instead of RDS?

Cost. RDS `db.t3.micro` costs ~$15/month. A `t3.micro` EC2 running PostgreSQL in Docker costs ~$7/month and serves the same purpose for a learning project.

---

## 10. DynamoDB — What it is, when to use it, and how

### What is DynamoDB?

DynamoDB is AWS's fully managed NoSQL database. It stores data as key-value pairs or documents (JSON-like). There is no SQL, no schema, no tables with fixed columns — you just store and retrieve items by a key.

### When to use DynamoDB (vs PostgreSQL)

| Use case | DynamoDB | PostgreSQL |
|----------|----------|------------|
| Simple lookups by ID (get user by ID, get session by token) | ✅ Perfect | Works but overkill |
| Chat message history (get all messages for session X) | ✅ Great fit | Works but overkill |
| Complex queries with joins | ❌ Not designed for this | ✅ Built for this |
| Vector similarity search (pgvector) | ❌ Not supported | ✅ With pgvector extension |
| Terraform state locking | ✅ Used for this | ❌ Not suitable |
| Metrics storage | ❌ Wrong tool | ✅ With TimescaleDB extension |

**Rule of thumb:** If your access pattern is always "give me items by this key", DynamoDB. If you need to filter, join, or search across many columns, PostgreSQL.

### How DynamoDB works

Every DynamoDB table has a **partition key** (required) and an optional **sort key**:

```
Table: ChatMessages
  partition_key: session_id      ← "give me all messages for this session"
  sort_key:      timestamp       ← "sorted by time"
  attributes:    role, content, created_at  ← any extra fields you want
```

You retrieve data by partition key:
```python
# Get all messages for a session, newest first
table.query(
    KeyConditionExpression=Key('session_id').eq('abc123'),
    ScanIndexForward=False
)
```

### How to create a DynamoDB table in Terraform

```hcl
resource "aws_dynamodb_table" "chat_messages" {
  name         = "chat-messages"
  billing_mode = "PAY_PER_REQUEST"   # no capacity planning needed
  hash_key     = "session_id"        # partition key
  range_key    = "timestamp"         # sort key

  attribute {
    name = "session_id"
    type = "S"   # S = String, N = Number, B = Binary
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}
```

### Terraform state locking with DynamoDB

One common use of DynamoDB is as a **lock mechanism for Terraform remote state**. When two people run `terraform apply` at the same time against the same S3 state file, they can corrupt it. DynamoDB prevents this:

1. `terraform apply` starts → writes a lock item to DynamoDB
2. Second `terraform apply` starts → sees the lock → waits or fails with a clear error
3. First apply finishes → deletes the lock item
4. Second apply can now proceed

```hcl
# The lock table (created once manually or via a bootstrap script)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Reference it in the backend config
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-locks"   # ← this enables locking
  }
}
```

**This project does not use DynamoDB locking** because there is only one contributor — concurrent `terraform apply` runs are impossible, so locking adds cost with no benefit. In a team of 2+ engineers, you would add it.

---

## 11. Monitoring Stack

### Prometheus

Collects metrics from all services every 15 seconds. Uses DNS-based service discovery to find container IPs automatically.

**Scrape jobs:**
- `prometheus` — self-metrics (localhost:9090)
- `web` — HTTP request metrics, LLM call metrics, active connections
- `grafana` — Grafana internal metrics
- `ollama` — LLM inference metrics
- `alertmanager` — alert routing metrics (sidecar on localhost:9093)

Data is stored on EFS for 30 days.

### Grafana Dashboards

Four dashboards provisioned automatically at startup:

**01 - Service Health & Resource Utilization**
Shows real-time up/down status for all 5 services, web and LLM request rates, and active connection counts.

**02 - LLM Service Performance**
Tracks Ollama inference: request rate by model, response latency percentiles (P50/P90/P95/P99), success/error rates.

**03 - Web Service Usage Statistics**
HTTP traffic breakdown by endpoint and status code, response time percentiles, error rates.

**04 - Database Performance**
Application-level database health indicators: `/chat` endpoint error rates and latency, LLM error rates (which surface pgvector query failures). Full PostgreSQL metrics (connections, cache hit ratio, query time) would require adding a `postgres_exporter` sidecar to the PostgreSQL host.

### Alertmanager

Runs as a sidecar container inside the Prometheus task. Receives alerts from Prometheus and routes them to Telegram.

Three receiver channels:
- `telegram-default` — standard alerts, grouped, repeated every 4 hours
- `telegram-critical` — immediate, repeated every hour
- `telegram-llm` — Ollama-specific alerts

Inhibition rule: if a critical alert fires for a service, warning alerts for the same service are suppressed.

---

## 12. Alerting with Telegram

### Why Telegram instead of Slack?

Both work. Telegram is free with no rate limits for bots. Slack free tier has message retention limits.

### Alert routing

```
Prometheus evaluates rules every 30s
  → fires if condition holds for 'for' duration
  → sends to Alertmanager (localhost:9093)
  → Alertmanager routes based on severity label
  → Telegram Bot API POST to chat_id
```

### Alert rules

| Alert | When | Duration | Severity |
|-------|------|----------|---------|
| ServiceDown | `up == 0` | 2 min | critical |
| OllamaHighLatency | P95 > 30s | 5 min | warning |
| OllamaNoRequests | No requests | 15 min | info |
| WebHighErrorRate | 5xx > 5% | — | warning |
| HighMemoryUsage | Memory > 90% | — | warning |
| PostgresDown | `pg_up == 0` | 1 min | critical |

---

## 13. CI/CD Pipeline

Three jobs in `.github/workflows/deploy.yml`:

### Job 1: test
- `terraform fmt -check -recursive` — fails if any file isn't formatted
- `terraform validate` — checks syntax and internal consistency without hitting AWS

### Job 2: build-and-push
- Matrix strategy: builds 5 images in parallel (ollama, web, prometheus, grafana, alertmanager)
- Authenticates to ECR using AWS keys from GitHub Secrets
- Tags image as `<registry>/<project>/<service>:<7-char-sha>` — **no `:latest` tag**
- Runs Trivy vulnerability scan (warns on CRITICAL/HIGH, doesn't fail the build)

### Job 3: deploy
- For each service: downloads current task definition → updates image tag → registers new revision → deploys
- Sends Telegram notification on success or failure

### Why no `:latest` tag?

`:latest` is mutable — two different deploys push different code to the same tag. You lose the ability to know which code is running.

With SHA-only tagging every image maps 1:1 to a git commit:
```
ecs-fargate/web:a1b2c3d  ← always this exact commit, forever
```

### Why render + deploy instead of `--force-new-deployment`?

**Old approach (wrong):**
```
Push new image with SHA tag → --force-new-deployment
```
Problem: `--force-new-deployment` restarts the service but keeps the **same task definition**. The task definition still references the **old SHA**. ECS pulls the old image.

**New approach (correct):**
```
1. Push new image with SHA tag
2. Download current task definition JSON from AWS
3. Swap the image field: old SHA → new SHA  (render step)
4. Register updated JSON as new task definition revision
5. Tell ECS service to use that new revision  (deploy step)
```

The task definition in AWS always shows the exact SHA running in production. Full audit trail: task definition revision → git commit → code change.

### The two GitHub Actions used

| Action | What it does |
|--------|-------------|
| `amazon-ecs-render-task-definition` | Takes task def JSON + new image URL → outputs updated JSON. Nothing created in AWS yet. |
| `amazon-ecs-deploy-task-def` | Takes updated JSON → registers new revision in AWS → updates service to use it. |

### Why does Prometheus need two render steps?

The Prometheus ECS task contains **two custom containers** (`prometheus` and `alertmanager`), both built from source and pushed to ECR. Render can only update one container at a time, so we chain two renders before deploying:
```
prometheus-task-def.json
  → render (update prometheus image)   → temp-1.json
  → render (update alertmanager image) → temp-2.json
  → deploy temp-2.json
```

### Why does the linter warn about `SHORT_SHA`?

`SHORT_SHA` is set dynamically at runtime via `echo "SHORT_SHA=..." >> $GITHUB_ENV`. The linter analyzes the file statically and cannot verify the variable will exist. At runtime it works correctly. This is a known linter limitation — not a real bug.

---

## 14. GitHub Actions OIDC

### What is it?

Instead of storing long-lived AWS access keys in GitHub Secrets, GitHub Actions can assume an AWS IAM role directly using a short-lived token. This is called OIDC (OpenID Connect).

### How it works

1. GitHub Actions requests a JWT from GitHub's OIDC provider
2. AWS IAM validates the JWT (checks it came from `token.actions.githubusercontent.com` and matches the expected repo)
3. AWS issues temporary credentials for the IAM role
4. No static keys ever stored — credentials expire after the workflow run

**Note:** The current pipeline uses static keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) for the build job because the OIDC role is set up for Terraform plan (read-only). The OIDC role and provider (`github_actions_iam.tf`) are ready to be migrated to for all jobs.

---

## 15. Secrets Management

All sensitive values are stored in AWS Secrets Manager, not in code or environment variables:

| Secret path | Used by | Injected as |
|-------------|---------|-------------|
| `/ecs-fargate/prod/db-password` | web | `DB_PASSWORD` |
| `/ecs-fargate/prod/telegram-bot-token` | alertmanager | `TELEGRAM_BOT_TOKEN` |
| `/ecs-fargate/prod/grafana-admin-password` | grafana | `GF_SECURITY_ADMIN_PASSWORD` |
| `/ecs-fargate/prod/grafana-db-password` | reserved | — |

ECS reads secrets from Secrets Manager at task startup and injects them as environment variables. The task execution IAM role has permission to read these specific secrets.

`terraform.tfvars` is listed in `.gitignore` — secret values are never committed to git.

---

## 16. Auto-Scaling

Target-tracking scaling — ECS automatically adjusts task count to keep metrics near target values.

| Service | Metric | Target | Min | Max |
|---------|--------|--------|-----|-----|
| web | CPU | 60% | 1 | 4 |
| ollama | CPU | 70% | 1 | 2 |
| ollama | Memory | 80% | 1 | 2 |

Scale-out is fast (60s cooldown) to handle traffic spikes. Scale-in is slower (120–300s cooldown) to avoid flapping.

Ollama max is capped at 2 because each instance needs 16GB RAM and pulls a ~1GB model — scaling too aggressively is expensive and slow.

---

## 17. Terraform Remote State

### Why remote state?

By default Terraform stores state locally in `terraform.tfstate`. This breaks team collaboration (everyone has different state) and is risky (lose the file = lose track of all resources).

Remote state in S3:
- Single source of truth for all infrastructure
- Versioned (S3 versioning enabled) — can recover from accidental state corruption
- S3 versioning allows recovery from accidental state corruption

### State file location

```
s3://ecs-fargate-terraform-state-<account-id>/prod/terraform.tfstate
```

---

## 18. Problems and Solutions

### Tasks stuck in PENDING — no public IP
**Symptom:** Tasks never reached RUNNING, stuck in PENDING indefinitely.
**Cause:** ECS tasks were configured with `assign_public_ip = false` in public subnets with no NAT Gateway. Tasks couldn't reach ECR to pull images.
**Fix:** Added NAT Gateway + private subnets. ECS tasks now live in private subnets and route outbound through NAT.

### EFS DNS resolution failing
**Symptom:** Prometheus/Grafana tasks failed to mount EFS — DNS name didn't resolve.
**Cause:** VPC had `enableDnsSupport = false` (disabled from previous project configuration).
**Fix:** Enabled `enableDnsSupport` and `enableDnsHostnames` on the VPC.

### EFS NFS connection refused
**Symptom:** EFS mount failed even after DNS resolved.
**Cause:** Security group had no inbound rule for NFS port 2049.
**Fix:** Added inbound rule allowing TCP 2049 from the ECS tasks security group to itself.

### ALB not reachable from internet
**Symptom:** ALB DNS resolved but connections timed out.
**Cause:** One of the two ALB subnets (eu-north-1b) had no route to the Internet Gateway in its route table.
**Fix:** Added `0.0.0.0/0 → igw` route to the eu-north-1b route table.

### Grafana "database is locked"
**Symptom:** Grafana returning 500, logs showing SQLite lock errors.
**Cause:** Rolling deployment started a second Grafana task before the first stopped. Both tasks tried to write to the same SQLite file on EFS simultaneously. SQLite doesn't support concurrent writers.
**Fix:** Scale service to 0 first, then back to 1 to ensure only one task runs at a time.

### GitHub Actions exit code 3 (terraform fmt)
**Symptom:** Test job failed with exit code 3.
**Cause:** Terraform files had inconsistent formatting — `terraform fmt -check` returns exit code 3 when formatting changes are needed.
**Fix:** Ran `terraform fmt -recursive .` and committed the reformatted files.

### PostgreSQL "no route to host"
**Symptom:** Grafana and web service logs showed `dial tcp <ip>:5432: no route to host`.
**Cause:** The EC2 instance running PostgreSQL was terminated. The IP in task definitions pointed to a non-existent host.
**Fix:** Launched a new EC2, deployed postgres:15-alpine in Docker, recreated databases, updated `db_host` in `terraform.tfvars` and task definitions.

---

## 19. Cost Considerations

Approximate monthly costs for this setup in eu-north-1:

| Resource | Approx cost |
|----------|-------------|
| Fargate: ollama (4vCPU/16GB × 1 task) | ~$110 |
| Fargate: web (0.5vCPU/1GB × 1-4 tasks) | ~$10–40 |
| Fargate: prometheus (1vCPU/2GB) | ~$20 |
| Fargate: grafana (0.5vCPU/1GB) | ~$10 |
| ALB | ~$20 |
| NAT Gateway | ~$35 |
| EFS (light use) | ~$1 |
| EC2 t3.micro (PostgreSQL) | ~$7 |
| ECR storage | ~$1 |
| Secrets Manager (4 secrets) | ~$2 |
| CloudWatch Logs | ~$3 |
| **Total** | **~$220/month** |

> Destroy with `terraform destroy` when not in use. The biggest cost is Fargate Ollama and NAT Gateway.
