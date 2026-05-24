#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $RootDir "terraform"
$ManifestsDir = Join-Path $RootDir "manifests"
$SsmExec = Join-Path $RootDir "scripts\helpers\ssm-exec.ps1"
$Region = "us-east-1"
$ProjectName = "k8AWS"

$MetricsServerUrl = "https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.1/components.yaml"
$NginxIngressUrl = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/baremetal/deploy.yaml"
$EsoCrdsUrl = "https://raw.githubusercontent.com/external-secrets/external-secrets/v0.9.20/deploy/crds/bundle.yaml"
$EsoManifestUrl = "https://raw.githubusercontent.com/external-secrets/external-secrets/v0.9.20/deploy/manifests/external-secrets.yaml"
$CertManagerUrl = "https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml"
$VeleroVersion = "v1.14.0"
$VeleroPluginVersion = "v1.10.0"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

function Get-TfOutput($name) {
    Push-Location $TerraformDir
    try { return terraform output -raw $name } finally { Pop-Location }
}

function Invoke-Ssm($instanceId, [string]$cmd, [int]$timeout = 180) {
    & $SsmExec -InstanceId $instanceId -Region $Region -Command $cmd -TimeoutSeconds $timeout
}

function Ensure-TerraformVars {
    $tfvars = Join-Path $TerraformDir "terraform.tfvars"
    if (Test-Path $tfvars) { return }
    Write-Step "Creating terraform.tfvars from your public IP"
    $ip = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 15).Trim()
    @"
aws_region           = "$Region"
allowed_ingress_cidr = "$ip/32"
allow_public_ingress = false
enable_velero_bucket = true
"@ | Set-Content -Path $tfvars -Encoding UTF8
    Write-Host "Created $tfvars with allowed_ingress_cidr=$ip/32"
}

function Wait-SsmOnline($instanceId, [int]$maxMinutes = 20) {
    Write-Step "Waiting for SSM agent online..."
    $deadline = (Get-Date).AddMinutes($maxMinutes)
    do {
        $status = aws ssm describe-instance-information `
            --filters "Key=InstanceIds,Values=$instanceId" --region $Region `
            --query "InstanceInformationList[0].PingStatus" --output text 2>$null
        if ($status -eq "Online") { Write-Host "SSM Online"; return }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)
    throw "SSM not online within ${maxMinutes}m"
}

function Wait-K8sReady($instanceId, [int]$maxMinutes = 30) {
    Write-Step "Waiting for kubeadm bootstrap..."
    $deadline = (Get-Date).AddMinutes($maxMinutes)
    do {
        try {
            $r = Invoke-Ssm $instanceId "test -f /var/lib/k8s-ready && echo READY || echo WAIT" 90
            if ($r.StandardOutputContent -match "READY") { return }
        } catch {}
        Start-Sleep -Seconds 30
    } while ((Get-Date) -lt $deadline)
    throw "Bootstrap timeout — run .\scripts\logs.ps1"
}

function Sync-ManifestsToS3($bucket) {
    Write-Step "Uploading manifests to s3://$bucket/manifests/"
    aws s3 sync $ManifestsDir "s3://$bucket/manifests/" --delete --region $Region
}

function Apply-ManifestsOnInstance($instanceId, $bucket, [string[]]$relativePaths) {
    foreach ($rel in $relativePaths) {
        $remote = "/opt/k8aws/manifests/$($rel -replace '\\','/')"
        Write-Host "Applying $rel"
        Invoke-Ssm $instanceId "mkdir -p /opt/k8aws && aws s3 cp s3://$bucket/manifests/$($rel -replace '\\','/') $remote --region $Region && kubectl apply -f $remote" 300
    }
}

function New-EsoSecretManifest($keyId, $secretKey) {
    $b64Key = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($keyId))
    $b64Secret = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secretKey))
    return @"
apiVersion: v1
kind: Secret
metadata:
  name: eso-aws-credentials
  namespace: external-secrets
type: Opaque
data:
  access-key-id: $b64Key
  secret-access-key: $b64Secret
"@
}

Write-Step "k8AWS Production Deploy"
& (Join-Path $RootDir "scripts\preflight.ps1")
if ($LASTEXITCODE -ne 0) { throw "Preflight failed" }

Ensure-TerraformVars

Write-Step "Terraform apply"
Push-Location $TerraformDir
try {
    terraform init -input=false
    terraform plan -out=tfplan -input=false
    if ($env:K8AWS_AUTO_APPROVE -ne "true") {
        if ((Read-Host "Apply plan? (yes/no)") -ne "yes") { throw "Cancelled" }
    }
    terraform apply -input=false tfplan
} finally { Pop-Location }

$instanceId = Get-TfOutput "instance_id"
$publicIp = Get-TfOutput "public_ip"
$veleroBucket = Get-TfOutput "velero_bucket_name"
Write-Host "Instance: $instanceId | IP: $publicIp | Bucket: $veleroBucket"

Wait-SsmOnline $instanceId
Wait-K8sReady $instanceId

if ($veleroBucket) { Sync-ManifestsToS3 $veleroBucket }

Write-Step "Platform: metrics-server"
Invoke-Ssm $instanceId "kubectl apply -f $MetricsServerUrl" 300
Invoke-Ssm $instanceId "kubectl patch deployment metrics-server -n kube-system --type=json -p='[{ `"op`": `"add`", `"path`": `"/spec/template/spec/containers/0/args/-`", `"value`": `"--kubelet-insecure-tls`" }]'" 120
Invoke-Ssm $instanceId "kubectl rollout status deployment/metrics-server -n kube-system --timeout=240s" 240

Write-Step "Platform: cert-manager"
Invoke-Ssm $instanceId "kubectl apply -f $CertManagerUrl" 300
Invoke-Ssm $instanceId "kubectl rollout status deployment/cert-manager -n cert-manager --timeout=240s" 240
Invoke-Ssm $instanceId "kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=240s" 240
Invoke-Ssm $instanceId "kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=240s" 240

Write-Step "Platform: nginx-ingress"
Invoke-Ssm $instanceId "kubectl apply -f $NginxIngressUrl" 300
Start-Sleep -Seconds 25
if ($veleroBucket) {
    Apply-ManifestsOnInstance $instanceId $veleroBucket @("networking\nginx-ingress-nodeport.yaml")
} else {
    throw "Velero bucket required for manifest delivery — enable_velero_bucket must be true"
}
Invoke-Ssm $instanceId "kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=240s" 240

Write-Step "Platform: External Secrets Operator"
Invoke-Ssm $instanceId "kubectl apply -f $EsoCrdsUrl" 300
Invoke-Ssm $instanceId "kubectl apply -f $EsoManifestUrl" 300
Invoke-Ssm $instanceId "kubectl rollout status deployment/external-secrets -n external-secrets --timeout=240s" 240

Write-Step "ESO credentials secret (safe base64 YAML)"
$esoKeyId = aws ssm get-parameter --name "/$ProjectName/eso-access-key-id" --with-decryption --region $Region --query "Parameter.Value" --output text
$esoSecret = aws ssm get-parameter --name "/$ProjectName/eso-secret-access-key" --with-decryption --region $Region --query "Parameter.Value" --output text
$esoYaml = New-EsoSecretManifest $esoKeyId $esoSecret
$esoTemp = Join-Path $env:TEMP "eso-secret.yaml"
$esoYaml | Set-Content -Path $esoTemp -Encoding UTF8
aws s3 cp $esoTemp "s3://$veleroBucket/manifests/bootstrap/eso-secret.yaml" --region $Region
Invoke-Ssm $instanceId "aws s3 cp s3://$veleroBucket/manifests/bootstrap/eso-secret.yaml /tmp/eso-secret.yaml --region $Region && kubectl apply -f /tmp/eso-secret.yaml" 120

$manifestSequence = @(
    "namespace\platform-namespaces.yaml",
    "namespace\app-namespace.yaml",
    "policy\guardrails.yaml",
    "observability\alertmanager.yaml",
    "observability\fluent-bit.yaml",
    "secrets\external-secrets.yaml"
)
Apply-ManifestsOnInstance $instanceId $veleroBucket $manifestSequence

Write-Step "Waiting for ExternalSecrets sync"
Invoke-Ssm $instanceId 'for i in $(seq 1 40); do kubectl get secret mongo-credentials -n app >/dev/null 2>&1 && kubectl get secret grafana-admin-credentials -n observability >/dev/null 2>&1 && exit 0; sleep 6; done; kubectl describe externalsecret -A; exit 1' 300

Apply-ManifestsOnInstance $instanceId $veleroBucket @(
    "observability\prometheus-grafana.yaml",
    "security\cert-manager-issuer.yaml"
)

Write-Step "Network policies (before workloads — avoids restart surprises)"
Apply-ManifestsOnInstance $instanceId $veleroBucket @("networking\networkpolicy.yaml")

Write-Step "Database first (mongo before api)"
Apply-ManifestsOnInstance $instanceId $veleroBucket @("database\mongo-statefulset.yaml")
Invoke-Ssm $instanceId "kubectl rollout status statefulset/mongo -n app --timeout=420s" 420
Invoke-Ssm $instanceId "kubectl wait --for=condition=Ready pod -l app=mongo -n app --timeout=300s" 300

Write-Step "Applications"
Apply-ManifestsOnInstance $instanceId $veleroBucket @(
    "microservices\api-deployment.yaml",
    "microservices\webapp-deployment.yaml"
)
Invoke-Ssm $instanceId "kubectl rollout status deployment/api -n app --timeout=420s" 420
Invoke-Ssm $instanceId "kubectl rollout status deployment/webapp -n app --timeout=300s" 300

Write-Step "Ingress rules"
Apply-ManifestsOnInstance $instanceId $veleroBucket @("networking\ingress-rules.yaml")

Write-Step "Velero backup (optional — continues on failure)"
try {
    $veleroKey = aws ssm get-parameter --name "/$ProjectName/velero-access-key-id" --with-decryption --region $Region --query "Parameter.Value" --output text
    $veleroSecretKey = aws ssm get-parameter --name "/$ProjectName/velero-secret-access-key" --with-decryption --region $Region --query "Parameter.Value" --output text
    $cred = "[default]`naws_access_key_id=$veleroKey`naws_secret_access_key=$veleroSecretKey"
    $credTemp = Join-Path $env:TEMP "velero-credentials"
    $cred | Set-Content -Path $credTemp -Encoding ASCII -NoNewline
    aws s3 cp $credTemp "s3://$veleroBucket/manifests/bootstrap/velero-credentials" --region $Region
    Invoke-Ssm $instanceId "curl -fsSL https://github.com/vmware-tanzu/velero/releases/download/$VeleroVersion/velero-${VeleroVersion}-linux-amd64.tar.gz | tar -xz && install velero-${VeleroVersion}-linux-amd64/velero /usr/local/bin/velero" 300
    Invoke-Ssm $instanceId "aws s3 cp s3://$veleroBucket/manifests/bootstrap/velero-credentials /tmp/velero-creds --region $Region && chmod 600 /tmp/velero-creds" 60
    Invoke-Ssm $instanceId "velero install --provider aws --plugins velero/velero-plugin-for-aws:${VeleroPluginVersion} --bucket $veleroBucket --secret-file /tmp/velero-creds --backup-location-config region=$Region --wait" 600
    $veleroCfg = (Get-Content (Join-Path $ManifestsDir "backup\velero-config.yaml") -Raw).Replace("PLACEHOLDER_BUCKET", $veleroBucket)
    $veleroCfgTemp = Join-Path $env:TEMP "velero-config.yaml"
    $veleroCfg | Set-Content $veleroCfgTemp -Encoding UTF8
    aws s3 cp $veleroCfgTemp "s3://$veleroBucket/manifests/bootstrap/velero-config.yaml" --region $Region
    Invoke-Ssm $instanceId "aws s3 cp s3://$veleroBucket/manifests/bootstrap/velero-config.yaml /tmp/velero-config.yaml --region $Region && kubectl apply -f /tmp/velero-config.yaml" 120
    Invoke-Ssm $instanceId "velero backup create app-manual-backup --include-namespaces app --wait" 300
} catch {
    Write-Host "Velero setup skipped or failed (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Step "Final readiness wait"
Invoke-Ssm $instanceId "kubectl get pods -A" 120

Write-Host @"

DEPLOY COMPLETE
  Webapp:  http://${publicIp}:30080/webapp
  API:     http://${publicIp}:30080/api
  Grafana: http://${publicIp}:30300

Grafana password:
  aws ssm get-parameter --name /$ProjectName/grafana-admin-password --with-decryption --region $Region --query Parameter.Value --output text

Next: .\scripts\verify.ps1
Destroy when done: .\scripts\destroy.ps1
"@ -ForegroundColor Green
