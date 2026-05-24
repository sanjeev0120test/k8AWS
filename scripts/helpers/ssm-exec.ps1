param(
    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$Command,
    [string]$InstanceId,
    [string]$Region = "us-east-1",
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TerraformDir = Join-Path $RootDir "terraform"

function Get-TerraformOutput {
    param([string]$Name)
    Push-Location $TerraformDir
    try {
        return (terraform output -raw $Name 2>$null)
    } finally {
        Pop-Location
    }
}

if (-not $InstanceId) {
    $InstanceId = Get-TerraformOutput "instance_id"
}

if (-not $Command -or $Command.Count -eq 0) {
    throw "Usage: ssm-exec.ps1 -Command 'kubectl get nodes'"
}

$cmdLine = if ($Command.Count -eq 1) { $Command[0] } else { $Command -join " " }
Write-Host "SSM exec on ${InstanceId}: $cmdLine"

$sendResult = aws ssm send-command `
    --instance-ids $InstanceId `
    --document-name "AWS-RunShellScript" `
    --parameters "commands=$cmdLine" `
    --region $Region `
    --output json | ConvertFrom-Json

$commandId = $sendResult.Command.CommandId
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

do {
    Start-Sleep -Seconds 3
    $invocation = aws ssm get-command-invocation `
        --command-id $commandId `
        --instance-id $InstanceId `
        --region $Region `
        --output json | ConvertFrom-Json

    if ($invocation.Status -in @("Success", "Failed", "Cancelled", "TimedOut")) {
        if ($invocation.StandardOutputContent) {
            Write-Host $invocation.StandardOutputContent
        }
        if ($invocation.StandardErrorContent) {
            Write-Host $invocation.StandardErrorContent -ForegroundColor DarkYellow
        }
        if ($invocation.Status -ne "Success") {
            throw "SSM command failed with status: $($invocation.Status)"
        }
        return $invocation
    }
} while ((Get-Date) -lt $deadline)

throw "SSM command timed out after ${TimeoutSeconds}s"
