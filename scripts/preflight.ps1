#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $RootDir "terraform"
$Region = "us-east-1"

Write-Host "`nk8AWS Preflight Checks`n" -ForegroundColor Cyan
$ok = $true

function Test-Check($name, $passed, $detail) {
    if ($passed) {
        Write-Host "[PASS] $name - $detail" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $name - $detail" -ForegroundColor Red
        $script:ok = $false
    }
}

foreach ($tool in @("aws", "terraform")) {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    Test-Check "Tool: $tool" ($null -ne $found) $(if ($found) { $found.Source } else { "not in PATH" })
}

try {
    $id = aws sts get-caller-identity --region $Region --output json 2>$null | ConvertFrom-Json
    Test-Check "AWS credentials" ($null -ne $id.Account) "Account $($id.Account)"
} catch {
    Test-Check "AWS credentials" $false "Run: aws login"
}

try {
    $ft = aws ec2 describe-instance-types --region $Region `
        --filters "Name=free-tier-eligible,Values=true" "Name=instance-type,Values=m7i-flex.large" `
        --query "InstanceTypes[0].InstanceType" --output text 2>$null
    Test-Check "m7i-flex.large free-tier eligible" ($ft -eq "m7i-flex.large") "region=$Region"
} catch {
    Test-Check "m7i-flex.large free-tier eligible" $false "Could not query EC2 API"
}

if (Test-Path (Join-Path $TerraformDir "terraform.tfvars")) {
    Test-Check "terraform.tfvars exists" $true "custom config found"
} else {
    Test-Check "terraform.tfvars" $true "will be auto-created from your public IP on deploy"
}

Push-Location $TerraformDir
try {
    if (Test-Path ".terraform") {
        terraform validate 2>$null | Out-Null
        Test-Check "terraform validate" ($LASTEXITCODE -eq 0) "configuration valid"
    } else {
        Test-Check "terraform init" $true "will run during deploy"
    }
} finally {
    Pop-Location
}

if (-not $ok) {
    Write-Host "`nPreflight FAILED - fix issues above before deploy.ps1`n" -ForegroundColor Red
    exit 1
}

Write-Host "`nPreflight PASSED - run .\scripts\deploy.ps1`n" -ForegroundColor Green
