# PrivBatch Coordinator -- Demo Script (~4-5 min)

## Pre-Demo Checklist

Before starting, make sure:

- [ ] Agent running: `cd agent && python3 -m src.main`
- [ ] Frontend running: `cd frontend && npm run dev`
- [ ] Browser open at `http://localhost:3000`
- [ ] MetaMask installed, connected to **Sepolia**, funded with Sepolia ETH
- [ ] Two browser tabs ready: one for the app, one for Etherscan (https://sepolia.etherscan.io)

---

## Part 1: The Problem (30 seconds)

**What you say:**

> "LPs on Uniswap are losing money to MEV bots every day. When you submit a transaction to add liquidity, your intent -- the token pair, the tick range, the amount -- is broadcast to the mempool in plain text. MEV bots decode this instantly and sandwich your position: they buy before you, push the price up, you get a worse entry, and the bot profits. This is a real problem -- billions have been extracted from LPs."

**What you show:** Nothing yet, stay on the Dashboard page. The audience sees the clean UI with the system overview.

---

## Part 2: Our Solution -- Architecture Overview (30 seconds)

**What you say:**

> "PrivBatch solves this with a three-layer architecture. First, users sign their LP intents off-chain using EIP-712 typed data -- nothing goes on-chain. Second, an off-chain agent collects these signed intents, batches them into a Merkle tree, and submits a single transaction. Third, a Uniswap v4 hook verifies every Merkle proof and every signature on-chain, and mints all positions atomically in one block. By the time anything is visible on-chain, it's already executed. There is no mempool window, so there is nothing to front-run."

**What you show:** Quickly point at the Dashboard stat cards (Pending Intents, Batches Executed, Gas Saved, k Multiplier) to show the system is live.

---

## Part 3: Connect Wallet + Mint Tokens (30 seconds)

**What you say:**

> "Let me walk you through the full flow. First, I connect my wallet on Sepolia."

**What you do:**
1. Click **Connect Wallet** button in the navbar
2. Connect MetaMask to Sepolia

> "Now I need some test tokens. These are MockERC20 tokens deployed on Sepolia -- anyone can mint them for free."

**What you do:**
1. Click **Mint Tokens** in the navbar
2. Enter amount: `1000`
3. Click **Mint TestTokenA** -- confirm in MetaMask
4. Click **Mint TestTokenB** -- confirm in MetaMask
5. Wait for confirmations, show balances update

**What you show:** The Mint page showing token names (TTA, TTB), your balances updating after mint.

---

## Part 4: Submit Intent with Privacy Tracker (60 seconds)

> "This is the core of PrivBatch. I'm going to add liquidity -- but instead of broadcasting my position to the mempool, I sign an intent off-chain."

**What you do:**
1. Click **Submit Intent** in the navbar
2. Point out the form fields: Amount, Tick Range (auto-suggested by the optimizer), Nonce, Deadline
3. Click **Get Suggested Range** to show the optimizer working
4. Enter amount: `500`
5. Point out the **privacy sidebar** on the right:
   - "Your Data (Private)" panel in green -- shows your actual parameters
   - "MEV Bot View (On-Chain)" panel in red -- shows "Nothing submitted" / hashes only

> "Watch the privacy flow tracker at the top. Step 1: I've created my intent -- everything is still in the browser, nothing on-chain."

6. Click **Sign & Submit**
7. MetaMask popup appears -- point to it:

> "Step 2: MetaMask asks me to sign EIP-712 typed data. This is NOT a transaction -- it's just a signature. No gas, no mempool, no on-chain footprint."

8. Confirm the signature in MetaMask

> "Step 3: The signed intent is sent to our agent over HTTP. Step 4: It's queued for the next batch. Notice the privacy tracker -- all four steps are green. An MEV bot monitoring the chain sees absolutely nothing."

**What you show:** The privacy flow tracker at the top progressing through all 4 steps. The green "Your Data" panel showing your real parameters. The red "MEV Bot View" panel showing hashes and "hidden" labels.

---

## Part 5: Privacy Demo -- Side-by-Side Simulation (60 seconds)

> "Let me show you the difference visually."

**What you do:**
1. Click **Privacy Demo** in the navbar
2. The simulation input is pre-filled with amount 1000, tick range [-120, 120]
3. Click **Run Simulation**
4. Watch both columns animate simultaneously

> "On the left -- a standard Uniswap LP. Watch what the MEV bot sees at each step."

5. Point to the left column as steps appear:
   - Step 1: "SCANNING MEMPOOL" -- bot sees token pair, tick range, amount, your address. All in red.
   - Step 2: "TARGET DETECTED" -- all parameters visible in mempool.
   - Step 3: "FRONT-RUNNING" -- bot buys tokens before you, pushes price up.
   - Step 4: "PROFIT EXTRACTED" -- you got a worse price, bot profits.

> "Now look at the right -- the same position through PrivBatch."

6. Point to the right column:
   - Step 1: "NO SIGNAL" -- everything shows "encrypted" in green.
   - Step 2: "NO SIGNAL" -- no mempool activity.
   - Step 3: "NO SIGNAL" -- Merkle tree built off-chain.
   - Step 4: "TOO LATE" -- batch executes atomically. Only a Merkle root is on-chain.

7. Point to the summary card that appears:

> "4 out of 4 parameters exposed in the normal flow. Zero out of 4 in PrivBatch. MEV extraction: eliminated."

**What you show:** The animated side-by-side simulation. Red badges (SCANNING, DETECTED, FRONT-RUNNING, PROFITED) on the left vs grey/green badges (NO SIGNAL, TOO LATE) on the right.

---

## Part 6: Verify On-Chain -- Calldata Proof (45 seconds)

> "Don't just trust the simulation. Let me prove this with actual on-chain data."

**What you do:**
1. Scroll down to the **Verify On-Chain** section
2. Point to the side-by-side calldata comparison:

> "On the left: the decoded calldata of a normal LP transaction. Nine parameters fully visible -- currency0, currency1, fee, tick range, amount, sender. An MEV bot decodes this in milliseconds."

3. Point to the right panel:

> "On the right: the PrivBatch commit calldata. Total size: 36 bytes. That's a 4-byte function selector and a 32-byte keccak256 hash. That's it. No token addresses, no tick range, no amount. keccak256 is a one-way function -- you cannot reverse it to get the parameters."

4. Point to the hash computation proof below:

> "And you can verify: the hash is computed from the real parameters. Change any input and the hash changes completely."

5. Scroll to the **Transaction Inspector**, click one of the example buttons (e.g., "Token Mint")
6. Click **Decode**, show the decoded transaction:

> "Here's a real Sepolia transaction decoded. You can see every parameter in the calldata. Now compare that with a commit transaction where only the hash is visible."

**What you show:** The calldata comparison (red vs green panels), the hash computation, and a decoded real transaction.

---

## Part 7: Monitor + Dashboard (30 seconds)

> "Let me check the system state."

**What you do:**
1. Click **Monitor** in the navbar
2. Point to the Pending Intents table:

> "Here's the intent I just submitted -- queued in the agent, waiting for the batch threshold. The deadline is counting down in real time. None of this data is on-chain."

3. Point to the Batch History table (may be empty or have entries):

> "Once enough intents accumulate, the agent builds a Merkle tree and submits a single batch transaction. Each row here is one atomic batch -- one transaction, multiple LP positions, all verified by the hook."

4. Click **Dashboard**:

> "The dashboard shows the full system overview -- pending intents, total batches executed, estimated gas savings from batching, and the adaptive k-multiplier that learns from impermanent loss history to suggest better tick ranges over time."

**What you show:** Monitor page with pending intents and real-time countdown. Dashboard with stat cards.

---

## Part 8: Commit-Reveal Demo -- On-Chain Proof (45 seconds)

> "One last thing. PrivBatch also uses a commit-reveal scheme for additional protection. Let me demonstrate on-chain."

**What you do:**
1. Click **Privacy Demo** in the navbar
2. Scroll to the **Commit-Reveal Demo** section
3. Enter secret data: `LP 500 TTA/TTB [-120, 120]`
4. Enter salt: `demo_salt_123`
5. Click **Compute keccak256 Hash** -- show the computed hash
6. Click **Commit Hash On-Chain** -- confirm in MetaMask

> "I just committed a hash on Sepolia. The transaction is on-chain. But what can an MEV bot see?"

7. Point to the right panel "What MEV Bots See":

> "They see: CommitContract.commit(bytes32). One argument -- the hash. They cannot determine the token pair, the tick range, the amount, or when I plan to execute. The data stays private for at least 5 blocks."

8. (Optional, if time permits) Wait for 5 blocks, then click **Reveal Data**:

> "After the delay, I reveal. The contract verifies my data matches the committed hash. But by this time, the batch has already executed. The front-running window was closed the entire time."

**What you show:** The commit transaction in MetaMask, the "Bot cannot determine" list, the Etherscan link.

---

## Part 9: Wrap Up (15 seconds)

**What you say:**

> "To summarize: PrivBatch keeps LP intents private through off-chain EIP-712 signing, Merkle tree batching, atomic on-chain execution via a Uniswap v4 hook, and a commit-reveal scheme. MEV bots see nothing until it's too late. All of this is deployed and running on Sepolia today. The contracts, the agent, and the frontend are fully open-source."

**What you show:** Dashboard page as the closing shot.

---

## Key Contract Addresses to Reference

If anyone asks, these are on Sepolia:

| Contract | Address |
|----------|---------|
| PrivBatchHook | `0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00` |
| BatchExecutor | `0x79dcDc67710C70be8Ef52e67C8295Fd0dA8A5722` |
| CommitContract | `0x5f4E461b847fCB857639D1Ec7277485286b7613F` |
| TestTokenA (TTA) | `0x486C739A8A219026B6AB13aFf557c827Db4E267e` |
| TestTokenB (TTB) | `0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E` |

---

## Timing Summary

| Part | Duration | What Happens |
|------|----------|-------------|
| 1. The Problem | 30s | Explain MEV extraction |
| 2. Architecture | 30s | Three-layer solution overview |
| 3. Connect + Mint | 30s | Wallet connection, mint TTA/TTB |
| 4. Submit Intent | 60s | Sign EIP-712, privacy tracker, submit to agent |
| 5. Privacy Simulation | 60s | Side-by-side Normal vs PrivBatch |
| 6. Verify On-Chain | 45s | Calldata comparison, tx inspector |
| 7. Monitor + Dashboard | 30s | Pending intents, batch history, stats |
| 8. Commit-Reveal | 45s | On-chain commit, show what bots see |
| 9. Wrap Up | 15s | Summary |
| **Total** | **~4.5 min** | |

---

## Backup Plan

If MetaMask is slow or a transaction takes too long:

- **Skip the mint step**: Tokens might already be minted from a previous run. Check balances first.
- **Skip the commit-reveal**: It requires waiting 5 blocks. Mention it verbally and show the UI without executing.
- **Pre-submit intents**: Before the demo, submit 2-3 intents so the Monitor page has data to show.
- **Pre-run the simulation**: If short on time, have the Privacy Demo simulation already completed so you can just point at the results.
