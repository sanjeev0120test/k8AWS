#Requires -Version 5.1
# Post-destroy cost audit - run after terraform destroy to prove account is clear.
$ErrorActionPreference = "Continue"
$Region = "us-east-1"
$Project = "k8AWS"
$fail = 0
$pass = 0

function Sync-AwsCredentials {
    Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
    $creds = aws configure export-credentials --format process 2>$null | ConvertFrom-Json
    if (-not $creds.AccessKeyId) { throw "AWS credentials missing or expired - run: aws login" }
    $env:AWS_ACCESS_KEY_ID = $creds.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $creds.SecretAccessKey
    if ($creds.SessionToken) { $env:AWS_SESSION_TOKEN = $creds.SessionToken }
}

function Test-Clear($label, $value) {
    $empty = [string]::IsNullOrWhiteSpace($value) -or $value -eq "None" -or $value -eq "[]"
    if ($empty) {
        Write-Host "[PASS] $label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[FAIL] $label => $value" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " k8AWS POST-DESTROY COST AUDIT (5 passes)"
Write-Host "========================================`n"

Sync-AwsCredentials
$id = aws sts get-caller-identity --output json | ConvertFrom-Json
Write-Host "Account: $($id.Account)  Arn: $($id.Arn)`n"

for ($passNum = 1; $passNum -le 5; $passNum++) {
    Write-Host "--- PASS $passNum/5 ---" -ForegroundColor Yellow
    Sync-AwsCredentials
    $fail = 0
    $pass = 0

    # PASS 1: Compute
    $running = aws ec2 describe-instances --region $Region `
        --filters "Name=instance-state-name,Values=running,pending,stopping" `
        --query "Reservations[*].Instances[*].InstanceId" --output text 2>$null
    Test-Clear "No running/pending EC2 (us-east-1)" $running

    $k8ec2 = aws ec2 describe-instances --region $Region `
        --filters "Name=tag:Project,Values=$Project" "Name=instance-state-name,Values=running,pending,stopped,stopping" `
        --query "Reservations[*].Instances[*].InstanceId" --output text 2>$null
    Test-Clear "No active k8AWS EC2" $k8ec2

    # PASS 2: Network cost traps
    $nat = aws ec2 describe-nat-gateways --region $Region `
        --filter "Name=state,Values=available,pending" `
        --query "NatGateways[*].NatGatewayId" --output text 2>$null
    Test-Clear "No NAT Gateways" $nat

    $eip = aws ec2 describe-addresses --region $Region `
        --query "Addresses[?AssociationId==null].AllocationId" --output text 2>$null
    Test-Clear "No unattached Elastic IPs" $eip

    $vpc = aws ec2 describe-vpcs --region $Region `
        --filters "Name=tag:Project,Values=$Project" `
        --query "Vpcs[*].VpcId" --output text 2>$null
    Test-Clear "No k8AWS VPC" $vpc

    # PASS 3: Storage
    $s3 = aws s3api list-buckets --query "Buckets[?contains(Name, 'k8aws')].Name" --output text 2>$null
    Test-Clear "No k8aws S3 buckets" $s3

    $ebs = aws ec2 describe-volumes --region $Region `
        --filters "Name=status,Values=available" `
        --query "Volumes[*].VolumeId" --output text 2>$null
    Test-Clear "No orphan EBS volumes" $ebs

    $snap = aws ec2 describe-snapshots --owner-ids self --region $Region `
        --query "Snapshots[?StartTime>='2026-05-01'].SnapshotId" --output text 2>$null
    Test-Clear "No recent EBS snapshots (since May 2026)" $snap

    # PASS 4: k8AWS config/secrets
    $ssm = aws ssm describe-parameters --region $Region `
        --parameter-filters "Key=Name,Option=BeginsWith,Values=/$Project/" `
        --query "Parameters[*].Name" --output text 2>$null
    Test-Clear "No SSM params /k8AWS/*" $ssm

    $kms = aws kms list-aliases --region $Region `
        --query "Aliases[?AliasName=='alias/$Project-ssm'].AliasName" --output text 2>$null
    Test-Clear "No KMS alias/$Project-ssm" $kms

    $roleOut = aws iam get-role --role-name "$Project-ec2-ssm-role" 2>&1 | Out-String
    if ($roleOut -match "NoSuchEntity") {
        Write-Host "[PASS] IAM role $Project-ec2-ssm-role removed" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "[FAIL] IAM role $Project-ec2-ssm-role still exists" -ForegroundColor Red
        $fail++
    }

    # PASS 5: Other billable services + global EC2
    $alb = aws elbv2 describe-load-balancers --region $Region `
        --query "LoadBalancers[*].LoadBalancerArn" --output text 2>$null
    Test-Clear "No ALB/NLB" $alb

    $rds = aws rds describe-db-instances --region $Region `
        --query "DBInstances[*].DBInstanceIdentifier" --output text 2>$null
    Test-Clear "No RDS instances" $rds

    $eks = aws eks list-clusters --region $Region --query "clusters" --output text 2>$null
    Test-Clear "No EKS clusters" $eks

    $allRunning = 0
    $regions = aws ec2 describe-regions --query "Regions[*].RegionName" --output text
    foreach ($r in $regions.Split()) {
        $cnt = aws ec2 describe-instances --region $r `
            --filters "Name=instance-state-name,Values=running,pending" `
            --query "length(Reservations[*].Instances[*])" --output text 2>$null
        if ($cnt -and [int]$cnt -gt 0) { $allRunning += [int]$cnt }
    }
    if ($allRunning -eq 0) {
        Write-Host "[PASS] No running EC2 in ANY region ($($regions.Split().Count) regions scanned)" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "[FAIL] Running EC2 in other regions: $allRunning instance(s)" -ForegroundColor Red
        $fail++
    }

    Write-Host "Pass $passNum result: $pass passed, $fail failed`n"
    if ($fail -gt 0) {
        Write-Host "AUDIT FAILED on pass $passNum - billable or k8AWS resources may remain." -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Seconds 2
}

Write-Host "========================================" -ForegroundColor Green
Write-Host " ALL 5 PASSES CLEAR - no k8AWS billable resources detected"
Write-Host " Compute meter STOPPED. Account safe from this lab."
Write-Host "========================================`n"
