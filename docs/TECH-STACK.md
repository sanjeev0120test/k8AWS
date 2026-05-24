# k8AWS — Complete Technology Stack Reference

> **Note:** This file is a standalone copy. The full content is also in the [main README](../README.md#complete-technology-stack) — the README is the single source of truth.

This document explains **every technology** in the k8AWS project: official definitions, why it was chosen, the specific problem it solves here, which files implement it, and **exact steps** to create or configure it.

---

## Table of contents

1. [Stack inventory](#stack-inventory)
2. [Layer 1 — Local tooling](#layer-1--local-tooling)
3. [Layer 2 — AWS infrastructure (Terraform)](#layer-2--aws-infrastructure-terraform)
4. [Layer 3 — Node bootstrap (cloud-init)](#layer-3--node-bootstrap-cloud-init)
5. [Layer 4 — Kubernetes platform add-ons](#layer-4--kubernetes-platform-add-ons)
6. [Layer 5 — Secrets management](#layer-5--secrets-management)
7. [Layer 6 — Application workloads](#layer-6--application-workloads)
8. [Layer 7 — Networking and security](#layer-7--networking-and-security)
9. [Layer 8 — Observability](#layer-8--observability)
10. [Layer 9 — Backup and disaster recovery](#layer-9--backup-and-disaster-recovery)
11. [Layer 10 — Automation scripts](#layer-10--automation-scripts)
12. [Layer 11 — CI/CD](#layer-11--cicd)
13. [Full manual build procedure](#full-manual-build-procedure)
14. [Immediate steps to make it work](#immediate-steps-to-make-it-work)

---

## Stack inventory

| # | Technology | Version / pin | Official documentation |
|---|---|---|---|
| 1 | Terraform | ≥ 1.5 | [terraform.io/docs](https://developer.hashicorp.com/terraform/docs) |
| 2 | AWS Provider | ~> 5.0 | [registry.terraform.io/hashicorp/aws](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) |
| 3 | Amazon VPC | — | [docs.aws.amazon.com/vpc](https://docs.aws.amazon.com/vpc/latest/userguide/) |
| 4 | Amazon EC2 | m7i-flex.large | [docs.aws.amazon.com/ec2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/) |
| 5 | AWS SSM Session Manager | — | [docs.aws.amazon.com/systems-manager/session-manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) |
| 6 | AWS SSM Parameter Store | — | [docs.aws.amazon.com/systems-manager-parameter-store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) |
| 7 | Amazon S3 | — | [docs.aws.amazon.com/s3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/) |
| 8 | AWS IAM | — | [docs.aws.amazon.com/iam](https://docs.aws.amazon.com/IAM/latest/UserGuide/) |
| 9 | Ubuntu Server | 24.04 Noble | [ubuntu.com/server/docs](https://ubuntu.com/server/docs) |
| 10 | containerd | apt package | [containerd.io/docs](https://containerd.io/docs/) |
| 11 | kubeadm / kubelet / kubectl | Kubernetes 1.29 | [kubernetes.io/docs/setup/production-environment/tools/kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/) |
| 12 | Calico CNI | v3.26.0 | [docs.tigera.io/calico](https://docs.tigera.io/calico/latest/about/) |
| 13 | local-path-provisioner | v0.0.28 | [github.com/rancher/local-path-provisioner](https://github.com/rancher/local-path-provisioner) |
| 14 | metrics-server | v0.7.1 | [kubernetes-sigs.github.io/metrics-server](https://github.com/kubernetes-sigs/metrics-server) |
| 15 | cert-manager | v1.14.5 | [cert-manager.io/docs](https://cert-manager.io/docs/) |
| 16 | nginx-ingress | controller v1.11.1 | [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) |
| 17 | External Secrets Operator | v0.9.20 | [external-secrets.io](https://external-secrets.io/latest/) |
| 18 | Velero | v1.14.0 | [velero.io/docs](https://velero.io/docs/) |
| 19 | MongoDB | 7 (container) | [mongodb.com/docs](https://www.mongodb.com/docs/) |
| 20 | nginx (app) | 1.27.3-alpine | [nginx.org/en/docs](https://nginx.org/en/docs/) |
| 21 | Python / pymongo | 3.12 / 4.7.3 | [pymongo.readthedocs.io](https://pymongo.readthedocs.io/) |
| 22 | Prometheus | container image | [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) |
| 23 | Alertmanager | container image | [prometheus.io/docs/alerting](https://prometheus.io/docs/alerting/latest/alertmanager/) |
| 24 | Grafana | container image | [grafana.com/docs](https://grafana.com/docs/grafana/latest/) |
| 25 | Fluent Bit | DaemonSet | [docs.fluentbit.io](https://docs.fluentbit.io/manual/) |
| 26 | PowerShell | 5.1+ | [learn.microsoft.com/powershell](https://learn.microsoft.com/en-us/powershell/) |
| 27 | GitHub Actions | — | [docs.github.com/actions](https://docs.github.com/en/actions) |

---

## Layer 1 — Local tooling

### Terraform

**Official definition:** Terraform is an open-source Infrastructure as Code (IaC) tool that lets you define cloud resources in declarative configuration files and provision them via provider APIs.

**Why in k8AWS:** Every AWS resource (VPC, EC2, IAM, SSM, S3) is reproducible, version-controlled, and destroyable in one command. Manual console clicks cannot be reliably torn down or peer-reviewed.

**Problem it solves here:**
- Creates identical lab environments for every user
- Enforces cost guardrails (`m7i-flex.large` only, `us-east-1` only, no NAT)
- Stores generated passwords in SSM — never in Git

**Files:** `terraform/*.tf`, `terraform/user-data/kubeadm-init.sh`

**How to create:**
```powershell
cd c:\dev\k8AWS\terraform
terraform init      # download AWS + random providers
terraform plan      # preview changes
terraform apply     # create all AWS resources
```

---

### AWS CLI v2

**Official definition:** Unified command-line interface for Amazon Web Services — calls the same APIs as the AWS Management Console.

**Why in k8AWS:** Drives SSM Run Command (remote kubectl), S3 manifest sync, SSM parameter reads, and identity checks — all from your laptop without SSH.

**Problem it solves here:** Orchestrates the post-Terraform deployment phases without installing kubectl locally or opening port 22.

**Files:** Used by all scripts in `scripts/`

**How to use:**
```powershell
aws login
aws sts get-caller-identity
aws ssm send-command ...   # wrapped by scripts/helpers/ssm-exec.ps1
aws s3 sync manifests s3://bucket/manifests/
```

---

### PowerShell scripts

**Official definition:** PowerShell is a cross-platform task automation shell and scripting language built on .NET.

**Why in k8AWS:** Primary automation on Windows/Cursor — chains Terraform, AWS CLI, and SSM into one deploy pipeline.

**Problem it solves here:** Single entry point (`deploy.ps1`) replaces 30+ manual steps that would otherwise be error-prone.

**Files:** `scripts/preflight.ps1`, `deploy.ps1`, `verify.ps1`, `destroy.ps1`, `logs.ps1`, `helpers/ssm-exec.ps1`

---

## Layer 2 — AWS infrastructure (Terraform)

### Amazon VPC (Virtual Private Cloud)

**Official definition:** A logically isolated section of the AWS Cloud where you launch AWS resources in a virtual network you define.

**Why in k8AWS:** Provides a dedicated `10.0.0.0/16` network with routing control. Required for security groups and subnet isolation.

**Problem it solves here:** Separates the lab from default VPC clutter; makes destroy clean (delete entire VPC).

**Files:** `terraform/vpc.tf`

**Resources created:**
| Resource | CIDR / detail |
|---|---|
| VPC | `10.0.0.0/16` |
| Public subnet | `10.0.1.0/24` in `us-east-1a` |
| Internet Gateway | Attached to VPC |
| Route table | `0.0.0.0/0` → IGW |

**Step:** `terraform apply` (automatic)

---

### Amazon EC2 (Elastic Compute Cloud)

**Official definition:** Secure and resizable compute capacity in the cloud — virtual servers called instances.

**Why in k8AWS:** Hosts the entire Kubernetes cluster (control plane + workloads) on one **m7i-flex.large** (2 vCPU, 8 GiB RAM).

**Problem it solves here:** Free-tier eligible compute for a full production-pattern stack without EKS control-plane cost (~$73/mo).

**Files:** `terraform/ec2.tf`, `terraform/user-data/kubeadm-init.sh`

**Key configuration:**
| Setting | Value | Why |
|---|---|---|
| Instance type | m7i-flex.large | Free tier + enough RAM for observability stack |
| AMI | Ubuntu 24.04 | LTS; supported by kubeadm 1.29 packages |
| Root volume | 20 GiB gp3 encrypted | Container images + etcd + PVC data |
| IMDSv2 | Required | SSRF protection |
| Public IP | Yes | No NAT Gateway needed |
| SSH (port 22) | Not opened | SSM-only access |

**Step:** Created by `terraform apply`; bootstrap runs automatically via `user_data`.

---

### AWS Systems Manager (SSM) Session Manager

**Official definition:** A fully managed AWS Systems Manager capability that provides secure, auditable instance management without open inbound ports or bastion hosts.

**Why in k8AWS:** Sole remote access path to the node. Deploy script runs all `kubectl` commands via **SSM Run Command** (`AWS-RunShellScript`).

**Problem it solves here:**
- No SSH keys to manage or leak
- No port 22 attack surface
- Works from any network (outbound HTTPS only)

**Files:** `terraform/ec2.tf` (IAM role `AmazonSSMManagedInstanceCore`), `scripts/helpers/ssm-exec.ps1`

**How to connect manually:**
```powershell
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

---

### AWS SSM Parameter Store

**Official definition:** A high-volume, hierarchical storage for configuration data and secrets, which can be stored as plain text or encrypted (SecureString).

**Why in k8AWS:** Central secret vault for MongoDB password, Grafana password, and IAM access keys for ESO/Velero.

**Problem it solves here:** Secrets exist outside Git and outside Kubernetes etcd until ESO syncs them on demand.

**Files:** `terraform/secrets.tf`, `terraform/ssm-parameters.tf`, `terraform/velero-s3.tf`

**Parameters created:**
| Path | Content |
|---|---|
| `/k8AWS/mongo-username` | `admin` |
| `/k8AWS/mongo-password` | random 24-char |
| `/k8AWS/grafana-admin-username` | `admin` |
| `/k8AWS/grafana-admin-password` | random 20-char |
| `/k8AWS/eso-access-key-id` | ESO IAM user key |
| `/k8AWS/eso-secret-access-key` | ESO IAM user secret |
| `/k8AWS/velero-access-key-id` | Velero IAM user key |
| `/k8AWS/velero-secret-access-key` | Velero IAM user secret |
| `/k8AWS/velero-bucket` | S3 bucket name |

---

### Amazon S3

**Official definition:** Object storage service offering industry-leading scalability, data availability, security, and performance.

**Why in k8AWS (two roles):**
1. **Manifest delivery** — EC2 pulls Kubernetes YAML from S3 (bypasses SSM 4096-char limit)
2. **Velero backups** — durable off-cluster backup target

**Problem it solves here:**
- Reliable large-payload delivery to the node
- Disaster recovery for the `app` namespace
- 30-day lifecycle rule controls storage cost

**Files:** `terraform/velero-s3.tf`, `manifests/backup/velero-config.yaml`

**S3 bucket naming:** `k8aws-velero-<ACCOUNT_ID>`

---

### AWS IAM

**Official definition:** Identity and Access Management — enables you to manage access to AWS services and resources securely.

**Why in k8AWS:** Three distinct principals with least privilege:

| Principal | Permissions | Purpose |
|---|---|---|
| EC2 instance role | SSM core + SSM read `/k8AWS/*` + S3 read manifests | Node ops + manifest pull |
| IAM user `k8AWS-eso-reader` | `ssm:GetParameter` on `/k8AWS/*` | External Secrets Operator |
| IAM user `k8AWS-velero` | S3 read/write on Velero bucket | Velero backup/restore |

**Problem it solves here:** Each component gets only the permissions it needs — production IAM hygiene on a lab budget.

**Files:** `terraform/ec2.tf`, `terraform/ssm-parameters.tf`, `terraform/velero-s3.tf`

---

## Layer 3 — Node bootstrap (cloud-init)

Executed automatically on first boot via EC2 `user_data`. Log file: `/var/log/kubeadm-init.log`. Ready marker: `/var/lib/k8s-ready`.

### Step-by-step bootstrap sequence

| Step | Action | Official reference | Why |
|---|---|---|---|
| 1 | Disable swap | [kubeadm install docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) | kubelet refuses to run with swap enabled |
| 2 | Load `overlay`, `br_netfilter` | Kubernetes networking requirements | Required for pod networking |
| 3 | Set sysctl (`ip_forward=1`) | Same | Enables pod-to-pod routing |
| 4 | Install containerd | [containerd docs](https://containerd.io/docs/) | CRI — runs containers without Docker daemon |
| 5 | Enable SystemdCgroup | containerd config | Required for kubelet cgroup driver alignment |
| 6 | Install kubelet/kubeadm/kubectl 1.29 | [pkgs.k8s.io](https://pkgs.k8s.io/) | Pinned Kubernetes version |
| 7 | `kubeadm init` | [kubeadm init](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/) | Creates control plane + kubeconfig |
| 8 | Remove control-plane taint | Single-node pattern | Allows app pods on the only node |
| 9 | Install Calico | [Calico install](https://docs.tigera.io/calico/latest/getting-started/kubernetes/) | CNI — assigns pod IPs + enforces NetworkPolicy |
| 10 | Install local-path-provisioner | [GitHub](https://github.com/rancher/local-path-provisioner) | Dynamic PV provisioning on node disk |
| 11 | Write `/var/lib/k8s-ready` | k8AWS convention | Signals deploy.ps1 that bootstrap finished |

**File:** `terraform/user-data/kubeadm-init.sh`

**How to monitor:**
```powershell
.\scripts\logs.ps1
# or
.\scripts\helpers\ssm-exec.ps1 -Command "tail -50 /var/log/kubeadm-init.log"
```

---

### containerd (Container Runtime Interface)

**Official definition:** An industry-standard container runtime with an emphasis on simplicity, robustness, and portability. Implements the Kubernetes CRI.

**Why not Docker:** Docker CE is not the recommended CRI for production Kubernetes since the dockershim removal in Kubernetes 1.24. containerd is what EKS and GKE use under the hood.

**Problem it solves here:** Runs all pod containers (mongo, nginx, prometheus, etc.) with lower overhead than Docker-in-Docker.

---

### Calico (CNI)

**Official definition:** A networking and network security solution for containers, virtual machines, and native host-based workloads. Implements the Kubernetes Container Network Interface (CNI).

**Why not Flannel alone:** Flannel provides pod networking but **does not enforce NetworkPolicy**. Calico adds zero-trust pod firewall rules required for this lab's security model.

**Problem it solves here:** Enables `default-deny` NetworkPolicies in the `app` namespace — api can only reach mongo on port 27017.

**Pod CIDR:** `192.168.0.0/16` (set in kubeadm init)

---

## Layer 4 — Kubernetes platform add-ons

Installed by `deploy.ps1` via SSM after bootstrap completes.

### metrics-server

**Official definition:** Cluster-wide aggregator of resource usage data. Collects metrics from the Summary API exposed by kubelet on each node.

**Why in k8AWS:** Required for `kubectl top nodes/pods` and for the **HorizontalPodAutoscaler** on webapp.

**Problem it solves here:** Demonstrates autoscaling infrastructure; verify check #27 confirms metrics pipeline works.

**Lab-specific patch:** `--kubelet-insecure-tls` — kubeadm uses self-signed kubelet certificates; without this flag metrics-server cannot scrape.

**Install step (automated):**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.1/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

---

### cert-manager

**Official definition:** A Kubernetes add-on to automate the management and issuance of TLS certificates from various issuing sources.

**Why in k8AWS:** Demonstrates production TLS workflow. Uses a **self-signed ClusterIssuer** for the lab (no public domain required).

**Problem it solves here:** Shows how certificates would be automated in production (swap ClusterIssuer for Let's Encrypt + DNS-01 when you have a real domain).

**File:** `manifests/security/cert-manager-issuer.yaml`

**Install step (automated):**
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
# wait for cert-manager, webhook, cainjector deployments
kubectl apply -f manifests/security/cert-manager-issuer.yaml
```

---

### nginx-ingress controller

**Official definition:** An Ingress controller that uses NGINX as a reverse proxy and load balancer. Implements the Kubernetes Ingress resource.

**Why in k8AWS:** Single HTTP entry point on NodePort **30080** routes `/webapp` and `/api` to different services — avoids paying for an AWS Application Load Balancer (~$16+/mo).

**Problem it solves here:** Path-based L7 routing for microservices on a bare-metal/single-node cluster.

**Files:** `manifests/networking/nginx-ingress-nodeport.yaml`, `manifests/networking/ingress-rules.yaml`

**Install step (automated):**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/baremetal/deploy.yaml
kubectl apply -f manifests/networking/nginx-ingress-nodeport.yaml   # pins NodePort 30080
kubectl apply -f manifests/networking/ingress-rules.yaml
```

---

## Layer 5 — Secrets management

### Terraform random_password

**Official definition:** Terraform resource that generates a cryptographically secure random string.

**Why in k8AWS:** Generates MongoDB and Grafana passwords at infrastructure creation time.

**Problem it solves here:** Passwords never appear in Git, YAML, or shell history.

**File:** `terraform/secrets.tf`

---

### External Secrets Operator (ESO)

**Official definition:** Integrates external secret management systems like AWS Secrets Manager or Parameter Store into Kubernetes via a custom resource API.

**Why in k8AWS:** Syncs SSM parameters into native Kubernetes `Secret` objects that pods consume via `secretKeyRef`.

**Problem it solves here:**
- Pods use standard Kubernetes Secrets — no AWS SDK in application code
- Same pattern used on production EKS clusters
- Grafana and MongoDB passwords rotate-able in SSM without redeploying Terraform

**Files:** `manifests/secrets/external-secrets.yaml`, ESO creds applied via S3 in `deploy.ps1`

**Resources:**
| Kind | Name | Purpose |
|---|---|---|
| ClusterSecretStore | `aws-ssm` | Connects ESO to Parameter Store |
| ExternalSecret | `mongo-credentials` | Syncs mongo user/pass to `app` namespace |
| ExternalSecret | `grafana-admin-credentials` | Syncs Grafana creds to `observability` namespace |

**Install step (automated):**
```bash
kubectl apply -f external-secrets CRDs v0.9.20
kubectl apply -f external-secrets manifest v0.9.20
kubectl apply -f eso-aws-credentials secret   # IAM keys for ESO
kubectl apply -f manifests/secrets/external-secrets.yaml
# wait for SecretSynced condition
```

---

## Layer 6 — Application workloads

### webapp (nginx Deployment + HPA)

**Official definition (nginx):** High-performance HTTP server and reverse proxy.

**Why in k8AWS:** Stateless front-end microservice — serves static HTML and demonstrates ingress path routing + HPA.

**Problem it solves here:** Proves ingress → Service → Pod path works; HPA proves metrics-server integration.

**File:** `manifests/microservices/webapp-deployment.yaml`

**Resources:** Deployment, ConfigMap (HTML), Service (ClusterIP), HorizontalPodAutoscaler (1–3 replicas, CPU 60%)

---

### api (Python Deployment)

**Official definition:** Custom HTTP health service using Python's stdlib `HTTPServer` + `pymongo` driver.

**Why in k8AWS:** Proves service-to-service communication (api → mongo), secret injection, and initContainer pattern.

**Problem it solves here:** Verify check #30 confirms `mongo_ok=True` — end-to-end data path works.

**File:** `manifests/microservices/api-deployment.yaml`

**Flow:** initContainer installs pymongo → main container reads `MONGO_USER`/`MONGO_PASS` from Secret → pings mongo → returns HTTP 200/503

---

### mongo (StatefulSet + PVC)

**Official definition (StatefulSet):** A Kubernetes workload API object used to manage stateful applications. Provides stable network IDs and persistent storage.

**Official definition (MongoDB):** Document-oriented NoSQL database.

**Why StatefulSet not Deployment:** MongoDB requires stable network identity (`mongo-0`) and persistent volume that survives pod restarts.

**Problem it solves here:** Demonstrates stateful workload patterns — PVC binding via local-path-provisioner, headless Service for stable DNS.

**File:** `manifests/database/mongo-statefulset.yaml`

**Storage:** 2 Gi `local-path` PVC per pod

**Deploy order:** mongo **must** start before api (deploy.ps1 enforces this)

---

## Layer 7 — Networking and security

### Kubernetes NetworkPolicy

**Official definition:** An API object that controls traffic flow at the IP address or port level (OSI layer 3 or 4).

**Why in k8AWS:** Default-deny with explicit allow rules — production zero-trust networking on a lab cluster.

**Problem it solves here:**

| Policy | Solves |
|---|---|
| `default-deny-all` | Blocks all unexpected pod traffic |
| `allow-dns-egress` | Pods can resolve DNS via kube-system |
| `allow-ingress-to-webapp-api` | Only nginx namespace can reach frontends |
| `allow-clients-to-mongo` | Only webapp + api can connect to mongo:27017 |
| `allow-api-egress-mongo` | api can only egress to mongo |
| `allow-api-egress-https` | api initContainer can pip install from PyPI |

**File:** `manifests/networking/networkpolicy.yaml`

---

### Security Group (AWS)

**Official definition:** A virtual firewall that controls inbound and outbound traffic for EC2 instances.

**Why in k8AWS:** Restricts NodePort access to **your IP/32** only — even though the node has a public IP, the world cannot reach your apps.

**File:** `terraform/ec2.tf`

---

### Pod Security Admission (PSA)

**Official definition:** A Kubernetes admission controller that applies Pod Security Standards (privileged, baseline, restricted) at the namespace level.

**Why in k8AWS:** `app` namespace enforces **baseline** — blocks privileged containers and hostPath mounts.

**File:** `manifests/namespace/app-namespace.yaml`

---

### Guardrails (PDB, ResourceQuota, LimitRange)

| Resource | Official definition | k8AWS use case |
|---|---|---|
| PodDisruptionBudget | Limits concurrent voluntary disruptions | webapp, api, mongo each have minAvailable: 1 |
| ResourceQuota | Caps total resource consumption per namespace | Prevents app namespace exhausting 8 GiB node |
| LimitRange | Default/min/max per-container resources | Every container gets sensible CPU/memory bounds |

**File:** `manifests/policy/guardrails.yaml`

---

## Layer 8 — Observability

### Prometheus

**Official definition:** An open-source systems monitoring and alerting toolkit that collects and stores metrics as time series data.

**Why in k8AWS:** Scrapes pods annotated with `prometheus.io/scrape: "true"` — discovers webapp and api automatically.

**Problem it solves here:** Production-grade metrics collection; feeds Alertmanager rules and Grafana dashboards.

**File:** `manifests/observability/prometheus-grafana.yaml`

---

### Alertmanager

**Official definition:** Handles alerts sent by client applications such as Prometheus. Takes care of deduplicating, grouping, and routing them.

**Why in k8AWS:** Demonstrates the alert pipeline even in a lab (rules fire; notifications can be added later).

**File:** `manifests/observability/alertmanager.yaml`

---

### Grafana

**Official definition:** An open-source platform for monitoring and observability — visualizes Prometheus metrics.

**Why in k8AWS:** Human-readable cluster health dashboard. Password from SSM via ESO — anonymous auth disabled.

**Problem it solves here:** Verify check #32 confirms login page reachable on NodePort 30300.

**File:** `manifests/observability/prometheus-grafana.yaml`

---

### Fluent Bit

**Official definition:** A fast and lightweight log processor and forwarder — runs as a DaemonSet on every node.

**Why in k8AWS:** Collects container stdout/stderr logs — same pattern as EKS → CloudWatch or Datadog pipelines.

**File:** `manifests/observability/fluent-bit.yaml`

---

## Layer 9 — Backup and disaster recovery

### Velero

**Official definition:** An open-source tool to safely backup and restore, perform disaster recovery, and migrate Kubernetes cluster resources and persistent volumes.

**Why in k8AWS:** Backs up the entire `app` namespace (mongo PVC metadata + resources) to S3 daily at 03:00 UTC.

**Problem it solves here:** Verify check #35 confirms at least one Completed backup exists. Proves DR is possible without etcd snapshots.

**Files:** `manifests/backup/velero-config.yaml`, Velero install in `deploy.ps1`

**Schedule:** `0 3 * * *` — daily, 720h (30 day) TTL

---

## Layer 10 — Automation scripts

| Script | Purpose | When to run |
|---|---|---|
| `preflight.ps1` | Validates AWS creds, tools, free-tier eligibility | Before deploy |
| `deploy.ps1` | Full pipeline: Terraform → bootstrap wait → K8s apps | Create lab |
| `verify.ps1` | 35 automated checks (SSM + HTTP) | After deploy |
| `destroy.ps1` | `terraform destroy` + cleanup verification | End of lab |
| `logs.ps1` | Tail bootstrap + kubelet logs via SSM | Troubleshooting |
| `helpers/ssm-exec.ps1` | Wrapper for SSM Run Command | Manual debugging |

---

## Layer 11 — CI/CD

### GitHub Actions

**Official definition:** Automate, customize, and execute software development workflows directly in your repository.

**Why in k8AWS:** Validates Terraform syntax and YAML on every push — catches broken configs before anyone runs deploy.

**File:** `.github/workflows/ci.yaml`

**Checks:** `terraform fmt -check`, `terraform validate`, `yamllint manifests/`

**Note:** CI does not deploy to AWS (no credentials stored in GitHub by default).

---

## Full manual build procedure

Use this to understand every step `deploy.ps1` automates. Total time: ~25–35 minutes.

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
$ID  = terraform -chdir=terraform output -raw instance_id
$IP  = terraform -chdir=terraform output -raw public_ip
$BUCKET = terraform -chdir=terraform output -raw velero_bucket_name
```

**Created:** VPC, subnet, IGW, EC2, security group, IAM roles/users, SSM parameters, S3 bucket.

### Phase C — Wait for Kubernetes bootstrap (10–15 min)

```powershell
# Repeat until PingStatus = Online
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$ID" --region us-east-1

# Repeat until output contains READY
.\scripts\helpers\ssm-exec.ps1 -InstanceId $ID -Command "test -f /var/lib/k8s-ready && echo READY"
```

**Created on node:** containerd, kubeadm cluster, Calico, local-path-provisioner.

### Phase D — Sync manifests to S3 (1 min)

```powershell
aws s3 sync manifests "s3://$BUCKET/manifests/" --delete --region us-east-1
```

### Phase E — Install platform add-ons (5 min, via SSM)

Run on instance (or use `deploy.ps1` which does all of this):

```bash
# metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.1/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml

# nginx-ingress + NodePort patch
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/baremetal/deploy.yaml
# apply manifests/networking/nginx-ingress-nodeport.yaml from S3

# External Secrets Operator
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/v0.9.20/deploy/crds/bundle.yaml
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/v0.9.20/deploy/manifests/external-secrets.yaml
```

### Phase F — Secrets and namespaces (3 min)

```bash
# Apply from S3: namespaces, guardrails, external-secrets.yaml
# Apply ESO AWS credentials secret
# Wait for mongo-credentials and grafana-admin-credentials secrets
kubectl get externalsecret -A
kubectl get secret mongo-credentials -n app
```

### Phase G — Observability + policies (3 min)

```bash
# Apply: prometheus-grafana.yaml, alertmanager.yaml, fluent-bit.yaml
# Apply: cert-manager-issuer.yaml
# Apply: networkpolicy.yaml  (BEFORE apps)
```

### Phase H — Workloads (5 min)

```bash
# Apply mongo StatefulSet → wait Ready
# Apply api + webapp Deployments → wait Ready
# Apply ingress-rules.yaml
kubectl get pods -n app
curl http://localhost:30080/api   # from node
```

### Phase I — Velero backup (2 min, optional)

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

## Immediate steps to make it work

Copy-paste this block — the fastest path from zero to running cluster:

```powershell
cd c:\dev\k8AWS
aws login
.\scripts\preflight.ps1
.\scripts\deploy.ps1
.\scripts\verify.ps1
```

Open browser:
- Webapp: `http://<PUBLIC_IP>:30080/webapp`
- API: `http://<PUBLIC_IP>:30080/api`
- Grafana: `http://<PUBLIC_IP>:30300`

When done:
```powershell
.\scripts\destroy.ps1
```
