# Production-Grade Kubernetes on AWS Free Tier (2026)

**Small-org production patterns** on **1× m7i-flex.large** (8 GB RAM) in **us-east-1** — fully automated from Windows/Cursor, strict $0 guardrails (no NAT, no ALB, no SSH).

---

## What you get

| Layer | Implementation |
|---|---|
| **IaC** | Terraform: VPC, EC2, SSM secrets, S3 (Velero + manifest delivery), IAM least-privilege |
| **Bootstrap** | cloud-init: kubeadm 1.29 + containerd + Calico v3.26 + local-path storage |
| **Access** | SSM Session Manager only (port 22 closed) |
| **Secrets** | `random_password` → SSM Parameter Store → External Secrets Operator |
| **Apps** | webapp (nginx) + api (Python/pymongo) → MongoDB StatefulSet + PVC |
| **Network** | Calico NetworkPolicies (default-deny), ingress locked to **your IP/32** |
| **Reliability** | PDBs, ResourceQuota, LimitRange, Pod Security Admission (baseline) |
| **Ingress** | nginx-ingress v1.11.1 baremetal, NodePort **30080** |
| **TLS** | cert-manager + self-signed ClusterIssuer |
| **Metrics** | metrics-server (with `--kubelet-insecure-tls` for kubeadm lab) |
| **Monitoring** | Prometheus + Alertmanager + Grafana (password from SSM, anonymous disabled) |
| **Logging** | Fluent Bit DaemonSet |
| **Backup** | Velero → S3 (5 GB free tier, 30-day lifecycle) |
| **CI** | GitHub Actions: `terraform validate` + yamllint |
| **Verify** | 35 automated checks → `verify.log` |

---

## Prerequisites (one-time)

Install on your Windows machine:

| Tool | Purpose | Verify |
|---|---|---|
| [AWS CLI v2](https://aws.amazon.com/cli/) | Terraform + deploy scripts | `aws --version` |
| [Terraform ≥ 1.5](https://developer.hashicorp.com/terraform/install) | Infrastructure | `terraform version` |
| PowerShell 5.1+ | Scripts | `$PSVersionTable.PSVersion` |

AWS account requirements:

- **2026 account** (or account where **m7i-flex.large** is free-tier eligible in **us-east-1**)
- IAM permissions for EC2, VPC, IAM, SSM, S3
- Free-tier credits active (~$100 for 6 months post–July 2025 model)

---

## Step-by-step: deploy the lab

### 1. Clone and open in Cursor

```powershell
cd c:\dev\k8AWS
```

### 2. Authenticate to AWS

```powershell
aws login
aws sts get-caller-identity
```

You must see your Account ID. If this fails, fix credentials before continuing.

### 3. Preflight checks

```powershell
.\scripts\preflight.ps1
```

This validates AWS credentials, tools in PATH, m7i-flex.large free-tier eligibility, and Terraform config.

### 4. Deploy (~20–35 minutes first run)

```powershell
.\scripts\deploy.ps1
```

What happens automatically:

1. Creates `terraform/terraform.tfvars` from your public IP (`checkip.amazonaws.com`) if missing
2. `terraform apply` — VPC, EC2, SSM parameters, S3 bucket, IAM
3. Waits for SSM agent + kubeadm bootstrap (`/var/lib/k8s-ready`)
4. Syncs manifests to S3 (avoids SSM 4096-char command limit)
5. Installs platform add-ons: metrics-server, cert-manager, nginx-ingress, External Secrets
6. Syncs secrets from SSM → Kubernetes via ESO
7. Deploys observability stack, **NetworkPolicies**, mongo → api → webapp, ingress
8. Optionally installs Velero + first backup

Non-interactive (CI / automation):

```powershell
$env:K8AWS_AUTO_APPROVE = "true"
.\scripts\deploy.ps1
```

When deploy finishes, note the printed URLs and instance ID.

### 5. Verify (35 checks)

```powershell
.\scripts\verify.ps1
```

Results are written to `verify.log`. All 35 checks should pass. If any fail, see [Troubleshooting](#troubleshooting).

### 6. Use the endpoints

Replace `<PUBLIC_IP>` with the IP from deploy output or:

```powershell
cd terraform
terraform output -raw public_ip
```

| Service | URL |
|---|---|
| Webapp | `http://<PUBLIC_IP>:30080/webapp` |
| API (Mongo health) | `http://<PUBLIC_IP>:30080/api` |
| Grafana | `http://<PUBLIC_IP>:30300` |

**Grafana login** (never stored in Git):

```powershell
aws ssm get-parameter --name /k8AWS/grafana-admin-password --with-decryption --region us-east-1 --query Parameter.Value --output text
```

Username: `admin`

### 7. Destroy when done (required)

```powershell
.\scripts\destroy.ps1
```

Type `destroy` when prompted. This removes EC2, VPC, S3 bucket, SSM parameters, and IAM users — stopping ~$0.096/hr compute charges.

Non-interactive destroy:

```powershell
$env:K8AWS_AUTO_APPROVE = "true"
.\scripts\destroy.ps1
```

---

## Configuration

Copy and edit if you need custom settings:

```powershell
copy terraform\terraform.tfvars.example terraform\terraform.tfvars
```

Key variables:

| Variable | Default | Notes |
|---|---|---|
| `allowed_ingress_cidr` | auto `/32` | **Must** be your public IP for security |
| `allow_public_ingress` | `false` | Set `true` only with `0.0.0.0/0` (not recommended) |
| `enable_velero_bucket` | `true` | Required for manifest S3 delivery + backups |
| `instance_type` | `m7i-flex.large` | Hard-coded guardrail — cannot change |
| `aws_region` | `us-east-1` | Hard-coded guardrail — cannot change |

If your IP changes mid-lab, update `allowed_ingress_cidr` in `terraform.tfvars` and run `terraform apply`.

---

## Architecture

```
Windows (Cursor)
    │
    ├── deploy.ps1 ──► Terraform ──► EC2 m7i-flex.large (us-east-1)
    │                      │              ├── Custom VPC + IGW (no NAT)
    │                      │              ├── SSM Parameter Store (secrets)
    │                      │              ├── S3 bucket (manifests + Velero)
    │                      │              └── cloud-init → kubeadm cluster
    │
    └── verify.ps1 ──► HTTP checks + SSM kubectl checks

Kubernetes (single node):
    ├── webapp (nginx) + HPA
    ├── api → MongoDB (NetworkPolicy enforced)
    ├── mongo StatefulSet + local-path PVC
    ├── nginx Ingress (NodePort 30080)
    ├── cert-manager (self-signed issuer)
    ├── metrics-server + Prometheus + Alertmanager + Grafana
    ├── Fluent Bit
    └── Velero → S3 daily backup (app namespace)
```

---

## Troubleshooting

### Deploy stuck on “Waiting for kubeadm bootstrap”

```powershell
.\scripts\logs.ps1
```

Bootstrap log: `/var/log/kubeadm-init.log` on the instance.

### SSM not online

Wait 2–5 minutes after EC2 launch. Then:

```powershell
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

### ExternalSecrets not syncing

```powershell
.\scripts\helpers\ssm-exec.ps1 -Command "kubectl describe externalsecret -A"
.\scripts\helpers\ssm-exec.ps1 -Command "kubectl get clustersecretstore aws-ssm -o yaml"
```

### API returns 503 / mongo_ok=False

Usually mongo not ready or NetworkPolicy issue:

```powershell
.\scripts\helpers\ssm-exec.ps1 -Command "kubectl get pods -n app"
.\scripts\helpers\ssm-exec.ps1 -Command "kubectl logs -n app -l app=api --tail=50"
```

### HTTP checks fail from verify but pods are Running

- Confirm you are on the same public IP used in `allowed_ingress_cidr`
- Security group only allows **your IP/32** on ports 30080 and 30300

### Velero failed (non-fatal)

Deploy continues. Cluster works without Velero. Re-run Velero steps manually via SSM if needed.

---

## Cost

| Resource | Approximate cost |
|---|---|
| m7i-flex.large | ~$0.096/hr (from free-tier credits) |
| S3 Velero + manifests | Within 5 GB free tier |
| NAT Gateway | **Not created** |
| ALB | **Not created** |

**3-hour lab ≈ $0.29** — always run `destroy.ps1`.

---

## Honest reliability assessment

| Question | Answer |
|---|---|
| Will this work **100%** guaranteed? | **No** — not without a live end-to-end run on your account. Upstream URLs (Calico, ingress-nginx, ESO, apt k8s packages) can change; free-tier eligibility varies by account age. |
| Expected success rate after fixes | **~90–95%** on a fresh 2026 account with valid credits and stable internet |
| Structural limits (by design) | Single-node (no HA), `--kubelet-insecure-tls`, static IAM keys for ESO/Velero, self-signed TLS only, 8 GB RAM ceiling |
| What would improve it further | Live E2E test in CI, IRSA instead of static keys, pre-built api image (no pip at runtime), second worker node, real DNS + Let's Encrypt |

---

## Optional upgrades (when budget allows)

- Second worker EC2 + `kubeadm join`
- AWS Load Balancer Controller + ALB
- ArgoCD or Flux GitOps
- EKS managed control plane
- Amazon RDS / DocumentDB instead of in-cluster MongoDB

---

## Project layout

```
k8AWS/
├── terraform/          # VPC, EC2, SSM, S3, IAM
├── manifests/          # Kubernetes YAML (apps, policies, observability)
├── scripts/
│   ├── preflight.ps1   # Pre-deploy validation
│   ├── deploy.ps1      # Full deploy pipeline
│   ├── verify.ps1      # 35 post-deploy checks
│   ├── destroy.ps1     # Tear down everything
│   ├── logs.ps1        # Remote bootstrap logs
│   └── helpers/ssm-exec.ps1
└── .github/workflows/ci.yaml
```

---

## CI

On push/PR: `terraform validate` and yamllint on manifests. Does not deploy to AWS (no credentials in CI by default).
