@echo off
echo === PrivBatch Agent Deployment ===

set REGION=us-east-1
set ACCOUNT_ID=630058354226
set ECR_REPO=%ACCOUNT_ID%.dkr.ecr.%REGION%.amazonaws.com/privbatch-agent

echo.
echo [1/4] Logging into ECR...
aws ecr get-login-password --region %REGION% | docker login --username AWS --password-stdin %ECR_REPO%

echo.
echo [2/4] Building Docker image...
cd agent
docker build -t privbatch-agent .

echo.
echo [3/4] Tagging image...
docker tag privbatch-agent:latest %ECR_REPO%:latest

echo.
echo [4/4] Pushing to ECR...
docker push %ECR_REPO%:latest

cd ..
echo.
echo === Done! Image pushed to ECR ===
echo.
echo Next: Create App Runner service at https://console.aws.amazon.com/apprunner
pause
