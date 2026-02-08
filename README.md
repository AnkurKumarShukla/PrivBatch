# PrivBatch Coordinator

**Privacy-preserving batched LP position management for Uniswap v4 on Sepolia**

PrivBatch protects liquidity providers from MEV extraction by batching LP intents off-chain, building Merkle trees, and executing them atomically through a Uniswap v4 hook. Individual intent parameters (tick range, amount, timing) stay hidden from MEV bots until batch execution, when it's too late to front-run.
![alt text](<image (1).jpg>)
![alt text](<image (2).jpg>)
![alt text](<image (3).jpg>)

Ref : [MEV attack on Liquidity provider](https://eigenphi.substack.com/p/mev-myth-2-sandwiching-adding-liquidity)
---

## Table of Contents

- [Architecture](#architecture)
- [Deployed Contracts (Sepolia)](#deployed-contracts-sepolia)
- [Deployment Transactions](#deployment-transactions)
- [Test Tokens](#test-tokens)
- [Pool Configuration](#pool-configuration)
- [Example Batched Transactions](#example-batched-transactions)
- [Privacy Pipeline](#privacy-pipeline)
- [Project Structure](#project-structure)
- [Setup & Run](#setup--run)
- [Agent API Reference](#agent-api-reference)
- [Frontend Pages](#frontend-pages)
- [How It Works (Technical)](#how-it-works-technical)
- [Key Addresses](#key-addresses)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Frontend (Next.js)                        │
│  Dashboard | Submit Intent | Mint Tokens | Monitor | Privacy     │
│  wagmi + viem + RainbowKit → MetaMask (Sepolia)                 │
└─────────────────────────────┬────────────────────────────────────┘
                              │ EIP-712 signed intents (HTTP)
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Agent (Python / FastAPI)                      │
│  Collector → Optimizer → Merkle Tree Builder → Batch Submitter   │
│  Adaptive k-multiplier learns from IL + gas history              │
└─────────────────────────────┬────────────────────────────────────┘
                              │ Single batch transaction
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Smart Contracts (Sepolia)                      │
│  BatchExecutor → PositionManager → PoolManager + PrivBatchHook   │
│  CommitContract (commit-reveal anti-MEV demo)                    │
└──────────────────────────────────────────────────────────────────┘
```

---

## Deployed Contracts (Sepolia)

| Contract | Address | Etherscan |
|----------|---------|-----------|
| **PrivBatchHook** | `0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00` | [View](https://sepolia.etherscan.io/address/0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00) |
| **BatchExecutor** | `0x79dcDc67710C70be8Ef52e67C8295Fd0dA8A5722` | [View](https://sepolia.etherscan.io/address/0x79dcDc67710C70be8Ef52e67C8295Fd0dA8A5722) |
| **CommitContract** | `0x5f4E461b847fCB857639D1Ec7277485286b7613F` | [View](https://sepolia.etherscan.io/address/0x5f4E461b847fCB857639D1Ec7277485286b7613F) |
| **TestTokenA (TTA)** | `0x486C739A8A219026B6AB13aFf557c827Db4E267e` | [View](https://sepolia.etherscan.io/address/0x486C739A8A219026B6AB13aFf557c827Db4E267e) |
| **TestTokenB (TTB)** | `0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E` | [View](https://sepolia.etherscan.io/address/0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E) |

### Uniswap v4 Canonical Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| PoolManager | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| PositionManager | `0x429ba70129df741b2ca2a85bc3a2a3328e5c09b4` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| SwapRouter | `0xf13D190e9117920c703d79B5F33732e10049b115` |

---

## Deployment Transactions

### Core Contracts (DeployAll)

| Step | Transaction | Description |
|------|-------------|-------------|
| CommitContract Deploy | [`0x732c04fa...`](https://sepolia.etherscan.io/tx/0x732c04faa1fe1630a1209f38b8b61e0eea78b3d132643099ba3adfa5324a1301) | Commit-reveal scheme (5-block delay, 256-block expiry) |
| PrivBatchHook Deploy (CREATE2) | [`0x61cf8741...`](https://sepolia.etherscan.io/tx/0x61cf87416602e05469316fd085ca3d23569926412a352f94ec0c1f14f7f25823) | Uniswap v4 hook with BEFORE_ADD, AFTER_ADD, BEFORE_REMOVE permissions |
| BatchExecutor Deploy | [`0x731b2933...`](https://sepolia.etherscan.io/tx/0x731b29334dd250d0360b170d1ce95f21d98c057cdad2201cac73a81749a6b3ab) | Atomic batch executor via PositionManager + Permit2 |

### Token & Pool Setup (DeployTokensAndPool)

| Step | Transaction | Description |
|------|-------------|-------------|
| TestTokenA (TTA) Deploy | [`0xba988fd4...`](https://sepolia.etherscan.io/tx/0xba988fd4f81e42b8251cf683dbd73c8d2adaef4d7a8e7f941bc597ba4aa997b8) | MockERC20 with public mint (18 decimals) |
| TestTokenB (TTB) Deploy | [`0x1e55bbb9...`](https://sepolia.etherscan.io/tx/0x1e55bbb9b76b95170b5f78b81dd0ac9828534ec7e3b950fa66a7b0c9d1c000db) | MockERC20 with public mint (18 decimals) |
| Mint 10M TTA to Deployer | [`0x15f103b9...`](https://sepolia.etherscan.io/tx/0x15f103b9c8d4eb37ef781387056f51d3fc6ac43bcf6cf112004e26cbcb0e5d58) | Initial supply for executor funding |
| Mint 10M TTB to Deployer | [`0xa5cda1a2...`](https://sepolia.etherscan.io/tx/0xa5cda1a23d8f387e187451161c5cb492020dc2680c4cbbd6b69becf9108e4ad1) | Initial supply for executor funding |

**Deployer Address**: `0xd555576D8C8b40193743f701E810f6B5A259A15C`

---

## Test Tokens

| Token | Symbol | Decimals | Address | Mint |
|-------|--------|----------|---------|------|
| TestTokenA | TTA | 18 | `0x486C739A8A219026B6AB13aFf557c827Db4E267e` | Anyone can call `mint(to, amount)` |
| TestTokenB | TTB | 18 | `0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E` | Anyone can call `mint(to, amount)` |

These are MockERC20 tokens (solmate) with a public `mint()` function for testnet use. Use the frontend Mint Tokens page or call directly:

```bash
cast send 0x486C739A8A219026B6AB13aFf557c827Db4E267e \
  "mint(address,uint256)" <YOUR_ADDRESS> 1000000000000000000000 \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/<KEY> \
  --private-key <KEY>
```

---

## Pool Configuration

| Parameter | Value |
|-----------|-------|
| Currency0 | `0x486C739A8A219026B6AB13aFf557c827Db4E267e` (TTA) |
| Currency1 | `0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E` (TTB) |
| Fee | 3000 (0.3%) |
| Tick Spacing | 60 |
| Hook | `0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00` (PrivBatchHook) |
| Initial Price | 1:1 (sqrtPriceX96 = 79228162514264337593543950336) |

**Pool Key Hash**: Derived from `keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks))`

---

## Example Batched Transactions

| Batch # | Transaction Hash |
|---------|------------------|
| 1 | [`0xb14262d0...`](https://sepolia.etherscan.io/tx/0xb14262d03d83764757f08021502757834e08919418915212a033b3abfe08783) |
| 2 | [`0x2fbe7f40...`](https://sepolia.etherscan.io/tx/0x2fbe7f4001ed9dadc0eadacf925cb0957628e5f10c7587890ce061a739e2d711) |
| 3 | [`0xd7e78298...`](https://sepolia.etherscan.io/tx/0xd7e7829846f7011e0bbefa7d48f76fdbc0d6b4ca62e57a82fbc6b4af6b055322) |

---

## Privacy Pipeline

Each step shows what MEV bots can and cannot see:

| Step | What Happens | Visibility |
|------|-------------|------------|
| **1. Intent Creation** | User fills LP parameters in browser | Private (browser only) |
| **2. EIP-712 Signing** | MetaMask signs structured typed data | Private (signature proves consent) |
| **3. Agent Queue** | Signed intent sent to off-chain agent via HTTP | Private (no on-chain footprint) |
| **4. Merkle Batching** | Agent groups intents into a Merkle tree | Private (individual data hidden in tree) |
| **5. Batch Execution** | Single tx sends Merkle root + proofs to hook | Public (root + proofs, but individual positions obscured) |
| **6. Hook Verification** | Hook verifies each Merkle proof + EIP-712 signature | Public (verified, positions minted atomically) |

MEV bots see one batch transaction, not individual LP positions. By the time data is revealed on-chain, all positions are already minted atomically -- the front-running window is closed.

### Security Model: Agent API vs Mempool

**Q: Can't bots just monitor the agent API instead of the mempool?**

In the demo, the `/intents/pending` endpoint is public so judges can see the queue. However, this is fundamentally different from mempool monitoring:

| Attack Vector | Mempool | PrivBatch Agent API |
|---------------|---------|---------------------|
| What bots see | Pending transactions | Intent data (not txs) |
| Can bot front-run? | Yes (same block) | No (different blocks) |
| Timing control | User's tx is public | Agent controls batch timing |
| Execution | Individual txs | Atomic batch (all-or-nothing) |

**Why API visibility doesn't enable MEV:**

1. **Intents aren't transactions** - Bots can't insert them into a block
2. **Agent controls timing** - Bot doesn't know when batch will execute
3. **Atomic execution** - All positions mint in one tx, no sandwich window
4. **Different blocks** - By the time bot reacts, batch may already be mined

**Production hardening (not in demo):**
- Add API authentication (JWT/API keys)
- Remove `/intents/pending` endpoint
- Rate limiting and IP allowlisting
- Private agent deployment (VPN/internal network)

The demo API is intentionally open for hackathon demonstration purposes.

---

## Project Structure

```
uniswap/
├── src/                          # Solidity contracts
│   ├── PrivBatchHook.sol         # Uniswap v4 hook (Merkle proof + EIP-712 verification)
│   ├── BatchExecutor.sol         # Atomic batch execution via PositionManager
│   ├── CommitContract.sol        # Commit-reveal anti-MEV scheme
│   ├── types/
│   │   └── LPIntent.sol          # Intent struct definition
│   └── libraries/
│       ├── IntentVerifier.sol    # EIP-712 signature verification
│       └── BatchMerkle.sol       # Merkle tree proof verification
│
├── script/                       # Foundry deployment scripts
│   ├── DeployAll.s.sol           # Deploy Hook + Executor + CommitContract
│   └── DeployTokensAndPool.s.sol # Deploy test tokens + initialize pool
│
├── test/                         # Solidity tests
│
├── agent/                        # Python off-chain agent
│   └── src/
│       ├── main.py               # Orchestrator (collect → optimize → batch → execute)
│       ├── collector.py          # FastAPI server + intent validation
│       ├── signer.py             # EIP-712 sign/verify
│       ├── merkle.py             # Merkle tree builder
│       ├── optimizer.py          # Tick range optimization (Black-Scholes based)
│       ├── executor.py           # Web3 batch submission
│       ├── adaptive.py           # Adaptive k-multiplier (IL-based learning)
│       ├── config.py             # Configuration from environment
│       └── types.py              # Python data types
│
├── frontend/                     # Next.js 14 frontend
│   └── src/
│       ├── app/
│       │   ├── page.tsx          # Dashboard (stats + batch history)
│       │   ├── submit/page.tsx   # Submit Intent (sign + privacy tracker)
│       │   ├── mint/page.tsx     # Mint test tokens
│       │   ├── monitor/page.tsx  # Live pending intents + batch history
│       │   ├── privacy/page.tsx  # Privacy pipeline + commit-reveal demo
│       │   ├── layout.tsx        # Root layout with providers
│       │   └── providers.tsx     # wagmi + RainbowKit + TanStack Query
│       ├── components/
│       │   ├── Navbar.tsx        # Navigation + wallet connect
│       │   └── StatCard.tsx      # Reusable stat display
│       ├── config/
│       │   ├── wagmi.ts          # Chain + wallet config
│       │   ├── contracts.ts      # Contract addresses
│       │   └── abis.ts           # Minimal contract ABIs
│       └── hooks/
│           ├── useAgentApi.ts    # Agent API fetch hooks
│           └── useEip712Sign.ts  # EIP-712 signing via walletClient
│
├── deploy-sepolia.sh             # Deploy core contracts
├── setup-pool.sh                 # Deploy tokens + initialize pool
├── .env                          # Configuration (RPC, keys, addresses)
└── foundry.toml                  # Foundry configuration
```

---

## Setup & Run

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast)
- [Node.js](https://nodejs.org/) >= 18
- [Python](https://www.python.org/) >= 3.10
- MetaMask browser extension
- Sepolia ETH (from [sepoliafaucet.com](https://sepoliafaucet.com) or [faucets.chain.link](https://faucets.chain.link))

### 1. Clone & Install Dependencies

```bash
# Solidity dependencies
forge install

# Agent dependencies
cd agent
pip install -r requirements.txt
cd ..

# Frontend dependencies
cd frontend
npm install
cd ..
```

### 2. Configure Environment

Copy `.env.example` to `.env` and add your keys:

```bash
cp .env.example .env
```

Edit `.env` and fill in:

```bash
# Required: Sepolia RPC URL (get free from Alchemy or Infura)
RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY

# Required: Wallet private key (fund with Sepolia ETH, NO 0x prefix)
PRIVATE_KEY=your_64_char_hex_private_key_here
```

All contract addresses are pre-filled in `.env.example` - no need to change them.

Create `frontend/.env.local`:

```bash
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_walletconnect_project_id
```

Get a free WalletConnect project ID at [cloud.walletconnect.com](https://cloud.walletconnect.com).

### 3. Smart Contracts (Already Deployed)

**All contracts are already deployed on Sepolia and ready to use!**

The `.env.example` includes pre-deployed addresses:
- `HOOK_ADDRESS` - PrivBatchHook
- `EXECUTOR_ADDRESS` - BatchExecutor
- `COMMIT_ADDRESS` - CommitContract
- `TOKEN_A` / `TOKEN_B` - Test tokens (anyone can mint)

**You can skip deployment and go directly to Step 4.**

<details>
<summary>Optional: Deploy your own contracts</summary>

If you want to deploy fresh contracts:

```bash
# Deploy core contracts (Hook, Executor, CommitContract)
bash deploy-sepolia.sh

# Deploy test tokens + initialize pool
bash setup-pool.sh
```

Update `.env` with the printed contract addresses.

</details>

### 4. Start the Agent

```bash
cd agent
python3 -m src.main
```

Agent starts on `http://localhost:8000`. It will:
- Accept signed intents via POST `/intents`
- Check for batch threshold every 30 seconds
- Build Merkle trees and submit batch transactions

### 5. Start the Frontend

```bash
cd frontend
npm run dev
```

Frontend starts on `http://localhost:3000`.

### 6. Demo Flow

1. Open `http://localhost:3000`, connect MetaMask to Sepolia
2. **Mint Tokens** -- mint TTA and TTB to your wallet
3. **Submit Intent** -- fill in LP parameters, sign with MetaMask, submit to agent
4. **Monitor** -- watch pending intents queue up, see batches execute
5. **Dashboard** -- view system stats, gas savings, batch history
6. **Privacy Demo** -- try the commit-reveal scheme, see the privacy pipeline

---

## Agent API Reference

Base URL: `http://localhost:8000`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/intents` | Submit a signed LP intent |
| `GET` | `/intents/pending` | List pending intents (private data) |
| `GET` | `/batch/status` | Current batch status (pending count, last batch) |
| `GET` | `/batch/history` | All executed batches (root, tx hash, count, time) |
| `GET` | `/config` | Chain config, contract addresses, pool key |
| `GET` | `/optimizer/suggest` | Suggested tick range (query: `price`, `volatility`) |
| `GET` | `/adaptive/stats` | Adaptive parameters (k_multiplier, IL stats, gas) |

### Submit Intent (POST /intents)

```json
{
  "user": "0xYourAddress",
  "pool_currency0": "0x486C739A8A219026B6AB13aFf557c827Db4E267e",
  "pool_currency1": "0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E",
  "pool_fee": 3000,
  "pool_tick_spacing": 60,
  "pool_hooks": "0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00",
  "tick_lower": -120,
  "tick_upper": 120,
  "amount": 1000000000000000000,
  "nonce": 0,
  "deadline": 1700000000,
  "signature": "0x..."
}
```

The signature is an EIP-712 `signTypedData` over the `LPIntent` struct with domain `{name: "PrivBatch", version: "1", chainId: 11155111, verifyingContract: hookAddress}`.

---

## Frontend Pages

### Dashboard (`/`)
System overview with stat cards (pending intents, batches executed, estimated gas saved, adaptive k-multiplier) and a recent batch history table with Etherscan links.

### Submit Intent (`/submit`)
The core interaction page. Users fill in LP parameters (amount, tick range), sign via EIP-712 in MetaMask, and submit to the agent. Includes:
- Auto-suggested tick range from the optimizer
- Live privacy flow tracker showing each step (Create → Sign → Send → Queued)
- Side-by-side privacy panel: "Your Data (Private)" vs "MEV Bot View (On-Chain)"

### Mint Tokens (`/mint`)
Mint free TestTokenA (TTA) and TestTokenB (TTB) to your wallet. Shows current balances and transaction confirmation.

### Batch Monitor (`/monitor`)
Live view of pending intents (polls every 5s) with deadline countdowns, plus full batch history table with Merkle roots and Etherscan transaction links.

### Privacy Demo (`/privacy`)
Educational page showing the 6-step privacy pipeline. Includes:
- Live System State comparing hidden agent data vs public on-chain data
- Interactive commit-reveal demo using the CommitContract on Sepolia
- Shows what MEV bots can and cannot determine from on-chain data

---

## How It Works (Technical)

### EIP-712 Intent Signing

Users sign structured typed data in MetaMask. The domain and types match `IntentVerifier.sol`:

```
Domain: { name: "PrivBatch", version: "1", chainId: 11155111, verifyingContract: <hookAddress> }

Types:
  PoolKey(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)
  LPIntent(address user, PoolKey pool, int24 tickLower, int24 tickUpper, uint256 amount, uint256 nonce, uint256 deadline)
```

### Merkle Batching

The agent collects signed intents, computes `keccak256(abi.encodePacked(user, tickLower, tickUpper, amount, nonce, deadline, signature))` for each leaf, builds a Merkle tree (OpenZeppelin-compatible sorted pairs), and submits the root + proofs in a single transaction.

### Hook Verification

`PrivBatchHook` hooks into `beforeAddLiquidity`. The hook data contains the batch root, intents array, signatures array, and Merkle proofs. For each intent:
1. Verify the Merkle proof against the batch root
2. Recover the signer from the EIP-712 signature
3. Confirm the signer matches `intent.user`

If all pass, liquidity positions are minted atomically. If any fails, the entire batch reverts.

### Commit-Reveal Scheme

`CommitContract` provides an additional anti-MEV layer:
1. **Commit**: User submits `keccak256(intentData || salt)` on-chain. Only the hash is visible.
2. **Wait**: Minimum 5 blocks must pass (configurable `minRevealDelay`).
3. **Reveal**: User submits the original data + salt. Contract verifies the hash matches.

The delay ensures MEV bots cannot front-run the intent during the commitment window.

### Adaptive Range Optimization

The agent tracks impermanent loss (IL) and gas costs per batch. An adaptive `k_multiplier` adjusts the suggested tick range width:
- High IL → widen ranges (increase k)
- Low IL → tighten ranges (decrease k)
- Uses exponential moving average over recent batch results

---

## Key Addresses

```
# Core Contracts
PrivBatchHook:     0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00
BatchExecutor:     0x79dcDc67710C70be8Ef52e67C8295Fd0dA8A5722
CommitContract:    0x5f4E461b847fCB857639D1Ec7277485286b7613F

# Test Tokens
TestTokenA (TTA):  0x486C739A8A219026B6AB13aFf557c827Db4E267e
TestTokenB (TTB):  0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E

# Uniswap v4 (Sepolia Canonical)
PoolManager:       0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
PositionManager:   0x429ba70129df741b2ca2a85bc3a2a3328e5c09b4
Permit2:           0x000000000022D473030F116dDEE9F6B43aC78BA3
SwapRouter:        0xf13D190e9117920c703d79B5F33732e10049b115

# Deployer
Deployer:          0xd555576D8C8b40193743f701E810f6B5A259A15C

# Network
Chain:             Sepolia (11155111)
Explorer:          https://sepolia.etherscan.io
```

---

## Built With

- **Solidity 0.8.26** -- Smart contracts (Foundry)
- **Uniswap v4** -- Pool Manager, Position Manager, Hooks
- **OpenZeppelin** -- Hook base, Merkle proof verification
- **Python 3.10+** -- Off-chain agent (FastAPI, Web3.py)
- **Next.js 14** -- Frontend (App Router, TypeScript)
- **wagmi v2 + viem** -- Ethereum interactions
- **RainbowKit** -- Wallet connection
- **TanStack React Query** -- Data fetching
- **Tailwind CSS** -- Styling

---

## License

MIT
