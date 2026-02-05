#!/bin/bash
# ===== Deploy PrivBatch contracts to Sepolia =====
set -e

# Load .env
if [ ! -f .env ]; then
    echo "ERROR: .env file not found!"
    echo ""
    echo "Do this first:"
    echo "  1. cp .env.example .env"
    echo "  2. Edit .env with your RPC_URL and PRIVATE_KEY"
    exit 1
fi

source .env

# Validate
if [ -z "$RPC_URL" ] || [ "$RPC_URL" = "https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_API_KEY" ]; then
    echo "ERROR: Set your RPC_URL in .env"
    echo "Get one free at https://www.alchemy.com"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" = "your_64_char_hex_private_key_here" ]; then
    echo "ERROR: Set your PRIVATE_KEY in .env"
    echo "Export from MetaMask: Settings > Accounts > Export Private Key"
    exit 1
fi

echo "============================================"
echo "  Deploying PrivBatch to Sepolia"
echo "============================================"
echo ""
echo "RPC: $RPC_URL"
echo "PoolManager: $POOL_MANAGER"
echo "PositionManager: $POSITION_MANAGER"
echo ""

# Build first
echo "[1/2] Building contracts..."
forge build
echo ""

# Deploy
echo "[2/2] Deploying to Sepolia..."
echo ""
forge script script/DeployAll.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --verify \
    -vvv

echo ""
echo "============================================"
echo "  DONE! Now update your .env file with"
echo "  the addresses printed above."
echo "============================================"
echo ""
echo "After updating .env, you can run the agent:"
echo "  cd agent && python3 -m src.main"
echo ""
