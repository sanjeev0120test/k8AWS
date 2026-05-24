# Production-Grade Kubernetes on AWS Free Tier (2026)

**Small-org production patterns** on **1× m7i-flex.large** (8 GB RAM) in **us-east-1** — fully automated from Windows/Cursor, strict $0 guardrails (no NAT, no ALB, no SSH).

**All documentation lives in this file.** Stack reference, diagrams, manual build steps, troubleshooting, and SRE review — nothing else required.

---

## Real-world problems this lab solves

| Scenario | Without this stack | How k8AWS solves it |
|---|---|---|
| **Learn kubeadm without EKS cost** | EKS control plane ~$73/mo | Self-managed cluster on free-tier EC2 (~$0.096/hr credits) |
| **Secrets in Git leak in PRs** | Passwords in YAML or `.env` committed | Terraform → SSM → External Secrets → pods; never in Git |
| **"Pods Running" but app broken** | No end-to-end verification | 35 checks: infra + SSM + HTTP + mongo_ok=True |
| **Forgotten lab drains credits** | EC2/NAT left running overnight | `destroy.ps1` + S3 `force_destroy` + no NAT by design |
| **SSH keys on public instances** | Port 22 scanned globally | SSM Session Manager only — outbound HTTPS |
| **Any pod talks to any pod** | Lateral movement in breaches | Calico default-deny NetworkPolicy with explicit allows |
| **Large YAML over SSM fails silently** | 4096-char Run Command limit | Manifests synced to S3; node pulls via IAM |
| **Stateful app on ephemeral disk** | Mongo data lost on restart | StatefulSet + local-path PVC (2 Gi) |
| **No observability in homelab** | Blind when api/mongo fails | Prometheus, Grafana, Fluent Bit, Alertmanager |
| **No backup story** | Rebuild from scratch after mistake | Velero daily backup of `app` namespace to S3 |

---

## Table of contents

| Section | What it covers |
|---|---|
| [Real-world problems](#real-world-problems-this-lab-solves) | What this project fixes |
| [Start now](#start-now-immediate-steps) | 4 commands to deploy |
| [Complete technology stack](#complete-technology-stack) | All 27 technologies — definitions, why, use cases |
| [Full manual build](#full-manual-build-procedure-phases-ak) | Phase-by-phase create guide |
| [Critical run checklist](#critical-run-checklist) | Pre-flight checks for smooth deploy |
| [What you get](#what-you-get) | Summary table |
| [Quick local execution](#quick-local-execution-3-commands) | Automated deploy |
| [Engineering architecture](#engineering-architecture) | System diagram |
| [AWS network topology](#aws-network-topology) | VPC / security group diagram |
| [Deploy flowchart](#end-to-end-deploy-flowchart) | deploy.ps1 sequence |
| [HTTP request path](#http-request-path-runtime) | Runtime sequence diagram |
| [Secrets lifecycle](#secrets-lifecycle) | SSM → ESO → pods |
| [Prerequisites](#prerequisites-one-time) | Tools and AWS account |
| [Step-by-step deploy](#step-by-step-deploy-the-lab) | Detailed walkthrough |
| [Configuration](#configuration) | terraform.tfvars variables |
| [Troubleshooting](#troubleshooting) | Common failures |
| [Project layout](#project-layout) | Folder tree |
| [SRE structure review](#sre-production-structure-review) | Production expert assessment |

---

## Complete technology stack

Every technology below includes: **official definition**, **why we use it**, **the real problem it solves in this project**, **files**, and **how to create/configure it**.

### Stack inventory

| # | Technology | Version / pin | Official docs |
|---|---|---|---|
| 1 | Terraform | ≥ 1.5 | [terraform.io/docs](https://developer.hashicorp.com/terraform/docs) |
| 2 | AWS Provider | ~> 5.0 | [registry.terraform.io/hashicorp/aws](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) |
| 3 | Amazon VPC | — | [docs.aws.amazon.com/vpc](https://docs.aws.amazon.com/vpc/latest/userguide/) |
| 4 | Amazon EC2 | m7i-flex.large | [docs.aws.amazon.com/ec2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/) |
| 5 | AWS SSM Session Manager | — | [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) |
| 6 | AWS SSM Parameter Store | — | [Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) |
| 7 | Amazon S3 | — | [docs.aws.amazon.com/s3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/) |
| 8 | AWS IAM | — | [docs.aws.amazon.com/iam](https://docs.aws.amazon.com/IAM/latest/UserGuide/) |
| 9 | Ubuntu Server | 24.04 Noble | [ubuntu.com/server/docs](https://ubuntu.com/server/docs) |
| 10 | containerd | apt package | [containerd.io/docs](https://containerd.io/docs/) |
| 11 | kubeadm / kubelet / kubectl | 1.29 | [kubeadm docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/) |
| 12 | Calico CNI | v3.26.0 | [docs.tigera.io/calico](https://docs.tigera.io/calico/latest/about/) |
| 13 | local-path-provisioner | v0.0.28 | [GitHub](https://github.com/rancher/local-path-provisioner) |
| 14 | metrics-server | v0.7.1 | [GitHub](https://github.com/kubernetes-sigs/metrics-server) |
| 15 | cert-manager | v1.14.5 | [cert-manager.io/docs](https://cert-manager.io/docs/) |
| 16 | nginx-ingress | v1.11.1 | [ingress-nginx docs](https://kubernetes.github.io/ingress-nginx/) |
| 17 | External Secrets Operator | v0.9.20 | [external-secrets.io](https://external-secrets.io/latest/) |
| 18 | Velero | v1.14.0 | [velero.io/docs](https://velero.io/docs/) |
| 19 | MongoDB | 7 | [mongodb.com/docs](https://www.mongodb.com/docs/) |
| 20 | nginx (app) | 1.27.3-alpine | [nginx.org/en/docs](https://nginx.org/en/docs/) |
| 21 | Python / pymongo | 3.12 / 4.7.3 | [pymongo docs](https://pymongo.readthedocs.io/) |
| 22 | Prometheus | 2.x image | [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) |
| 23 | Alertmanager | 0.x image | [Alertmanager docs](https://prometheus.io/docs/alerting/latest/alertmanager/) |
| 24 | Grafana | 11.0.0 | [grafana.com/docs](https://grafana.com/docs/grafana/latest/) |
| 25 | Fluent Bit | latest stable | [docs.fluentbit.io](https://docs.fluentbit.io/manual/) |
| 26 | PowerShell | 5.1+ | [Microsoft docs](https://learn.microsoft.com/en-us/powershell/) |
| 27 | GitHub Actions | — | [docs.github.com/actions](https://docs.github.com/en/actions) |

---

### Layer 1 — Local tooling

#### Terraform
- **Definition:** IaC tool — declare AWS resources in HCL, provision via provider APIs.
- **Real use case:** Same lab for every teammate; peer-reviewed infra changes; one-command teardown.
- **Problem solved:** Console-clicked resources cannot be reliably destroyed or reproduced. Terraform enforces `m7i-flex.large` only, `us-east-1` only, no NAT.
- **Files:** `terraform/*.tf`, `terraform/user-data/kubeadm-init.sh`
- **Create:** `cd terraform && terraform init && terraform apply`

#### AWS CLI v2
- **Definition:** Unified CLI for all AWS service APIs.
- **Real use case:** Run remote `kubectl` via SSM without installing kubeconfig locally or opening port 22.
- **Problem solved:** Post-Terraform orchestration from a Windows laptop.
- **Files:** `scripts/*.ps1`, `scripts/helpers/ssm-exec.ps1`

#### PowerShell
- **Definition:** Task automation shell for Windows.
- **Real use case:** CI/CD-style pipeline on a developer machine — preflight → deploy → verify → destroy.
- **Problem solved:** 30+ manual steps collapsed into `deploy.ps1`.
- **Files:** `scripts/preflight.ps1`, `deploy.ps1`, `verify.ps1`, `destroy.ps1`, `logs.ps1`

---

### Layer 2 — AWS infrastructure

#### VPC + Internet Gateway
- **Definition:** Isolated virtual network (`10.0.0.0/16`) with internet routing via IGW.
- **Real use case:** Dedicated lab network — not mixed with default VPC resources.
- **Problem solved:** Clean `terraform destroy` deletes entire stack; public subnet avoids **NAT Gateway (~$32+/mo)**.
- **Resources:** VPC `10.0.0.0/16`, public subnet `10.0.1.0/24` in `us-east-1a`, route `0.0.0.0/0` → IGW.
- **Files:** `terraform/vpc.tf`

#### EC2 m7i-flex.large
- **Definition:** 2 vCPU, 8 GiB RAM compute instance running Ubuntu 24.04 Noble.
- **Real use case:** Host control plane + all workloads on one node for free-tier learning.
- **Problem solved:** EKS control-plane cost avoided; enough RAM for observability + apps.
- **Config:** 20 GiB gp3 encrypted root, IMDSv2 required, public IP, **no SSH (port 22)**, bootstrap via `user_data`.
- **Files:** `terraform/ec2.tf`, `terraform/user-data/kubeadm-init.sh`

#### SSM Session Manager + Run Command
- **Definition:** Managed access and remote command execution without inbound ports.
- **Real use case:** Production-style admin — audit trail, no bastion, no SSH key rotation.
- **Problem solved:** All `kubectl apply` runs via `AWS-RunShellScript` from `deploy.ps1`.
- **Connect:** `aws ssm start-session --target <INSTANCE_ID> --region us-east-1`
- **Files:** `terraform/ec2.tf` (IAM `AmazonSSMManagedInstanceCore`), `scripts/helpers/ssm-exec.ps1`

#### SSM Parameter Store
- **Definition:** Encrypted hierarchical secret/config storage.
- **Real use case:** Same pattern as AWS Secrets Manager + EKS External Secrets in production.
- **Problem solved:** Mongo/Grafana passwords and IAM keys never touch Git or Kubernetes YAML.
- **Parameters:** `/k8AWS/mongo-password`, `/k8AWS/grafana-admin-password`, ESO/Velero IAM keys (see table below).
- **Files:** `terraform/secrets.tf`, `terraform/ssm-parameters.tf`, `terraform/velero-s3.tf`

| Path | Content |
|---|---|
| `/k8AWS/mongo-username` | `admin` |
| `/k8AWS/mongo-password` | random 24-char |
| `/k8AWS/grafana-admin-username` | `admin` |
| `/k8AWS/grafana-admin-password` | random 20-char |
| `/k8AWS/eso-access-key-id` | ESO IAM key |
| `/k8AWS/eso-secret-access-key` | ESO IAM secret |
| `/k8AWS/velero-access-key-id` | Velero IAM key |
| `/k8AWS/velero-secret-access-key` | Velero IAM secret |
| `/k8AWS/velero-bucket` | S3 bucket name |

#### S3
- **Definition:** Durable object storage.
- **Real use case (1):** Manifest delivery — EC2 pulls YAML from `s3://k8aws-velero-<ACCOUNT>/manifests/`.
- **Real use case (2):** Velero backup target with 30-day lifecycle expiration.
- **Problem solved:** SSM Run Command **4096-character limit** breaks large manifest apply; S3 is the production-style workaround.
- **Files:** `terraform/velero-s3.tf` (`force_destroy = true` for clean teardown), `manifests/backup/velero-config.yaml`

#### IAM (least privilege)
| Principal | Permissions | Problem solved |
|---|---|---|
| EC2 instance role | SSM core + read `/k8AWS/*` SSM + read S3 manifests | Node ops without static keys on disk |
| IAM user `k8AWS-eso-reader` | `ssm:GetParameter` on `/k8AWS/*` | ESO reads only what it needs |
| IAM user `k8AWS-velero` | S3 read/write on Velero bucket | Backup isolation from ESO |

---

### Layer 3 — Node bootstrap (cloud-init)

Executed on first boot. Log: `/var/log/kubeadm-init.log`. Ready marker: `/var/lib/k8s-ready`.

| Step | Why | Problem if skipped |
|---|---|---|
| Disable swap | kubelet requirement | kubelet refuses to start |
| containerd + SystemdCgroup | Kubernetes CRI (not Docker) | dockershim removed since K8s 1.24 |
| kubeadm init 1.29, pod CIDR `192.168.0.0/16` | Conformant control plane | No cluster |
| Calico v3.26 | CNI + **NetworkPolicy** | Flannel alone cannot enforce policy |
| local-path-provisioner v0.0.28 | Dynamic PVC on node disk | mongo has no persistent storage |
| Remove control-plane taint | Single-node scheduling | Apps stuck Pending |
| Write `/var/lib/k8s-ready` | Signal for deploy.ps1 | Race — apps applied before cluster ready |

**Monitor:** `.\scripts\logs.ps1` or `ssm-exec.ps1 -Command "tail -50 /var/log/kubeadm-init.log"`

**File:** `terraform/user-data/kubeadm-init.sh`

---

### Layer 4 — Kubernetes platform add-ons

| Component | Definition | Real use case | Problem solved | Pin |
|---|---|---|---|---|
| **metrics-server** | Aggregates pod/node CPU/memory | HPA on webapp; `kubectl top` | Without it, HPA and verify check #27 fail | v0.7.1 + `--kubelet-insecure-tls` |
| **cert-manager** | Automates TLS certificates | Production cert workflow demo | Manual cert rotation doesn't scale | v1.14.5 |
| **nginx-ingress** | L7 Ingress controller (NGINX) | Route `/webapp` and `/api` on one NodePort | ALB costs ~$16+/mo — avoid on lab | controller v1.11.1 baremetal |
| **External Secrets** | Syncs external vault into K8s Secrets | EKS + Secrets Manager pattern on kubeadm | Hardcoded secrets in Deployments | v0.9.20 |

**ClusterIssuer:** self-signed (`manifests/security/cert-manager-issuer.yaml`) — swap for Let's Encrypt when you have a domain.

---

### Layer 5 — Secrets management

```mermaid
flowchart LR
    TF["Terraform random_password"] --> SSM["SSM SecureString"]
    SSM --> ESO["External Secrets Operator"]
    ESO --> KS["K8s Secrets"]
    KS --> POD["Pod secretKeyRef"]
```

| Resource | Purpose |
|---|---|
| `ClusterSecretStore` `aws-ssm` | ESO → Parameter Store connection |
| `ExternalSecret` `mongo-credentials` | Mongo root user/pass in `app` namespace |
| `ExternalSecret` `grafana-admin-credentials` | Grafana login in `observability` namespace |

**Real use case:** Rotate password in SSM → ESO refreshes K8s Secret → restart pod. No Terraform re-apply for app secrets.

**Files:** `terraform/secrets.tf`, `manifests/secrets/external-secrets.yaml`

---

### Layer 6 — Application workloads

| Workload | Kind | Real use case | Problem solved | File |
|---|---|---|---|---|
| **webapp** | Deployment + HPA | Stateless front-end behind ingress | Proves L7 routing + autoscaling | `microservices/webapp-deployment.yaml` |
| **api** | Deployment + initContainer | Service-to-service health check | Proves secrets + api→mongo path; verify checks `mongo_ok=True` | `microservices/api-deployment.yaml` |
| **mongo** | StatefulSet + 2Gi PVC | Persistent database | Data survives pod restart; stable DNS `mongo-0` | `database/mongo-statefulset.yaml` |

**Deploy order (enforced in deploy.ps1):** mongo Ready → api → webapp → ingress.

**Why StatefulSet for mongo:** Deployments don't guarantee stable network identity or PVC binding — wrong tool for databases.

---

### Layer 7 — Networking and security

| Component | Real use case | Problem solved |
|---|---|---|
| **NetworkPolicy default-deny** | Zero-trust pod networking | Compromised pod cannot scan entire cluster |
| **SG YOUR_IP/32** | Lock NodePorts 30080/30300 | Public IP without open-to-world |
| **PSA baseline** on `app` ns | Block privileged pods | Aligns with production cluster policy |
| **PDB minAvailable: 1** | Survive voluntary disruptions | Pattern for when you scale to 2+ replicas |
| **ResourceQuota + LimitRange** | Cap namespace on 8 GiB node | One runaway Deployment can't OOM the node |

**NetworkPolicy rules (6):** `default-deny-all` · `allow-dns-egress` · `allow-ingress-to-webapp-api` · `allow-clients-to-mongo` · `allow-api-egress-mongo` · `allow-api-egress-https` (PyPI for api initContainer)

**Files:** `manifests/networking/networkpolicy.yaml`, `ingress-rules.yaml`, `nginx-ingress-nodeport.yaml`, `policy/guardrails.yaml`, `namespace/app-namespace.yaml`

---

### Layer 8 — Observability

| Component | Real use case | Problem solved | Access |
|---|---|---|---|
| **Prometheus** | Scrape pod metrics via annotations | Know when api/webapp degrade before users do | ClusterIP |
| **Alertmanager** | Route/deduplicate alerts | Production alert pipeline (add Slack/PagerDuty later) | ClusterIP |
| **Grafana** | Dashboards for humans | Visual confirmation cluster healthy | **NodePort 30300** |
| **Fluent Bit** | Collect container stdout/stderr | Same agent pattern as EKS → CloudWatch | DaemonSet |

**Grafana password:** `aws ssm get-parameter --name /k8AWS/grafana-admin-password --with-decryption --region us-east-1 --query Parameter.Value --output text`

**Files:** `manifests/observability/prometheus-grafana.yaml`, `alertmanager.yaml`, `fluent-bit.yaml`

---

### Layer 9 — Backup (Velero)

- **Definition:** Kubernetes backup/restore to object storage.
- **Real use case:** Accidentally delete app namespace — restore from S3 without rebuilding cluster.
- **Problem solved:** Verify check #35 confirms Completed backup exists.
- **Schedule:** daily `0 3 * * *` UTC, TTL 720h, bucket `k8aws-velero-<ACCOUNT_ID>`.
- **Files:** `manifests/backup/velero-config.yaml`, Velero install in `deploy.ps1`

---

### Layer 10 — Automation scripts

| Script | Real use case | When |
|---|---|---|
| `preflight.ps1` | Catch missing tools/creds before spending 25 min | Before deploy |
| `deploy.ps1` | One pipeline: Terraform → bootstrap wait → K8s → Velero | Create lab |
| `verify.ps1` | 35 gates — infra, pods, HTTP, backup | After deploy |
| `destroy.ps1` | Stop credit burn; verify no EC2 left | End of lab |
| `logs.ps1` | Debug bootstrap without guessing | When stuck |
| `ssm-exec.ps1` | Ad-hoc remote kubectl | Manual ops |

---

### Layer 11 — CI

GitHub Actions (`.github/workflows/ci.yaml`): `terraform fmt -check`, `terraform validate`, `yamllint manifests/`. Catches broken configs before anyone runs deploy. Does **not** deploy to AWS.

---

## Full manual build procedure (Phases A–K)

Total time: **25–35 minutes**. Same outcome as `deploy.ps1`.

### Phase A — Prepare local machine (5 min)

```powershell
cd c:\dev\k8AWS
aws login
aws sts get-caller-identity
.\scripts\preflight.ps1
```

### Phase B — Create AWS infrastructure (5 min)

```powershell
cd terraform
copy terraform.tfvars.example terraform.tfvars
# Edit: allowed_ingress_cidr = "YOUR_PUBLIC_IP/32"
terraform init
terraform plan -out=tfplan
terraform apply tfplan
cd ..
$ID     = terraform -chdir=terraform output -raw instance_id
$IP     = terraform -chdir=terraform output -raw public_ip
$BUCKET = terraform -chdir=terraform output -raw velero_bucket_name
```

**Created:** VPC, subnet, IGW, EC2, SG, IAM, SSM params, S3 bucket.

### Phase C — Wait for Kubernetes bootstrap (10–15 min)

```powershell
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$ID" --region us-east-1
.\scripts\helpers\ssm-exec.ps1 -InstanceId $ID -Command "test -f /var/lib/k8s-ready && echo READY"
.\scripts\logs.ps1   # if stuck
```

**Created on node:** containerd, kubeadm, Calico, local-path storage.

### Phase D — Sync manifests to S3 (1 min)

```powershell
aws s3 sync manifests "s3://$BUCKET/manifests/" --delete --region us-east-1
```

### Phase E — Install platform add-ons via SSM (5 min)

```bash
# Run on instance (deploy.ps1 automates all of this):
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.1/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/baremetal/deploy.yaml
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/v0.9.20/deploy/crds/bundle.yaml
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/v0.9.20/deploy/manifests/external-secrets.yaml
```

### Phase F — Secrets and namespaces (3 min)

Apply via S3: `namespace/`, `policy/guardrails.yaml`, `secrets/external-secrets.yaml`, ESO creds secret. Wait for `mongo-credentials` and `grafana-admin-credentials` secrets.

### Phase G — Observability + NetworkPolicies (3 min)

Apply: `prometheus-grafana.yaml`, `alertmanager.yaml`, `fluent-bit.yaml`, `cert-manager-issuer.yaml`, **`networkpolicy.yaml` before apps**.

### Phase H — Workloads (5 min)

```bash
# Order matters: mongo → api → webapp → ingress
kubectl apply -f database/mongo-statefulset.yaml
kubectl wait --for=condition=Ready pod -l app=mongo -n app --timeout=300s
kubectl apply -f microservices/api-deployment.yaml
kubectl apply -f microservices/webapp-deployment.yaml
kubectl apply -f networking/ingress-rules.yaml
```

### Phase I — Velero (2 min, optional)

```bash
velero install --provider aws --bucket $BUCKET ...
velero backup create app-manual-backup --include-namespaces app --wait
```

### Phase J — Verify from laptop

```powershell
.\scripts\verify.ps1
start "http://$IP:30080/webapp"
```

### Phase K — Destroy

```powershell
.\scripts\destroy.ps1
```

---

## Critical run checklist

Verify these **before and during deploy** for a smooth run:

| # | Check | How | Why it matters |
|---|---|---|---|
| 1 | AWS credentials valid | `aws sts get-caller-identity` | All scripts fail without this |
| 2 | m7i-flex.large free-tier eligible | `preflight.ps1` | Wrong instance type = charges |
| 3 | Region is us-east-1 | `terraform/variables.tf` default | Hard guardrail in Terraform |
| 4 | `allowed_ingress_cidr` = YOUR_IP/32 | auto-set by deploy.ps1 | HTTP checks fail if IP wrong |
| 5 | `enable_velero_bucket = true` | terraform.tfvars | Required for manifest S3 delivery |
| 6 | SSM Online before K8s steps | deploy.ps1 waits 20 min | Cannot run kubectl until Online |
| 7 | `/var/lib/k8s-ready` exists | deploy.ps1 waits 30 min | Bootstrap must finish first |
| 8 | ExternalSecrets synced | deploy.ps1 waits 4 min | mongo/Grafana fail without secrets |
| 9 | mongo Ready before api | deploy.ps1 enforces order | api returns 503 if mongo down |
| 10 | NetworkPolicies before apps | deploy.ps1 order | Prevents restart surprises |
| 11 | Same IP for verify HTTP checks | run verify from same network | SG blocks other IPs |
| 12 | Run destroy.ps1 when done | manual | Stops $0.096/hr charges |

**Honest expectation:** ~90–95% success on a fresh 2026 account with credits. Not 100% — upstream URLs and apt packages can change. No live E2E has been run until you execute deploy.

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

See [Complete technology stack](#complete-technology-stack) above for full definitions, real use cases, and manual steps.

---

## Quick local execution (3 commands)

Everything runs from your **local Windows machine** — no bastion, no SSH. Terraform creates AWS resources; PowerShell drives the rest over **SSM Run Command**.

```powershell
cd c:\dev\k8AWS
aws login
.\scripts\preflight.ps1          # validate tools + AWS creds
.\scripts\deploy.ps1             # Terraform + kubeadm + K8s apps (~25 min)
.\scripts\verify.ps1             # 35 checks → verify.log
```

When finished:

```powershell
.\scripts\destroy.ps1            # tear down ALL AWS resources
```

Non-interactive mode (no prompts):

```powershell
$env:K8AWS_AUTO_APPROVE = "true"
.\scripts\deploy.ps1
$env:K8AWS_AUTO_APPROVE = "true"
.\scripts\destroy.ps1
```

**What “local” means here:** your laptop orchestrates AWS API calls (Terraform, SSM, S3 sync). The Kubernetes control plane and workloads run on the EC2 instance in AWS — there is no local kind/minikube cluster. This mirrors how real teams operate: IaC from CI/laptop, workloads in cloud.

---

## Engineering architecture

High-level view of how your laptop, AWS, and Kubernetes connect.

```mermaid
flowchart TB
    subgraph LOCAL["Your Windows machine"]
        PS["PowerShell scripts"]
        TF["Terraform CLI"]
        AWSCLI["AWS CLI"]
    end

    subgraph AWS["AWS us-east-1"]
        subgraph NET["VPC 10.0.0.0/16"]
            IGW["Internet Gateway"]
            EC2["EC2 m7i-flex.large<br/>kubeadm single-node"]
        end
        SSM["SSM Parameter Store<br/>passwords + IAM keys"]
        S3["S3 bucket<br/>manifests + Velero backups"]
        IAM["IAM roles + users<br/>ESO / Velero / EC2"]
    end

    subgraph K8S["Kubernetes on EC2"]
        CP["Control plane<br/>kube-apiserver / etcd"]
        CNI["Calico CNI"]
        ING["nginx-ingress<br/>NodePort 30080"]
        APP["webapp + api + mongo"]
        OBS["Prometheus / Grafana / Fluent Bit"]
        ESO["External Secrets Operator"]
        VEL["Velero"]
    end

    PS --> TF
    PS --> AWSCLI
    TF --> NET
    TF --> SSM
    TF --> S3
    TF --> IAM
    AWSCLI -->|"SSM Run Command"| EC2
    AWSCLI -->|"s3 sync manifests"| S3
    EC2 --> K8S
    S3 -->|"EC2 IAM read"| EC2
    SSM -->|"ESO sync"| ESO
    S3 --> VEL
    IGW <-->|"HTTPS egress"| EC2
    LOCAL -->|"HTTP :30080 / :30300<br/>your IP/32 only"| IGW
```

---

## AWS network topology

Why **no NAT Gateway**: NAT costs ~$32+/month and is unnecessary — the node sits in a **public subnet** with a public IP. Inbound user traffic is restricted by security group to **your IP/32**; outbound (apt, container pulls, SSM) uses the IGW directly.

```mermaid
flowchart LR
    subgraph Internet
        YOU["Your browser<br/>YOUR_IP/32"]
    end

    subgraph VPC["VPC 10.0.0.0/16"]
        IGW["Internet Gateway"]
        subgraph PUB["Public subnet 10.0.1.0/24"]
            EC2["EC2 node<br/>Public + Private IP"]
        end
    end

    YOU -->|"TCP 30080, 30300"| IGW
    IGW --> EC2
    EC2 -->|"all egress"| IGW
    IGW --> Internet

    style NAT fill:#f9f,stroke:#333,stroke-dasharray: 5 5
    NAT["NAT Gateway<br/>NOT CREATED"]
```

| Security group rule | Port | Source | Why |
|---|---|---|---|
| NodePort HTTP | 30080 | `allowed_ingress_cidr` | nginx-ingress for webapp/api |
| Grafana NodePort | 30300 | `allowed_ingress_cidr` | Grafana UI |
| HTTP | 80 | `allowed_ingress_cidr` | hostNetwork ingress fallback |
| Kubelet | 10250 | VPC CIDR | internal node health |
| K8s API | 6443 | VPC CIDR | in-VPC API access |
| SSH | 22 | — | **blocked by design** |
| Egress | all | 0.0.0.0/0 | SSM, apt, image pulls, PyPI |

Access to the node shell uses **SSM Session Manager** (outbound HTTPS to AWS endpoints) — no inbound SSH required.

---

## End-to-end deploy flowchart

What `deploy.ps1` does, in order, and why each phase exists.

```mermaid
flowchart TD
    A([Start deploy.ps1]) --> B[preflight.ps1]
    B --> C{terraform.tfvars<br/>exists?}
    C -->|No| D[Auto-detect public IP<br/>write YOUR_IP/32]
    C -->|Yes| E[terraform init + apply]
    D --> E
    E --> F[Wait SSM Online]
    F --> G[Wait /var/lib/k8s-ready<br/>kubeadm + Calico done]
    G --> H[Sync manifests/ → S3]
    H --> I[Install metrics-server]
    I --> J[Install cert-manager]
    J --> K[Install nginx-ingress<br/>patch NodePort 30080]
    K --> L[Install External Secrets Operator]
    L --> M[Apply ESO AWS creds secret]
    M --> N[Apply namespaces + guardrails]
    N --> O[Apply ExternalSecrets<br/>wait K8s secrets synced]
    O --> P[Prometheus + Grafana + Alertmanager]
    P --> Q[Apply NetworkPolicies<br/>before workloads]
    Q --> R[Deploy mongo StatefulSet<br/>wait Ready]
    R --> S[Deploy api + webapp<br/>wait Ready]
    S --> T[Apply Ingress rules]
    T --> U{Velero install}
    U -->|Success| V[First backup to S3]
    U -->|Fail| W[Non-fatal warning]
    V --> X([Print URLs + done])
    W --> X
```

**Why S3 for manifests?** SSM Run Command has a **4096-character limit** per command. Base64-encoding YAML exceeds that. The EC2 instance pulls manifests from S3 using its instance profile — same pattern as production GitOps artifact delivery.

**Why mongo before api?** The API initContainer installs `pymongo` and probes MongoDB on startup. Starting mongo first avoids crash-loop races.

**Why NetworkPolicies before apps?** Policies are applied while pods are still coming up so restarts behave correctly under default-deny rules (api→mongo ingress, api→PyPI egress on 443).

---

## HTTP request path (runtime)

How a browser request reaches your microservices.

```mermaid
sequenceDiagram
    participant B as Browser
    participant SG as Security Group
    participant NP as NodePort 30080
    participant IC as nginx-ingress controller
    participant ING as Ingress resource
    participant WEB as webapp Service
    participant API as api Service
    participant MDB as mongo StatefulSet

    B->>SG: GET /webapp (YOUR_IP/32)
    SG->>NP: allow if CIDR matches
    NP->>IC: forward to controller pod
    IC->>ING: match path /webapp
    ING->>WEB: rewrite → nginx:80
    WEB-->>B: HTML response

    B->>NP: GET /api
    NP->>IC: forward
    IC->>ING: match path /api Prefix
    ING->>API: api:8080
    API->>MDB: pymongo ping :27017
    MDB-->>API: pong
    API-->>B: mongo_ok=True
```

Grafana bypasses Ingress and is exposed directly on **NodePort 30300** (defined in `prometheus-grafana.yaml`) for simpler lab access.

---

## Secrets lifecycle

Why secrets never live in Git.

```mermaid
flowchart LR
    TF["Terraform<br/>random_password"] --> SSM["SSM Parameter Store<br/>SecureString"]
    SSM --> ESO["External Secrets Operator<br/>ClusterSecretStore aws-ssm"]
    ESO --> KS["Kubernetes Secrets<br/>mongo-credentials<br/>grafana-admin-credentials"]
    KS --> POD["App pods<br/>env / volumeMount"]

    IAM["IAM user k8AWS-eso-reader<br/>ssm:GetParameter only"] --> ESO
```

| Step | Component | Why |
|---|---|---|
| Generate | `random_password` in Terraform | Cryptographically random; not in Git |
| Store | SSM Parameter Store | Encrypted at rest; audit trail; rotation-friendly |
| Sync | External Secrets Operator | Kubernetes-native; pods consume standard Secrets |
| Consume | Deployments / StatefulSets | `secretKeyRef` — same pattern as EKS + Secrets Manager |

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
├── terraform/              # AWS infrastructure (VPC, EC2, IAM, SSM, S3)
│   ├── vpc.tf
│   ├── ec2.tf
│   ├── secrets.tf
│   ├── ssm-parameters.tf
│   ├── velero-s3.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── terraform.tfvars.example
│   └── user-data/
│       └── kubeadm-init.sh # cloud-init bootstrap script
├── manifests/
│   ├── namespace/          # app, observability, ingress-nginx, external-secrets
│   ├── policy/             # PDB, ResourceQuota, LimitRange
│   ├── secrets/            # ExternalSecrets + ClusterSecretStore
│   ├── security/           # cert-manager ClusterIssuer
│   ├── networking/         # NetworkPolicy, Ingress, NodePort patch
│   ├── database/           # mongo StatefulSet + PVC
│   ├── microservices/      # webapp (nginx) + api (Python/pymongo)
│   ├── observability/      # Prometheus, Grafana, Alertmanager, Fluent Bit
│   └── backup/             # Velero schedule + BackupStorageLocation
├── scripts/
│   ├── preflight.ps1       # Pre-deploy validation
│   ├── deploy.ps1          # Full deploy pipeline
│   ├── verify.ps1          # 35 post-deploy checks
│   ├── destroy.ps1         # Tear down everything
│   ├── logs.ps1            # Remote bootstrap logs
│   └── helpers/
│       └── ssm-exec.ps1    # SSM Run Command wrapper
├── .github/workflows/
│   └── ci.yaml             # terraform validate + yamllint
├── .gitignore
├── LICENSE
└── README.md               # All documentation (this file)
```

---

## SRE production structure review

Expert assessment of this repository layout against production SRE standards.

### What is correct (production-aligned)

| Area | Verdict | Notes |
|---|---|---|
| **Separation of concerns** | ✅ Good | `terraform/` (infra), `manifests/` (K8s), `scripts/` (orchestration) — clean boundaries |
| **No secrets in Git** | ✅ Good | `.gitignore` blocks tfvars/state; passwords in SSM only |
| **IaC for all AWS resources** | ✅ Good | Nothing requires manual console steps |
| **Destroy path exists** | ✅ Good | `destroy.ps1` + S3 `force_destroy` + Terraform default tags |
| **Remote access model** | ✅ Good | SSM-only — no SSH keys, no port 22 |
| **Network zero-trust** | ✅ Good | Calico NetworkPolicy default-deny + SG IP lockdown |
| **Resource governance** | ✅ Good | ResourceQuota, LimitRange, PDB, PSA baseline |
| **Observability triad** | ✅ Good | Metrics (Prometheus) + logs (Fluent Bit) + dashboards (Grafana) |
| **Backup strategy** | ✅ Good | Velero to S3 with lifecycle expiration |
| **Verification gate** | ✅ Good | 35-check `verify.ps1` before declaring success |
| **CI validation** | ✅ Good | Terraform fmt/validate + yamllint on every push |
| **Cost guardrails** | ✅ Good | No NAT, no ALB, instance type/region locked in Terraform |
| **Manifest delivery** | ✅ Good | S3 sync avoids SSM payload limits — production pattern |

### Known gaps (acceptable for free-tier lab, fix for real production)

| Gap | Severity | Recommendation |
|---|---|---|
| Single-node cluster | High for prod | Add worker node + remove control-plane taint |
| Local Terraform state | Medium | Add S3 backend + DynamoDB lock for team use |
| Static IAM keys for ESO/Velero | Medium | Use IRSA (EKS) or instance profile with scoped policies |
| `--kubelet-insecure-tls` | Medium | Install proper kubelet serving certs (kubeadm certs pattern) |
| No GitOps controller | Low | Add ArgoCD/Flux — currently script-driven apply |
| api pip install at runtime | Low | Build custom container image with pymongo pre-baked |
| `metrics-server.yaml` / `storage-class.yaml` | Low | Placeholder/reference only — not applied directly (documented) |
| No live E2E in CI | Medium | Add OIDC-based deploy smoke test on dedicated AWS account |
| Self-signed TLS only | Low | Add Route53 + Let's Encrypt ClusterIssuer when domain available |
| 8 GiB RAM ceiling | High at scale | Full observability stack + apps may OOM under load testing |

### Overall SRE score

| Lens | Score | Summary |
|---|---|---|
| Free-tier lab / learning | **9/10** | Complete, automated, destroyable |
| Small-org single-node patterns | **8.5/10** | Real production patterns at minimal scale |
| Multi-node HA production | **4/10** | By design — one instance |
| Enterprise compliance | **6/10** | Good foundations; static keys and single node limit audit score |

**Verdict:** Folder structure and component choices are **correct and production-pattern-aligned** for a single-node AWS lab. The layout would scale to a multi-node/EKS migration by moving `manifests/` into GitOps and replacing kubeadm bootstrap with managed node groups — without restructuring the repo.

---

## CI

On push/PR: `terraform validate` and yamllint on manifests. Does not deploy to AWS (no credentials in CI by default).

---

## Start now (immediate steps)

```powershell
cd c:\dev\k8AWS
aws login
.\scripts\preflight.ps1
.\scripts\deploy.ps1
.\scripts\verify.ps1
# Browser: http://<PUBLIC_IP>:30080/webapp
.\scripts\destroy.ps1   # when finished
```
