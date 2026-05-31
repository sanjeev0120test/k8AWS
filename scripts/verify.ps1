#Requires -Version 5.1
$ErrorActionPreference = "Continue"

$RootDir = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $RootDir "terraform"
$SsmExec = Join-Path $RootDir (Join-Path "scripts" (Join-Path "helpers" "ssm-exec.ps1"))
$LogFile = Join-Path $RootDir "verify.log"
$Region = "us-east-1"
$ProjectName = "k8AWS"
$passed = 0
$failed = 0

function Get-TfOutput($name) {
    Push-Location $TerraformDir
    try { return terraform output -raw $name 2>$null } finally { Pop-Location }
}

function Write-Check($num, $desc, $ok, $detail = "") {
    if ($ok) { $script:passed++ } else { $script:failed++ }
    $status = if ($ok) { "PASS" } else { "FAIL" }
    $color = if ($ok) { "Green" } else { "Red" }
    $line = "[CHECK $num] $status - $desc"
    if ($detail) { $line += " | $detail" }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value "$(Get-Date -Format o) $line"
}

function Invoke-SsmQuiet($instanceId, [string]$cmd) {
    if ($cmd -match 'kubectl|velero') {
        $cmd = "export KUBECONFIG=/etc/kubernetes/admin.conf; $cmd"
    }
    try {
        $r = & $SsmExec -InstanceId $instanceId -Region $Region -Command $cmd -TimeoutSeconds 120
        return @{ Ok = $true; Out = $r.StandardOutputContent }
    } catch {
        return @{ Ok = $false; Out = $_.Exception.Message }
    }
}

"" | Set-Content $LogFile
Write-Host "`nk8AWS Verification - 35 checks (production grade)`n" -ForegroundColor Cyan

try {
    $id = aws sts get-caller-identity --region $Region --output json | ConvertFrom-Json
    Write-Check 1 "AWS caller identity" ($null -ne $id.Account) "Account $($id.Account)"
} catch { Write-Check 1 "AWS caller identity" $false $_.Exception.Message }

$instanceId = Get-TfOutput "instance_id"
$publicIp = Get-TfOutput "public_ip"
$veleroBucket = Get-TfOutput "velero_bucket_name"

if ($instanceId) {
    $inst = aws ec2 describe-instances --instance-ids $instanceId --region $Region --output json | ConvertFrom-Json
    $state = $inst.Reservations[0].Instances[0].State.Name
    $itype = $inst.Reservations[0].Instances[0].InstanceType
    Write-Check 2 "EC2 running m7i-flex.large" ($state -eq "running" -and $itype -eq "m7i-flex.large") "state=$state"
} else { Write-Check 2 "EC2 running m7i-flex.large" $false }

$vpcId = Get-TfOutput "vpc_id"
if ($vpcId) {
    $nat = aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpcId" "Name=state,Values=available,pending" --region $Region --query "NatGateways" --output json | ConvertFrom-Json
    Write-Check 3 "No NAT Gateway" ($nat.Count -eq 0)
} else { Write-Check 3 "No NAT Gateway" $false }

Write-Check 4 "Velero S3 bucket provisioned" ([bool]$veleroBucket) "bucket=$veleroBucket"

if ($instanceId) {
    $ssmStatus = aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instanceId" --region $Region --query "InstanceInformationList[0].PingStatus" --output text
    Write-Check 5 "SSM agent online" ($ssmStatus -eq "Online")
    $ready = Invoke-SsmQuiet $instanceId "test -f /var/lib/k8s-ready && echo READY"
    Write-Check 6 "K8S_READY marker" ($ready.Out -match "READY")
    $ctr = Invoke-SsmQuiet $instanceId "systemctl is-active containerd"
    Write-Check 7 "containerd active" ($ctr.Out -match "active")
    $nodes = Invoke-SsmQuiet $instanceId "kubectl get nodes --no-headers"
    Write-Check 8 "Node Ready" ($nodes.Out -match "Ready")
    $calico = Invoke-SsmQuiet $instanceId "kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers"
    Write-Check 9 "Calico Running" ($calico.Out -match "Running")
    $cm = Invoke-SsmQuiet $instanceId "kubectl get deployment cert-manager -n cert-manager --no-headers"
    Write-Check 10 "cert-manager Running" ($cm.Out -match "1/1")
    $ms = Invoke-SsmQuiet $instanceId "kubectl get deployment metrics-server -n kube-system --no-headers"
    Write-Check 11 "metrics-server Running" ($ms.Out -match "1/1")
    $ing = Invoke-SsmQuiet $instanceId "kubectl get deployment ingress-nginx-controller -n ingress-nginx --no-headers"
    Write-Check 12 "nginx-ingress Running" ($ing.Out -match "1/1")
    $eso = Invoke-SsmQuiet $instanceId "kubectl get deployment external-secrets -n default --no-headers"
    Write-Check 13 "External Secrets Running" ($eso.Out -match "1/1")
    $esMongo = Invoke-SsmQuiet $instanceId "kubectl get externalsecret mongo-credentials -n app --no-headers"
    $esGrafana = Invoke-SsmQuiet $instanceId "kubectl get externalsecret grafana-admin-credentials -n observability --no-headers"
    $esSynced = ($esMongo.Out -match "SecretSynced|Ready") -and ($esGrafana.Out -match "SecretSynced|Ready")
    Write-Check 14 "ExternalSecrets synced (mongo + grafana)" $esSynced "mongo=$($esMongo.Out.Trim()) grafana=$($esGrafana.Out.Trim())"
    $pvc = Invoke-SsmQuiet $instanceId "kubectl get pvc -n app --no-headers"
    Write-Check 15 "Mongo PVC Bound" ($pvc.Out -match "Bound")
    $mongo = Invoke-SsmQuiet $instanceId "kubectl get statefulset mongo -n app --no-headers"
    Write-Check 16 "mongo StatefulSet Ready" ($mongo.Out -match "1/1")
    $web = Invoke-SsmQuiet $instanceId "kubectl get deployment webapp -n app --no-headers"
    Write-Check 17 "webapp Ready" ($web.Out -match "1/1")
    $api = Invoke-SsmQuiet $instanceId "kubectl get deployment api -n app --no-headers"
    Write-Check 18 "api Ready" ($api.Out -match "1/1")
    $pdb = Invoke-SsmQuiet $instanceId "kubectl get pdb -n app --no-headers | wc -l"
    Write-Check 19 "PodDisruptionBudgets (3+)" ([int]$pdb.Out.Trim() -ge 3)
    $quota = Invoke-SsmQuiet $instanceId "kubectl get resourcequota -n app --no-headers"
    Write-Check 20 "ResourceQuota applied" ($quota.Out -match "app-quota")
    $am = Invoke-SsmQuiet $instanceId "kubectl get deployment alertmanager -n observability --no-headers"
    Write-Check 21 "Alertmanager Running" ($am.Out -match "1/1")
    $prom = Invoke-SsmQuiet $instanceId "kubectl get deployment prometheus -n observability --no-headers"
    Write-Check 22 "Prometheus Running" ($prom.Out -match "1/1")
    $graf = Invoke-SsmQuiet $instanceId "kubectl get deployment grafana -n observability --no-headers"
    Write-Check 23 "Grafana Running" ($graf.Out -match "1/1")
    $fb = Invoke-SsmQuiet $instanceId "kubectl get daemonset fluent-bit -n observability --no-headers"
    Write-Check 24 "Fluent Bit Running" ($fb.Out -match "1")
    $np = Invoke-SsmQuiet $instanceId "kubectl get networkpolicy -n app --no-headers | wc -l"
    Write-Check 25 "NetworkPolicies (6+)" ([int]$np.Out.Trim() -ge 6)
    $hpa = Invoke-SsmQuiet $instanceId "kubectl get hpa webapp -n app --no-headers"
    Write-Check 26 "HPA configured" ($hpa.Out -match "webapp")
    $top = Invoke-SsmQuiet $instanceId "kubectl top nodes"
    Write-Check 27 "kubectl top nodes" ($top.Out -match "cpu")
    $velero = Invoke-SsmQuiet $instanceId "velero version 2>/dev/null"
    $bsl = Invoke-SsmQuiet $instanceId "velero backup-location get 2>/dev/null | grep Available || true"
    $veleroOk = ($velero.Out -match "Version") -and ($bsl.Out -match "Available")
    Write-Check 28 "Velero installed with available backup location" $veleroOk "bsl=$($bsl.Out.Trim())"
} else {
    5..28 | ForEach-Object { Write-Check $_ "Skipped (no instance)" $false }
}

if ($publicIp) {
    try {
        $apiResp = Invoke-WebRequest -Uri "http://${publicIp}:30080/api" -UseBasicParsing -TimeoutSec 20
        Write-Check 29 "API HTTP 200" ($apiResp.StatusCode -eq 200) "status=$($apiResp.StatusCode)"
        Write-Check 30 "API reports mongo connected" ($apiResp.Content -match "mongo_ok=True")
    } catch {
        Write-Check 29 "API HTTP 200" $false $_.Exception.Message
        Write-Check 30 "API reports mongo connected" $false
    }
    try {
        $webResp = Invoke-WebRequest -Uri "http://${publicIp}:30080/webapp" -UseBasicParsing -TimeoutSec 20
        Write-Check 31 "Webapp HTTP 200" ($webResp.StatusCode -eq 200)
    } catch { Write-Check 31 "Webapp HTTP 200" $false }
    try {
        $grafResp = Invoke-WebRequest -Uri "http://${publicIp}:30300/login" -UseBasicParsing -TimeoutSec 20
        Write-Check 32 "Grafana login page" ($grafResp.StatusCode -eq 200)
    } catch { Write-Check 32 "Grafana login page" $false }
} else {
    29..32 | ForEach-Object { Write-Check $_ "HTTP check skipped" $false }
}

if ($instanceId) {
    $issuer = Invoke-SsmQuiet $instanceId "kubectl get clusterissuer selfsigned-issuer --no-headers"
    Write-Check 33 "ClusterIssuer selfsigned" ($issuer.Out -match "True")
    $psa = Invoke-SsmQuiet $instanceId "kubectl get ns app -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'"
    Write-Check 34 "Pod Security Admission (baseline)" ($psa.Out -match "baseline")
    if ($veleroBucket) {
        $vb = Invoke-SsmQuiet $instanceId "velero backup get 2>/dev/null | grep -c Completed || true"
        Write-Check 35 "Velero backup exists" ([int]$vb.Out.Trim() -ge 1) "completed=$($vb.Out.Trim())"
    } else { Write-Check 35 "Velero backup exists" $false "no bucket" }
} else {
    33..35 | ForEach-Object { Write-Check $_ "Skipped" $false }
}

Write-Host "`nResults: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
Write-Host "Log: $LogFile"
if ($failed -gt 0) { exit 1 }
