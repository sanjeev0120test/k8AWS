#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/kubeadm-init.log) 2>&1

AWS_REGION="${aws_region}"
PROJECT_NAME="${project_name}"
READY_MARKER="/var/lib/k8s-ready"
K8S_VERSION="1.29.15-1.1"
KUBE_PKG_VERSION="1.29.*"

log() { echo "[$(date -Is)] $*"; }

log "=== k8AWS kubeadm bootstrap starting ==="

# --- Phase 1: OS prerequisites ---
log "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

log "Loading kernel modules..."
cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

log "Configuring sysctl..."
cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# --- Phase 2: containerd (single CRI — no Docker, no CRI-O) ---
log "Installing containerd..."
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg awscli jq

apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# --- Phase 3: Kubernetes 1.29 packages ---
log "Installing kubeadm, kubelet, kubectl $${K8S_VERSION}..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y "kubelet=$${KUBE_PKG_VERSION}" "kubeadm=$${KUBE_PKG_VERSION}" "kubectl=$${KUBE_PKG_VERSION}" || \
  apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

# --- Phase 4: kubeadm init ---
PRIVATE_IP=$(curl -sf http://169.254.169.254/latest/meta-data/local-ipv4)
log "Initializing kubeadm on $${PRIVATE_IP}..."

kubeadm config images pull
kubeadm init \
  --apiserver-advertise-address="$${PRIVATE_IP}" \
  --pod-network-cidr=192.168.0.0/16 \
  --cri-socket=unix:///var/run/containerd/containerd.sock

export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# Single-node: allow scheduling on control-plane
log "Removing control-plane taint for single-node cluster..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || \
  kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true

# --- Phase 5: Calico CNI ---
log "Installing Calico v3.26..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

log "Waiting for node to become Ready..."
for i in $(seq 1 60); do
  if kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; then
    log "Node is Ready"
    break
  fi
  sleep 10
done

# --- Phase 6: local-path storage provisioner ---
log "Installing local-path-provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true

# --- Phase 7: Wait for core system pods ---
log "Waiting for kube-system pods..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s 2>/dev/null || true

# --- Phase 8: Ready marker ---
echo "K8S_READY=true" >"$${READY_MARKER}"
log "=== k8AWS kubeadm bootstrap complete ==="
