# EKS + Terraform + Jenkins CI/CD — Complete Setup Guide

## Project Structure

```
eks-terraform/
├── main.tf                     ← calls vpc + eks modules
├── providers.tf                ← AWS provider + S3 backend
├── variables.tf                ← all input variables
├── outputs.tf                  ← useful outputs after apply
├── terraform.tfvars.example    ← copy → terraform.tfvars and fill in
├── Jenkinsfile                 ← pipeline definition
├── jenkins-iam-policy.json     ← attach this policy to Jenkins EC2 role
├── .gitignore
└── modules/
    ├── vpc/
    │   ├── main.tf             ← VPC, subnets, IGW, NAT, route tables
    │   ├── variables.tf
    │   └── outputs.tf
    └── eks/
        ├── main.tf             ← EKS cluster + IAM roles + node group
        ├── variables.tf
        └── outputs.tf
```

---

## PART 1 — AWS Prerequisites

### Step 1 — Create the S3 bucket for Terraform state

```bash
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-east-1

# Enable versioning (lets you roll back state)
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
  }'
```

### Step 2 — Create DynamoDB table for state locking

```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Step 3 — Attach IAM policy to your Jenkins EC2 role

1. Go to **AWS Console → IAM → Roles**
2. Find the role attached to your Jenkins EC2 instance (e.g. `jenkins-ec2-role`)
3. Click **Add permissions → Create inline policy**
4. Paste the contents of `jenkins-iam-policy.json`
5. Name it `JenkinsTerraformEKSPolicy` → **Save**

> ✅ No access key or secret key needed anywhere.  
> The AWS SDK on the Jenkins EC2 instance automatically uses the instance metadata (IMDSv2).

---

## PART 2 — Local Setup (WSL / Ubuntu)

### Step 4 — Copy and fill in your tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set your region, cluster name, etc.
nano terraform.tfvars
```

> ⚠️  `terraform.tfvars` is in `.gitignore` — it will NOT be pushed to git.

### Step 5 — Update providers.tf with your bucket name

Open `providers.tf` and edit the backend block:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"   # ← your real bucket name
  key            = "eks/terraform.tfstate"
  region         = "us-east-1"                     # ← your region
  dynamodb_table = "terraform-state-lock"
  encrypt        = true
}
```

### Step 6 — Verify locally (optional but recommended)

```bash
# Configure AWS CLI with a profile that has permission
# (only needed locally — Jenkins uses IAM role automatically)
aws configure

# Init and validate
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars
```

---

## PART 3 — Push to Git

### Step 7 — Push to your repo

```bash
git init                              # if not already a git repo
git remote add origin <your-repo-url>
git add .
git commit -m "feat: add EKS terraform + Jenkinsfile"
git push origin main
```

> ✅ `.gitignore` ensures `terraform.tfvars`, `.terraform/`, and `tfplan.binary` are NOT pushed.

---

## PART 4 — Jenkins Setup

### Step 8 — Install required Jenkins plugins

Go to **Manage Jenkins → Plugin Manager → Available plugins**, install:

| Plugin | Why |
|---|---|
| **Pipeline** | Declarative pipeline support |
| **Git** | Checkout from git |
| **AnsiColor** | Coloured Terraform output |
| **Timestamper** | Timestamps in console |

### Step 9 — Verify Terraform is installed on Jenkins server

SSH into your Jenkins EC2 instance:

```bash
terraform -version
# If not installed:
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

### Step 10 — Create Jenkins Pipeline job

1. Jenkins Dashboard → **New Item**
2. Name: `eks-terraform-pipeline` → type: **Pipeline** → OK
3. Under **Pipeline**:
   - Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: your repo URL
   - Branch: `*/main`
   - Script Path: `eks-terraform/Jenkinsfile`
4. Click **Save**

### Step 11 — Run the pipeline

1. Click **Build with Parameters**
2. `TF_ACTION` → choose `plan-apply`
3. `TF_VAR_cluster_name` → leave default or override
4. Watch the stages:
   - **Checkout** → **Init** → **Validate** → **Plan** → **⏸ Approval** → **Apply**
5. At the **Approval** stage, click the link in console → review the plan → click **Yes, Apply!**

---

## PART 5 — After Deployment

### Step 12 — Configure kubectl on your local machine

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name my-eks-cluster

# Verify
kubectl get nodes
kubectl get pods -A
```

---

## Pipeline Flow Diagram

```
Push to Git
    │
    ▼
┌─────────────┐
│  Checkout   │
└──────┬──────┘
       │
┌──────▼──────┐
│ TF Init     │  terraform init (pulls providers, S3 backend)
└──────┬──────┘
       │
┌──────▼──────┐
│ TF Validate │  syntax + config check
└──────┬──────┘
       │
┌──────▼──────┐
│ TF Plan     │  saves plan to tfplan.binary, archives plan_output.txt
└──────┬──────┘
       │
┌──────▼──────┐
│ ⏸ APPROVAL  │  human reviews plan → clicks Proceed or Abort (30 min timeout)
└──────┬──────┘
       │
┌──────▼──────┐
│ TF Apply    │  applies the saved plan — no drift possible
└─────────────┘
```

---

## Common Issues & Fixes

| Problem | Fix |
|---|---|
| `Error: No valid credential sources` | Jenkins EC2 has no IAM role attached — go to EC2 console → Actions → Security → Modify IAM Role |
| `Error: S3 bucket not found` | Create the bucket first (Part 1 Step 1) |
| `terraform: command not found` | Install Terraform on Jenkins EC2 (Step 9) |
| `Error acquiring state lock` | Another run is in progress, or a previous run crashed — run `terraform force-unlock <LOCK_ID>` |
| Approval stage times out | Default 30 min — increase `timeout(time: 30...)` in Jenkinsfile |
| `kubectl: Unauthorized` | Re-run `aws eks update-kubeconfig` with the correct region/profile |
