#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $RootDir "terraform"
$SsmExec = Join-Path $RootDir "scripts\helpers\ssm-exec.ps1"
$Region = "us-east-1"

function Get-TfOutput($name) {
    Push-Location $TerraformDir
    try { return terraform output -raw $name 2>$null } finally { Pop-Location }
}

$instanceId = Get-TfOutput "instance_id"
if (-not $instanceId) {
    throw "No instance_id in terraform output. Has deploy been run?"
}

Write-Host "Fetching logs from instance $instanceId via SSM`n" -ForegroundColor Cyan

Write-Host "=== cloud-init / kubeadm init log (last 80 lines) ===" -ForegroundColor Yellow
& $SsmExec -InstanceId $instanceId -Region $Region -Command "tail -80 /var/log/kubeadm-init.log 2>/dev/null || tail -80 /var/log/cloud-init-output.log" -TimeoutSeconds 60

Write-Host "`n=== kubelet status ===" -ForegroundColor Yellow
& $SsmExec -InstanceId $instanceId -Region $Region -Command "systemctl status kubelet --no-pager -l | tail -20" -TimeoutSeconds 60

Write-Host "`n=== containerd status ===" -ForegroundColor Yellow
& $SsmExec -InstanceId $instanceId -Region $Region -Command "systemctl status containerd --no-pager -l | tail -10" -TimeoutSeconds 60

Write-Host "`n=== kubectl get pods -A ===" -ForegroundColor Yellow
& $SsmExec -InstanceId $instanceId -Region $Region -Command "kubectl get pods -A" -TimeoutSeconds 60

Write-Host "`n=== recent cluster events ===" -ForegroundColor Yellow
& $SsmExec -InstanceId $instanceId -Region $Region -Command "kubectl get events -A --sort-by=.lastTimestamp | tail -20" -TimeoutSeconds 60
