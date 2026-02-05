"use client";

import { useState } from "react";
import Link from "next/link";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
  useBlockNumber,
} from "wagmi";
import { keccak256, encodePacked, toHex, toBytes, pad } from "viem";
import { CommitContractABI } from "@/config/abis";
import { CONTRACTS } from "@/config/contracts";
import { usePendingIntents, useBatchHistory } from "@/hooks/useAgentApi";

const PIPELINE_STEPS = [
  {
    title: "1. Intent Creation",
    desc: "User fills in LP parameters on the Submit page. Everything stays in the browser -- nothing on-chain.",
    visibility: "private",
    color: "green",
  },
  {
    title: "2. EIP-712 Signing",
    desc: "MetaMask signs structured typed data. The signature proves consent without revealing data on-chain.",
    visibility: "private",
    color: "green",
  },
  {
    title: "3. Agent Queue",
    desc: "Signed intent is sent to the off-chain agent over HTTP. No on-chain footprint yet.",
    visibility: "private",
    color: "green",
  },
  {
    title: "4. Merkle Batching",
    desc: "Agent groups multiple intents into a Merkle tree. Each intent becomes a leaf -- individual data stays hidden inside the tree.",
    visibility: "private",
    color: "green",
  },
  {
    title: "5. Batch Execution",
    desc: "A single transaction sends the Merkle root + proofs to the hook. MEV bots see one batch tx, not individual positions.",
    visibility: "public (root + proofs)",
    color: "yellow",
  },
  {
    title: "6. Hook Verification",
    desc: "The Uniswap v4 hook verifies each Merkle proof and EIP-712 signature on-chain. All positions are minted atomically.",
    visibility: "public (verified)",
    color: "yellow",
  },
];

export default function PrivacyPage() {
  const { address } = useAccount();
  const { data: pending } = usePendingIntents();
  const { data: history } = useBatchHistory();

  // Commit-reveal state
  const [secretText, setSecretText] = useState("");
  const [salt, setSalt] = useState("");
  const [computedHash, setComputedHash] = useState("");
  const [committedText, setCommittedText] = useState("");
  const [committedSalt, setCommittedSalt] = useState("");

  const { writeContract: commitWrite, data: commitTxHash, isPending: isCommitting, reset: resetCommit } = useWriteContract();
  const { isLoading: isCommitConfirming, isSuccess: commitSuccess } = useWaitForTransactionReceipt({ hash: commitTxHash });

  const { writeContract: revealWrite, data: revealTxHash, isPending: isRevealing, reset: resetReveal } = useWriteContract();
  const { isLoading: isRevealConfirming, isSuccess: revealSuccess } = useWaitForTransactionReceipt({ hash: revealTxHash });

  const { data: hasCommit } = useReadContract({
    address: CONTRACTS.COMMIT,
    abi: CommitContractABI,
    functionName: "hasValidCommit",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 },
  });

  const { data: commitInfo } = useReadContract({
    address: CONTRACTS.COMMIT,
    abi: CommitContractABI,
    functionName: "commits",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 },
  });

  const { data: minDelay } = useReadContract({
    address: CONTRACTS.COMMIT,
    abi: CommitContractABI,
    functionName: "minRevealDelay",
  });

  const { data: currentBlock } = useBlockNumber({ watch: true });

  const commitBlock = commitInfo ? (commitInfo as [string, bigint, boolean])[1] : BigInt(0);
  const revealReady =
    hasCommit &&
    currentBlock &&
    minDelay &&
    currentBlock >= commitBlock + (minDelay as bigint);

  const computeHash = () => {
    if (!secretText || !salt) return;
    const intentData = toHex(toBytes(secretText));
    const saltBytes = pad(toHex(toBytes(salt)), { size: 32 });
    const hash = keccak256(encodePacked(["bytes", "bytes32"], [intentData, saltBytes]));
    setComputedHash(hash);
  };

  const handleCommit = () => {
    if (!computedHash) return;
    resetCommit();
    setCommittedText(secretText);
    setCommittedSalt(salt);
    commitWrite({
      address: CONTRACTS.COMMIT,
      abi: CommitContractABI,
      functionName: "commit",
      args: [computedHash as `0x${string}`],
    });
  };

  const handleReveal = () => {
    if (!committedText || !committedSalt) return;
    resetReveal();
    const intentData = toHex(toBytes(committedText));
    const saltBytes = pad(toHex(toBytes(committedSalt)), { size: 32 });
    revealWrite({
      address: CONTRACTS.COMMIT,
      abi: CommitContractABI,
      functionName: "reveal",
      args: [intentData as `0x${string}`, saltBytes as `0x${string}`],
    });
  };

  return (
    <div className="space-y-10">
      <div>
        <h1 className="text-2xl font-bold">Privacy Guarantees</h1>
        <p className="mt-1 text-gray-400">
          How PrivBatch protects LP intents from MEV extraction at every step
        </p>
      </div>

      {/* Link to real flow */}
      <div className="rounded-xl border border-violet-500/30 bg-violet-500/10 p-4 flex items-center justify-between">
        <div>
          <p className="text-sm text-violet-200">
            See the privacy flow in action while submitting a real intent
          </p>
          <p className="text-xs text-violet-300/60 mt-1">
            The Submit page shows a live privacy tracker as you sign and submit
          </p>
        </div>
        <Link
          href="/submit"
          className="shrink-0 px-4 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium transition-colors"
        >
          Go to Submit
        </Link>
      </div>

      {/* Privacy Pipeline */}
      <div>
        <h2 className="text-lg font-semibold mb-4">Privacy Pipeline</h2>
        <div className="space-y-3">
          {PIPELINE_STEPS.map((step, i) => (
            <div
              key={i}
              className="rounded-lg border border-white/10 bg-white/5 p-4 flex gap-4"
            >
              <div className="flex-1">
                <h3 className="font-medium text-white">{step.title}</h3>
                <p className="text-sm text-gray-400 mt-1">{step.desc}</p>
              </div>
              <div className="shrink-0">
                <span
                  className={`text-xs px-2 py-1 rounded ${
                    step.color === "green"
                      ? "bg-green-500/20 text-green-300 border border-green-500/30"
                      : "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30"
                  }`}
                >
                  {step.visibility}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Live System State - shows what would be visible on-chain right now */}
      <div>
        <h2 className="text-lg font-semibold mb-4">Live System State</h2>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Private side */}
          <div className="rounded-xl border border-green-500/20 bg-green-500/5 p-5 space-y-4">
            <h3 className="font-semibold text-green-400">Hidden from chain (Agent Only)</h3>
            <div className="space-y-2 text-sm">
              <div className="bg-black/30 rounded p-3 flex justify-between">
                <span className="text-gray-400">Pending intents</span>
                <span className="text-green-300 font-mono">{pending?.length ?? 0}</span>
              </div>
              {pending && pending.length > 0 && (
                <div className="bg-black/30 rounded p-3 space-y-1">
                  <p className="text-gray-400 text-xs mb-2">Intent details (private):</p>
                  {pending.slice(0, 3).map((intent, i) => (
                    <div key={i} className="text-xs font-mono text-green-300/80">
                      user: {intent.user.slice(0, 8)}... | range: [{intent.tick_lower}, {intent.tick_upper}] | amt: {BigInt(intent.amount).toLocaleString()}
                    </div>
                  ))}
                  {pending.length > 3 && (
                    <p className="text-xs text-gray-500">+{pending.length - 3} more...</p>
                  )}
                </div>
              )}
              <p className="text-xs text-green-400/60">
                These details exist only in the agent&apos;s memory. Nothing is on-chain until batch execution.
              </p>
            </div>
          </div>

          {/* Public side */}
          <div className="rounded-xl border border-red-500/20 bg-red-500/5 p-5 space-y-4">
            <h3 className="font-semibold text-red-400">Visible on-chain (MEV Bots See This)</h3>
            <div className="space-y-2 text-sm">
              <div className="bg-black/30 rounded p-3 flex justify-between">
                <span className="text-gray-400">Pending intents visible</span>
                <span className="text-red-300 font-mono">0</span>
              </div>
              <div className="bg-black/30 rounded p-3 flex justify-between">
                <span className="text-gray-400">Executed batch roots</span>
                <span className="text-gray-300 font-mono">{history?.length ?? 0}</span>
              </div>
              {history && history.length > 0 && (
                <div className="bg-black/30 rounded p-3 space-y-1">
                  <p className="text-gray-400 text-xs mb-2">Past batch roots (public):</p>
                  {history.slice(-3).map((batch, i) => (
                    <div key={i} className="text-xs font-mono text-gray-300/80">
                      root: {batch.root.slice(0, 14)}... ({batch.intent_count} intents)
                    </div>
                  ))}
                </div>
              )}
              <p className="text-xs text-red-400/60">
                Bots see batch roots after execution, but cannot extract individual intent parameters.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Commit-Reveal Demo */}
      <div>
        <h2 className="text-lg font-semibold mb-2">
          Commit-Reveal Demo (On-Chain)
        </h2>
        <p className="text-sm text-gray-400 mb-4">
          Try the commit-reveal pattern used by PrivBatch. Commit a hash on-chain, then reveal the data after a delay.
          This demonstrates how intent data can be hidden from MEV bots during the commitment window.
        </p>

        {!address && (
          <div className="rounded-xl border border-yellow-500/30 bg-yellow-500/10 p-6 text-yellow-200">
            Connect your wallet to try the commit-reveal demo on Sepolia
          </div>
        )}

        {address && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Left: User actions */}
            <div className="rounded-xl border border-white/10 bg-white/5 p-6 space-y-4">
              <h3 className="font-semibold text-violet-400">
                Step 1: Commit a Secret
              </h3>

              <div>
                <label className="block text-sm text-gray-400 mb-1">
                  Secret data (e.g. your LP intent)
                </label>
                <input
                  type="text"
                  value={secretText}
                  onChange={(e) => setSecretText(e.target.value)}
                  placeholder="LP 500 TTA/TTB [-120, 120]"
                  className="w-full rounded-lg bg-white/10 border border-white/10 px-3 py-2 text-white text-sm focus:outline-none focus:border-violet-500"
                />
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-1">Salt (random string)</label>
                <input
                  type="text"
                  value={salt}
                  onChange={(e) => setSalt(e.target.value)}
                  placeholder="my_random_salt_123"
                  className="w-full rounded-lg bg-white/10 border border-white/10 px-3 py-2 text-white text-sm focus:outline-none focus:border-violet-500"
                />
              </div>

              <button
                onClick={computeHash}
                disabled={!secretText || !salt}
                className="w-full py-2 rounded-lg bg-white/10 hover:bg-white/20 disabled:opacity-50 text-white text-sm transition-colors"
              >
                Compute keccak256 Hash
              </button>

              {computedHash && (
                <div className="text-xs font-mono break-all text-gray-300 bg-black/30 rounded p-2">
                  hash: {computedHash}
                </div>
              )}

              <div className="flex gap-3">
                <button
                  onClick={handleCommit}
                  disabled={!computedHash || isCommitting || isCommitConfirming}
                  className="flex-1 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-sm transition-colors"
                >
                  {isCommitting
                    ? "Confirm in wallet..."
                    : isCommitConfirming
                    ? "Committing..."
                    : "Commit Hash On-Chain"}
                </button>

                <button
                  onClick={handleReveal}
                  disabled={!revealReady || isRevealing || isRevealConfirming}
                  className="flex-1 py-2 rounded-lg bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-sm transition-colors"
                >
                  {isRevealing
                    ? "Confirm in wallet..."
                    : isRevealConfirming
                    ? "Revealing..."
                    : `Reveal Data${!revealReady && hasCommit ? " (wait ~5 blocks)" : ""}`}
                </button>
              </div>

              {commitSuccess && (
                <p className="text-sm text-green-400">
                  Committed! Wait {(minDelay as bigint)?.toString() ?? "5"} blocks
                  (block {(commitBlock + (minDelay as bigint || BigInt(5))).toString()}), then reveal.
                  Current block: {currentBlock?.toString() ?? "..."}
                </p>
              )}
              {revealSuccess && (
                <p className="text-sm text-green-400">
                  Revealed! The contract verified your data matches the committed hash.
                </p>
              )}
            </div>

            {/* Right: What on-chain shows */}
            <div className="rounded-xl border border-red-500/20 bg-red-500/5 p-6 space-y-4">
              <h3 className="font-semibold text-red-400">
                What MEV Bots See On-Chain
              </h3>

              <div className="space-y-3">
                <div className="bg-black/30 rounded p-3">
                  <p className="text-xs text-gray-500 mb-1">Transaction:</p>
                  <p className="text-xs font-mono text-gray-300">
                    CommitContract.commit(bytes32)
                  </p>
                </div>

                <div className="bg-black/30 rounded p-3">
                  <p className="text-xs text-gray-500 mb-1">Argument (the hash):</p>
                  <p className="text-xs font-mono text-gray-300 break-all">
                    {computedHash || "0x0000...0000"}
                  </p>
                </div>

                <div className="bg-black/30 rounded p-3 border border-red-500/20">
                  <p className="text-xs text-red-400 font-medium mb-2">Bot cannot determine:</p>
                  <ul className="text-xs text-red-300/80 space-y-1">
                    <li>- What token pair you&apos;re providing liquidity to</li>
                    <li>- Your tick range (price boundaries)</li>
                    <li>- How much liquidity you&apos;re adding</li>
                    <li>- When you plan to execute</li>
                  </ul>
                </div>

                <div className="bg-black/30 rounded p-3">
                  <p className="text-xs text-gray-500 mb-1">After reveal (5+ blocks later):</p>
                  <p className="text-xs text-gray-400">
                    Data becomes visible, but by then the batch has already been executed atomically.
                    The window for front-running has passed.
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
