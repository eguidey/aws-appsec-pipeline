# Setup guide

Takes about 45 minutes the first time. Commands are shown for Windows PowerShell; they work the same on Mac/Linux.

---

## Part 0 - Install the tools (one time)

| Tool | Get it from | Check it works |
|---|---|---|
| Git | git-scm.com | `git --version` |
| Python 3.12 | python.org (tick **Add to PATH**) | `py --version` |
| AWS CLI v2 | aws.amazon.com/cli | `aws --version` |
| Terraform | developer.hashicorp.com/terraform/install (or `winget install Hashicorp.Terraform`) | `terraform -version` |
| Docker Desktop *(optional, for local builds)* | docker.com | `docker --version` |

Close and reopen your terminal after installing so the new commands are found.

---

## Part 1 - AWS account access for Terraform

1. Sign in to the AWS console as the root user and **turn on MFA** for root (Security credentials > MFA).
2. Go to **IAM > Users > Create user** and name it `terraform-admin`.
3. Attach the policy **AdministratorAccess**. Terraform creates IAM roles, so it needs broad rights. This user is only for you, on your machine.
4. Open the user > **Security credentials > Create access key > Command Line Interface (CLI)**. Copy both keys.
5. In your terminal:
   ```powershell
   aws configure
   # AWS Access Key ID:     <paste>
   # AWS Secret Access Key: <paste>
   # Default region name:   us-east-1
   # Default output format: json
   aws sts get-caller-identity    # should print your account number
   ```

> 🔒 Never put these keys in the repository or in GitHub. GitHub uses OIDC instead and never sees any keys. Delete the access key when you finish the project.

---

## Part 2 - Put the code on GitHub

Using Git (or PyCharm's Git features) avoids the folder-flattening problems of drag-and-drop uploads, especially for the hidden `.github` folder.

1. On GitHub, create a new **public** repository named **`aws-appsec-pipeline`**. Leave it empty (no README).
2. In a terminal inside the unzipped project folder:
   ```powershell
   git init
   git add .
   git commit -m "Initial commit: AWS AppSec pipeline"
   git branch -M main
   git remote add origin https://github.com/eguidey/aws-appsec-pipeline.git
   git push -u origin main
   ```
3. Open the **Actions** tab. The security stages (tests, Bandit, pip-audit, Gitleaks, Checkov, image build + Trivy) run and should all pass. **Push/deploy are skipped** for now, which is expected because AWS isn't set up yet.

---

## Part 3 - Create the AWS infrastructure

1. Find your public IP (so only you can reach the API):
   ```powershell
   (Invoke-WebRequest https://checkip.amazonaws.com).Content
   ```
2. In the `infra` folder, copy `terraform.tfvars.example` to **`terraform.tfvars`** and edit it:
   ```hcl
   alert_email           = "your-email@example.com"
   github_repository     = "eguidey/aws-appsec-pipeline"
   allowed_ingress_cidrs = ["YOUR.IP.ADDRESS/32"]
   ```
   `terraform.tfvars` is git-ignored, so it never gets committed.
3. Create everything:
   ```powershell
   cd infra
   terraform init
   terraform plan      # read through what will be created (roughly 50 resources)
   terraform apply     # type "yes"
   ```
   If you see *"EntityAlreadyExists ... token.actions.githubusercontent.com"*, your account already has the GitHub OIDC provider. Add `create_github_oidc_provider = false` to `terraform.tfvars` and run `terraform apply` again.
4. **Check your email** and click **Confirm subscription** in the message from AWS Notifications. Without this, alerts won't arrive.

---

## Part 4 - Connect GitHub to AWS

1. Show the values you need:
   ```powershell
   terraform output
   ```
2. In your GitHub repository: **Settings > Secrets and variables > Actions > Variables tab > New repository variable**. Add these six. They are **variables**, not secrets, because none of them are sensitive:

   | Name | Value from `terraform output` |
   |---|---|
   | `AWS_REGION` | `aws_region` |
   | `AWS_DEPLOY_ROLE_ARN` | `github_deploy_role_arn` |
   | `ECR_REPOSITORY` | `ecr_repository_name` |
   | `ECS_CLUSTER` | `ecs_cluster_name` |
   | `ECS_SERVICE` | `ecs_service_name` |
   | `ECS_TASK_FAMILY` | `ecs_task_family` |

3. *(Optional, recommended)* **Settings > Environments > New environment** named `production`. Tick **Required reviewers** and add yourself, so every deployment waits for your approval.

---

## Part 5 - First deployment

1. **Actions > AppSec Pipeline > Run workflow > Run workflow** (on `main`).
2. After the security gates pass, the image is pushed to ECR and the **Deploy** job starts. Approve it if you set up the environment reviewer.
3. The deploy job registers a new task definition, starts one Fargate task and waits for it to be healthy (about 2-4 minutes). The smoke test prints the task's public IP.

   The smoke test shows a warning if you limited `allowed_ingress_cidrs` to your own IP, because GitHub's servers can't reach it. That's expected; test from your own computer instead.

4. Test it from your computer (use the IP from the deploy log, or run the `find_public_ip_command` Terraform output):
   ```powershell
   curl http://<PUBLIC-IP>:8000/health
   curl http://<PUBLIC-IP>:8000/api/items
   ```

---

## Part 6 - Test the detections

1. Run the attack simulator against **your own** deployment:
   ```powershell
   py scripts/simulate_attacks.py http://<PUBLIC-IP>:8000
   ```
2. Within about 5 minutes you should get alarm emails for **brute_force**, **auth_failure_spike**, **injection_attempt** and **rate_limited**.
3. Investigate like an analyst:
   - **CloudWatch > Alarms**: see which fired and when.
   - **CloudWatch > Logs Insights > Saved queries** (`appsec-api/...`): run *top_source_ips* and *injection_attempts*.
   - **CloudWatch > Log groups > /ecs/appsec-api**: the raw JSON events.
4. Take screenshots of the pipeline run, an alarm email, and a Logs Insights result. They're useful for your README, a blog post, or an interview.

**Try the real login:** the password is in Secrets Manager (`appsec-api/demo-password`), where you can view it in the console. POST it to `/api/login` with username `analyst` to see an `auth_success` event.

---

## Part 7 - Tear down (don't skip!)

When you're done for the day, stop paying for the running task:

```powershell
aws ecs update-service --cluster appsec-api --service appsec-api --desired-count 0
```

When you're done with the project, remove **everything**:

```powershell
cd infra
terraform destroy    # type "yes"
```

Then delete the `terraform-admin` access key in IAM.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Deploy fails: *Not authorized to perform sts:AssumeRoleWithWebIdentity* | `github_repository` in `terraform.tfvars` must exactly match your repo (`owner/name`). Run `terraform apply` again after fixing it. |
| Deploy job skipped | The `AWS_DEPLOY_ROLE_ARN` variable is missing, or the run wasn't on `main`. |
| Task keeps stopping | Check **CloudWatch > Log groups > /ecs/appsec-api** and **ECS > Cluster > Service > Events**. The circuit breaker rolls back failed releases. |
| Trivy fails on a new CVE | Usually fixed by rebuilding (the image upgrades OS packages) or by bumping the version Dependabot suggests. |
| No alarm emails | Confirm the SNS subscription email (Part 3, step 4) and check spam. |
| `terraform destroy` fails on the ECR repository | Run it again; `force_delete` removes the images. |
