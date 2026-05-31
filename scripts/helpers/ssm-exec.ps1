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

function Sync-AwsCredentials {
    Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
    $creds = aws configure export-credentials --format process 2>$null | ConvertFrom-Json
    if (-not $creds.AccessKeyId) { throw "AWS credentials missing or expired - run: aws login" }
    $env:AWS_ACCESS_KEY_ID = $creds.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $creds.SecretAccessKey
    if ($creds.SessionToken) { $env:AWS_SESSION_TOKEN = $creds.SessionToken } else { Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue }
}

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

Sync-AwsCredentials

$wrapped = "echo $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmdLine))) | base64 -d | bash"
$sendResult = aws ssm send-command `
    --instance-ids $InstanceId `
    --document-name "AWS-RunShellScript" `
    --parameters "commands=$wrapped" `
    --region $Region `
    --output json | ConvertFrom-Json

$commandId = $sendResult.Command.CommandId
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

do {
    Start-Sleep -Seconds 3
    Sync-AwsCredentials
    $invocationJson = aws ssm get-command-invocation `
        --command-id $commandId `
        --instance-id $InstanceId `
        --region $Region `
        --output json 2>&1 | Out-String
    $invocation = $invocationJson | ConvertFrom-Json

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
