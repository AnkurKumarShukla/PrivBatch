# PrivBatch AWS Deployment Script (PowerShell)
# Run this from Windows PowerShell in the project root

$REGION = "us-east-1"
$ACCOUNT_ID = "630058354226"
$ECR_REPO = "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/privbatch-agent"

Write-Host "=== PrivBatch AWS Deployment ===" -ForegroundColor Cyan

# Step 1: Login to ECR
Write-Host "`n[1/4] Logging into ECR..." -ForegroundColor Yellow
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# Step 2: Build Docker image
Write-Host "`n[2/4] Building Docker image..." -ForegroundColor Yellow
Set-Location agent
docker build -t privbatch-agent .

# Step 3: Tag and push to ECR
Write-Host "`n[3/4] Pushing to ECR..." -ForegroundColor Yellow
docker tag privbatch-agent:latest ${ECR_REPO}:latest
docker push ${ECR_REPO}:latest

Write-Host "`n[4/4] Creating App Runner service..." -ForegroundColor Yellow
Set-Location ..

# Note: You need to set these environment variables in App Runner
Write-Host @"

=== NEXT STEPS ===

Image pushed to: $ECR_REPO:latest

Now create App Runner service in AWS Console:
1. Go to: https://console.aws.amazon.com/apprunner
2. Click 'Create service'
3. Source: Container registry > Amazon ECR
4. Image URI: $ECR_REPO:latest
5. Port: 8000
6. Add environment variables:
   - RPC_URL
   - PRIVATE_KEY
   - HOOK_ADDRESS=0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00
   - EXECUTOR_ADDRESS=0x79dcDc67710C70be8Ef52e67C8295Fd0dA8A5722
   - COMMIT_ADDRESS=0x5f4E461b847fCB857639D1Ec7277485286b7613F
   - TOKEN_A=0x486C739A8A219026B6AB13aFf557c827Db4E267e
   - TOKEN_B=0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E
7. Create service

"@ -ForegroundColor Green
