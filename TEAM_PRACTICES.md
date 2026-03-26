# Team Practices — Learning Guide

Topics not implemented in this solo project but essential knowledge for team environments.

---

## 1. Terraform State Locking with DynamoDB

### Why it exists

Terraform stores all knowledge of your infrastructure in a state file (`terraform.tfstate`). When two engineers run `terraform apply` at the same time, both read the same state, both make changes, and one overwrites the other's work — leaving the state file corrupted and the infrastructure in an unknown state.

DynamoDB locking solves this by acting as a mutex: before `terraform apply` starts, it writes a lock record to DynamoDB. Any other `terraform apply` that tries to start sees the lock and waits (or fails with a clear error). When the first apply finishes, it deletes the lock.

### Why it's not in this project

Single contributor — there is never a concurrent `terraform apply`. Adding DynamoDB would be unused complexity.

### How it looks when enabled

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"   # ← this is the lock table
  }
}
```

```hcl
# The DynamoDB table itself (created once, manually or via bootstrap Terraform)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"               # ← Terraform always uses this key name

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

### What a lock looks like in DynamoDB

When an apply is running, a record appears in the table:
```json
{
  "LockID": "my-company-terraform-state/prod/terraform.tfstate",
  "Info": {
    "ID": "uuid",
    "Operation": "OperationTypeApply",
    "Who": "alice@workstation",
    "Version": "1.7.0",
    "Created": "2024-03-15T10:30:00Z",
    "Path": "prod/terraform.tfstate"
  }
}
```

### Force-unlocking a stuck lock

If an apply crashes mid-run, the lock is never released. You can manually remove it:
```bash
terraform force-unlock <LOCK_ID>
# or delete directly from DynamoDB
aws dynamodb delete-item \
  --table-name terraform-locks \
  --key '{"LockID": {"S": "my-bucket/prod/terraform.tfstate"}}'
```

### Learning resources

| Type | Resource |
|------|----------|
| Official docs | https://developer.hashicorp.com/terraform/language/settings/backends/s3 |
| Tutorial | https://developer.hashicorp.com/terraform/tutorials/aws/aws-remote |
| Video (TechWorld with Nana) | "Terraform Tutorial for Beginners" — covers remote state ~30 min mark |
| Video (Anton Babenko) | https://www.youtube.com/watch?v=7xngnjfIlK4 — Terraform best practices |
| Blog | https://spacelift.io/blog/terraform-s3-backend |
| Blog (state locking deep dive) | https://www.env0.com/blog/terraform-state-locking |

### When you will use this

- Any project with more than one person running `terraform apply`
- CI/CD pipelines where multiple branches might trigger `terraform apply` simultaneously
- Any "prod" infrastructure that must never have concurrent modifications

---

## 2. Pull Request Workflow in GitHub Actions

### Why it exists

In a team, no one pushes directly to `main`. Every change goes through a Pull Request:
1. Engineer creates a feature branch (`git checkout -b feature/add-nat-gateway`)
2. Pushes commits to that branch
3. Opens a PR to merge into `main`
4. GitHub Actions runs checks on the PR (tests, lint, security scan, terraform plan)
5. A teammate reviews the code and the CI results
6. After approval, the PR is merged — and CI/CD deploys to production

This prevents broken code from reaching `main` and gives teams visibility into what will change before it changes.

### Why it's not in this project

Single contributor, single branch (`main`). PRs are overhead with no benefit when you are both the author and the reviewer.

### How the workflow looks

```yaml
# .github/workflows/deploy.yml
on:
  push:
    branches: [main]          # ← triggers build + deploy
  pull_request:
    branches: [main]          # ← triggers checks only (no deploy)

jobs:
  test:
    # runs on both push and PR

  build-and-push:
    if: github.ref == 'refs/heads/main'   # ← only on merged commits, not PRs
    needs: test

  deploy:
    if: github.ref == 'refs/heads/main'   # ← only on merged commits, not PRs
    needs: build-and-push

  terraform-plan:
    if: github.event_name == 'pull_request'   # ← only on PRs, posts plan as comment
    permissions:
      pull-requests: write    # ← needed to post comments on PRs
    steps:
      - name: Terraform Plan
        run: terraform plan -no-color 2>&1 | tee plan.txt

      - name: Comment plan on PR
        uses: actions/github-script@v7
        with:
          script: |
            const plan = require('fs').readFileSync('plan.txt', 'utf8').slice(0, 60000);
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '## Terraform Plan\n```\n' + plan + '\n```'
            });
```

### What engineers see on a PR

On every PR opened against `main`, GitHub shows:

```
✅ test — Terraform fmt check passed, validate passed
✅ terraform-plan — Plan: 3 to add, 1 to change, 0 to destroy.
                    [full plan output as a PR comment]
```

A reviewer can look at the plan comment and see exactly which AWS resources will change before approving the merge.

### Branch protection rules

To enforce the PR workflow, teams add branch protection to `main`:

```
GitHub → Settings → Branches → Add rule for "main":
  ✅ Require a pull request before merging
  ✅ Require status checks to pass before merging
       → Select: "test", "terraform-plan"
  ✅ Require approvals: 1
  ✅ Do not allow bypassing the above settings
```

Now `git push origin main` is rejected for everyone, including repo owners.

### Terraform plan in PR comments — full example

The plan comment posted by GitHub Actions looks like this:

```
## Terraform Plan

Plan: 2 to add, 1 to change, 0 to destroy.

# module.ecs.aws_ecs_service.web will be updated in-place
~ resource "aws_ecs_service" "web" {
    ~ desired_count = 1 -> 2
  }

# aws_nat_gateway.this will be created
+ resource "aws_nat_gateway" "this" {
    + allocation_id = (known after apply)
    + subnet_id     = "subnet-08776b4ee365bf258"
  }
```

This makes infrastructure changes reviewable like code changes.

### Git branching model (for context)

In teams, a typical flow:

```
main ──────────────────────────────────●── (always deployable)
              ↑ merge via PR           │
feature/nat ──●──●──●                  │
                                       │
fix/grafana-db ──●──● ────────────────●
```

Common conventions:
- `feature/` — new functionality
- `fix/` — bug fixes
- `chore/` — dependency updates, refactoring
- `release/` — for projects with versioned releases

### Learning resources

| Type | Resource |
|------|----------|
| Official docs (GitHub Actions triggers) | https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows |
| Official docs (branch protection) | https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches |
| Official docs (PR environments) | https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment |
| Tutorial (Terraform + GitHub Actions) | https://developer.hashicorp.com/terraform/tutorials/automation/github-actions |
| Video (TechWorld with Nana) | "GitHub Actions Tutorial" — https://www.youtube.com/watch?v=R8_veQiYBjI |
| Video (DevOps Toolkit) | "Terraform in CI/CD" — https://www.youtube.com/watch?v=toaOZDAS7AE |
| Blog (Atlantis — dedicated Terraform PR tool) | https://www.runatlantis.io — purpose-built for Terraform PR workflows |

### Atlantis — worth knowing

Atlantis is an open-source tool specifically designed for the Terraform PR workflow. Instead of writing Terraform plan/apply steps in GitHub Actions YAML, you install Atlantis as a server and it handles everything automatically:

```
PR opened → Atlantis comments: terraform plan output
PR comment "atlantis apply" → Atlantis runs terraform apply, comments result
PR merged → done
```

Used by many companies for production Terraform workflows. Worth exploring once comfortable with the basics.
