#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $RootDir "terraform"
$Region = "us-east-1"
$ProjectName = "k8AWS"

Write-Host "`nk8AWS — Destroy all resources`n" -ForegroundColor Yellow
Write-Host "This removes EC2, VPC, SSM parameters, and IAM resources."
Write-Host "Estimated savings: ~`$0.096/hr compute credits.`n"

if ($env:K8AWS_AUTO_APPROVE -ne "true") {
    $confirm = Read-Host "Type 'destroy' to confirm"
    if ($confirm -ne "destroy") {
        Write-Host "Destroy cancelled."
        exit 0
    }
}

Push-Location $TerraformDir
try {
    if (-not (Test-Path ".terraform")) {
        terraform init -input=false
    }
    terraform destroy -auto-approve -input=false
} finally {
    Pop-Location
}

Write-Host "`nVerifying cleanup..."
$remaining = aws ec2 describe-instances `
    --region $Region `
    --filters "Name=tag:Project,Values=$ProjectName" "Name=instance-state-name,Values=running,pending,stopping,stopped" `
    --query "Reservations[*].Instances[*].InstanceId" `
    --output text

if ($remaining) {
    Write-Host "WARNING: Instances still exist: $remaining" -ForegroundColor Red
    exit 1
}

Write-Host "Cleanup verified — no running EC2 instances tagged Project=$ProjectName" -ForegroundColor Green
Write-Host "Credits preserved. Safe to close lab.`n"
