#!/bin/bash
# ===== Deploy Test Tokens & Initialize Pool on Sepolia =====
set -e

# Load .env
if [ ! -f .env ]; then
    echo "ERROR: .env file not found!"
    echo "Run deploy-sepolia.sh first to deploy the core contracts."
    exit 1
fi

source .env

# Validate required addresses
if [ -z "$RPC_URL" ]; then
    echo "ERROR: RPC_URL not set in .env"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "ERROR: PRIVATE_KEY not set in .env"
    exit 1
fi

if [ -z "$HOOK_ADDRESS" ]; then
    echo "ERROR: HOOK_ADDRESS not set in .env (deploy core contracts first)"
    exit 1
fi

if [ -z "$EXECUTOR_ADDRESS" ]; then
    echo "ERROR: EXECUTOR_ADDRESS not set in .env (deploy core contracts first)"
    exit 1
fi

if [ -z "$POOL_MANAGER" ]; then
    echo "ERROR: POOL_MANAGER not set in .env"
    exit 1
fi

echo "============================================"
echo "  Deploying Test Tokens & Initializing Pool"
echo "============================================"
echo ""
echo "RPC:      $RPC_URL"
echo "Hook:     $HOOK_ADDRESS"
echo "Executor: $EXECUTOR_ADDRESS"
echo ""

# Build
echo "[1/2] Building contracts..."
forge build
echo ""

# Deploy tokens + initialize pool
echo "[2/2] Deploying tokens and initializing pool..."
echo ""
forge script script/DeployTokensAndPool.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvv

echo ""
echo "============================================"
echo "  DONE! Add TOKEN_A and TOKEN_B to .env"
echo "  (addresses printed above)"
echo "============================================"
echo ""
echo "Verify with:"
echo "  cast call \$TOKEN_A \"name()(string)\" --rpc-url \$RPC_URL"
echo "  cast call \$TOKEN_B \"name()(string)\" --rpc-url \$RPC_URL"
echo ""
