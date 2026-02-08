# PrivBatch Agent Documentation

**Privacy-preserving batched LP position management for Uniswap v4**

---

## The MEV Problem

When you add liquidity to a Uniswap pool, your transaction is visible in the mempool before it's mined. MEV (Maximal Extractable Value) bots exploit this:

1. **See your pending LP transaction** in the mempool
2. **Front-run** by adding their own liquidity first
3. **Sandwich attack** by manipulating prices around your transaction
4. **Extract value** from your position

LPs lose an estimated **$500M+ annually** to MEV extraction.

---

## How PrivBatch Solves This

### The Privacy Pipeline

| Step | What Happens | Visibility |
|------|-------------|------------|
| 1. Intent Creation | User fills LP parameters in browser | **Private** (browser only) |
| 2. EIP-712 Signing | MetaMask signs structured typed data | **Private** (signature proves consent) |
| 3. Agent Queue | Signed intent sent to off-chain agent | **Private** (no on-chain footprint) |
| 4. Merkle Batching | Agent groups intents into Merkle tree | **Private** (individual data hidden in tree) |
| 5. Batch Execution | Single tx sends root + proofs to hook | **Public** (but all-or-nothing atomic) |
| 6. Hook Verification | Hook verifies proofs + signatures | **Public** (positions minted atomically) |

**Key insight:** By the time data hits the blockchain, all positions are already minted atomically in a single transaction. There's no window for MEV bots to front-run.

---

## Security Model: Agent API vs Mempool

### Q: Can't bots just monitor the agent API instead of the mempool?

In the demo, the `/intents/pending` endpoint is public so judges can see the queue. However, this is fundamentally different from mempool monitoring:

| Attack Vector | Mempool | PrivBatch Agent API |
|---------------|---------|---------------------|
| What bots see | Pending transactions | Intent data (not txs) |
| Can bot front-run? | **Yes** (same block) | **No** (different blocks) |
| Timing control | User's tx is public | Agent controls batch timing |
| Execution | Individual txs | Atomic batch (all-or-nothing) |

### Why API visibility doesn't enable MEV:

1. **Intents aren't transactions** - Bots can't insert them into a block
2. **Agent controls timing** - Bot doesn't know when batch will execute
3. **Atomic execution** - All positions mint in one tx, no sandwich window
4. **Different blocks** - By the time bot reacts, batch may already be mined

### Production hardening (not in demo):

- Add API authentication (JWT/API keys)
- Remove `/intents/pending` endpoint
- Rate limiting and IP allowlisting
- Private agent deployment (VPN/internal network)

> The demo API is intentionally open for hackathon demonstration purposes.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Frontend (Next.js)                        │
│  Dashboard | Submit Intent | Mint Tokens | Monitor | Privacy     │
└─────────────────────────────┬────────────────────────────────────┘
                              │ EIP-712 signed intents (HTTP)
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Agent (Python / FastAPI)                      │
│  Collector → Optimizer → Merkle Tree Builder → Batch Submitter   │
└─────────────────────────────┬────────────────────────────────────┘
                              │ Single batch transaction
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Smart Contracts (Sepolia)                      │
│  BatchExecutor → PositionManager → PoolManager + PrivBatchHook   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Deployed Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| PrivBatchHook | `0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00` |
| BatchExecutor | `0x79dcDc67710C70be8Ef52e67C8295Fd0dA8A5722` |
| CommitContract | `0x5f4E461b847fCB857639D1Ec7277485286b7613F` |
| TestTokenA (TTA) | `0x486C739A8A219026B6AB13aFf557c827Db4E267e` |
| TestTokenB (TTB) | `0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E` |

---

## Technical Details

### EIP-712 Intent Signing

Users sign structured typed data in MetaMask:

```
Domain: {
  name: "PrivBatch",
  version: "1",
  chainId: 11155111,
  verifyingContract: <hookAddress>
}

Types:
  PoolKey(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)
  LPIntent(address user, PoolKey pool, int24 tickLower, int24 tickUpper, uint256 amount, uint256 nonce, uint256 deadline)
```

### Merkle Batching

The agent:
1. Collects signed intents
2. Computes leaf: `keccak256(abi.encodePacked(user, tickLower, tickUpper, amount, nonce, deadline, signature))`
3. Builds Merkle tree (OpenZeppelin-compatible sorted pairs)
4. Submits root + proofs in single transaction

### Hook Verification

`PrivBatchHook` hooks into `beforeAddLiquidity`:
1. Verify Merkle proof against batch root
2. Recover signer from EIP-712 signature
3. Confirm signer matches `intent.user`
4. If all pass → mint positions atomically

---

## Hackathon Tracks

### Privacy DeFi Track
- **Commit-reveal scheme** hides intent data until execution
- **Merkle batching** obscures individual positions in the tree
- **EIP-712 signatures** prove consent without on-chain exposure
- **Atomic execution** eliminates sandwich attack window

### Agentic Finance Track
- **Autonomous agent** collects, optimizes, and executes batches
- **Adaptive k-multiplier** learns optimal tick ranges from IL history
- **Gas optimization** via batching (1 tx vs N individual txs)
- **24/7 operation** without manual intervention

---

## Built With

- **Solidity 0.8.26** - Smart contracts (Foundry)
- **Uniswap v4** - Pool Manager, Position Manager, Hooks
- **Python 3.10+** - Off-chain agent (FastAPI, Web3.py)
- **Next.js 14** - Frontend (App Router, TypeScript)
- **wagmi v2 + viem** - Ethereum interactions
- **RainbowKit** - Wallet connection

---

## License

MIT
