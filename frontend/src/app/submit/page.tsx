"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { parseEther, keccak256, encodePacked, toHex, numberToHex } from "viem";
import { useAgentConfig, useSuggestedRange, submitIntent } from "@/hooks/useAgentApi";
import { useEip712Sign } from "@/hooks/useEip712Sign";

const NONCE_KEY = "privbatch_nonce_";

function getNextNonce(address: string): number {
  if (typeof window === "undefined") return 0;
  const key = NONCE_KEY + address.toLowerCase();
  const stored = localStorage.getItem(key);
  return stored ? parseInt(stored, 10) : 0;
}

function incrementNonce(address: string) {
  if (typeof window === "undefined") return;
  const key = NONCE_KEY + address.toLowerCase();
  const current = getNextNonce(address);
  localStorage.setItem(key, String(current + 1));
}

type FlowStep = "idle" | "filling" | "signing" | "submitting" | "queued" | "error";

function StepIndicator({ current }: { current: FlowStep }) {
  const steps: { key: FlowStep; label: string; privLabel: string }[] = [
    { key: "filling",    label: "Create Intent",   privLabel: "Browser only" },
    { key: "signing",    label: "EIP-712 Sign",    privLabel: "Browser only" },
    { key: "submitting", label: "Send to Agent",   privLabel: "Encrypted channel" },
    { key: "queued",     label: "Queued in Batch",  privLabel: "Hidden in Merkle tree" },
  ];

  const getIdx = (s: FlowStep) => steps.findIndex((x) => x.key === s);
  const currentIdx = getIdx(current);

  return (
    <div className="flex items-center gap-1 overflow-x-auto pb-1">
      {steps.map((step, i) => {
        const done = currentIdx > i;
        const active = currentIdx === i;
        return (
          <div key={step.key} className="flex items-center gap-1">
            <div
              className={`flex flex-col items-center px-3 py-2 rounded-lg text-xs transition-all ${
                active
                  ? "bg-violet-500/20 border border-violet-500/40 text-white"
                  : done
                  ? "bg-green-500/10 border border-green-500/30 text-green-300"
                  : "bg-white/5 border border-white/10 text-gray-500"
              }`}
            >
              <span className="font-medium">{step.label}</span>
              <span className={`mt-0.5 ${active ? "text-violet-300" : done ? "text-green-400" : "text-gray-600"}`}>
                {done ? "private" : step.privLabel}
              </span>
            </div>
            {i < steps.length - 1 && (
              <span className={`text-lg ${done ? "text-green-500" : "text-gray-600"}`}>&rarr;</span>
            )}
          </div>
        );
      })}
    </div>
  );
}

export default function SubmitIntentPage() {
  const { address } = useAccount();
  const { data: config } = useAgentConfig();
  const { signIntent, isReady } = useEip712Sign();

  const [amount, setAmount] = useState("100");
  const [price, setPrice] = useState(1.0);
  const [volatility, setVolatility] = useState(0.05);
  const [useAuto, setUseAuto] = useState(true);
  const [manualLower, setManualLower] = useState(-120);
  const [manualUpper, setManualUpper] = useState(120);

  const [flowStep, setFlowStep] = useState<FlowStep>("idle");
  const [errorMsg, setErrorMsg] = useState("");
  const [lastResult, setLastResult] = useState<Record<string, unknown> | null>(null);
  const [signature, setSignature] = useState("");
  const [intentHash, setIntentHash] = useState("");

  const { data: suggested } = useSuggestedRange(
    useAuto ? price : 0,
    useAuto ? volatility : 0
  );

  const tickLower = useAuto ? (suggested?.tick_lower ?? -120) : manualLower;
  const tickUpper = useAuto ? (suggested?.tick_upper ?? 120) : manualUpper;

  // Derive flow step from user interaction
  const interacting = address && config && (amount !== "" || !useAuto);
  const displayStep: FlowStep = flowStep === "idle" && interacting ? "filling" : flowStep;

  const handleSubmit = async () => {
    if (!address || !config || !isReady) return;

    setFlowStep("signing");
    setErrorMsg("");
    setLastResult(null);
    setSignature("");
    setIntentHash("");

    try {
      const nonce = getNextNonce(address);
      const deadline = Math.floor(Date.now() / 1000) + 3600;

      const poolKey = config.pool_key;

      const intentParams = {
        user: address as `0x${string}`,
        pool: {
          currency0: poolKey.currency0 as `0x${string}`,
          currency1: poolKey.currency1 as `0x${string}`,
          fee: poolKey.fee,
          tickSpacing: poolKey.tickSpacing,
          hooks: poolKey.hooks as `0x${string}`,
        },
        tickLower,
        tickUpper,
        amount: parseEther(amount),
        nonce: BigInt(nonce),
        deadline: BigInt(deadline),
      };

      // Compute a display hash of the intent (simplified)
      const hash = keccak256(
        encodePacked(
          ["address", "int24", "int24", "uint256"],
          [address, tickLower, tickUpper, parseEther(amount)]
        )
      );
      setIntentHash(hash);

      const sig = await signIntent(
        intentParams,
        config.hook_address as `0x${string}`
      );
      setSignature(sig);

      setFlowStep("submitting");

      const result = await submitIntent({
        user: address,
        pool_currency0: poolKey.currency0,
        pool_currency1: poolKey.currency1,
        pool_fee: poolKey.fee,
        pool_tick_spacing: poolKey.tickSpacing,
        pool_hooks: poolKey.hooks,
        tick_lower: tickLower,
        tick_upper: tickUpper,
        amount: Number(parseEther(amount)),
        nonce: nonce,
        deadline: deadline,
        signature: sig,
      });

      setFlowStep("queued");
      setLastResult(result);
      incrementNonce(address);
    } catch (e: unknown) {
      setFlowStep("error");
      setErrorMsg(e instanceof Error ? e.message : "Unknown error");
    }
  };

  const resetFlow = () => {
    setFlowStep("idle");
    setSignature("");
    setIntentHash("");
    setLastResult(null);
    setErrorMsg("");
  };

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">Submit LP Intent</h1>
        <p className="mt-1 text-gray-400">
          Sign and submit a private LP intent to the batch coordinator
        </p>
      </div>

      {!address && (
        <div className="rounded-xl border border-yellow-500/30 bg-yellow-500/10 p-6 text-yellow-200">
          Connect your wallet to submit intents
        </div>
      )}

      {address && config && (
        <>
          {/* Privacy Flow Tracker */}
          <div className="rounded-xl border border-white/10 bg-white/5 p-4">
            <h3 className="text-sm text-gray-400 mb-3">Privacy Flow</h3>
            <StepIndicator current={displayStep} />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Left: Intent Form (2 cols) */}
            <div className="lg:col-span-2 space-y-6">
              {/* Pool Info */}
              <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                <h3 className="text-sm text-gray-400 mb-2">Pool</h3>
                <div className="grid grid-cols-2 gap-2 text-xs font-mono">
                  <div>
                    <span className="text-gray-500">currency0: </span>
                    {config.pool_key.currency0?.slice(0, 10)}...
                  </div>
                  <div>
                    <span className="text-gray-500">currency1: </span>
                    {config.pool_key.currency1?.slice(0, 10)}...
                  </div>
                  <div>
                    <span className="text-gray-500">fee: </span>
                    {config.pool_key.fee}
                  </div>
                  <div>
                    <span className="text-gray-500">hook: </span>
                    {config.pool_key.hooks?.slice(0, 10)}...
                  </div>
                </div>
              </div>

              {/* Amount */}
              <div>
                <label className="block text-sm text-gray-400 mb-2">
                  Liquidity Amount (tokens)
                </label>
                <input
                  type="number"
                  value={amount}
                  onChange={(e) => { setAmount(e.target.value); if (flowStep === "idle") setFlowStep("idle"); }}
                  className="w-full rounded-lg bg-white/10 border border-white/10 px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-violet-500"
                />
              </div>

              {/* Tick Range */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="text-sm text-gray-400">Tick Range</label>
                  <button
                    onClick={() => setUseAuto(!useAuto)}
                    className="text-xs text-violet-400 hover:text-violet-300"
                  >
                    {useAuto ? "Switch to manual" : "Switch to auto"}
                  </button>
                </div>

                {useAuto ? (
                  <div className="space-y-3">
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block text-xs text-gray-500 mb-1">Price</label>
                        <input
                          type="number"
                          step="0.01"
                          value={price}
                          onChange={(e) => setPrice(parseFloat(e.target.value) || 0)}
                          className="w-full rounded-lg bg-white/10 border border-white/10 px-3 py-2 text-white text-sm focus:outline-none focus:border-violet-500"
                        />
                      </div>
                      <div>
                        <label className="block text-xs text-gray-500 mb-1">Volatility</label>
                        <input
                          type="number"
                          step="0.01"
                          value={volatility}
                          onChange={(e) => setVolatility(parseFloat(e.target.value) || 0)}
                          className="w-full rounded-lg bg-white/10 border border-white/10 px-3 py-2 text-white text-sm focus:outline-none focus:border-violet-500"
                        />
                      </div>
                    </div>
                    <div className="flex items-center gap-4 text-sm">
                      <span className="text-gray-400">
                        Suggested: [{tickLower}, {tickUpper}]
                      </span>
                      {suggested && (
                        <span className="text-xs text-gray-500">
                          k={suggested.k_multiplier.toFixed(2)}
                        </span>
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs text-gray-500 mb-1">Tick Lower</label>
                      <input
                        type="number"
                        step={60}
                        value={manualLower}
                        onChange={(e) => setManualLower(parseInt(e.target.value) || 0)}
                        className="w-full rounded-lg bg-white/10 border border-white/10 px-3 py-2 text-white text-sm focus:outline-none focus:border-violet-500"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-500 mb-1">Tick Upper</label>
                      <input
                        type="number"
                        step={60}
                        value={manualUpper}
                        onChange={(e) => setManualUpper(parseInt(e.target.value) || 0)}
                        className="w-full rounded-lg bg-white/10 border border-white/10 px-3 py-2 text-white text-sm focus:outline-none focus:border-violet-500"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Metadata */}
              <div className="text-xs text-gray-500 space-y-1">
                <div>Nonce: {address ? getNextNonce(address) : "---"}</div>
                <div>Deadline: +1 hour from now</div>
              </div>

              {/* Submit Button */}
              {flowStep !== "queued" ? (
                <button
                  onClick={handleSubmit}
                  disabled={flowStep === "signing" || flowStep === "submitting" || !isReady}
                  className="w-full py-3 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white font-semibold transition-colors"
                >
                  {flowStep === "signing"
                    ? "Sign in wallet..."
                    : flowStep === "submitting"
                    ? "Submitting to agent..."
                    : "Sign & Submit Intent"}
                </button>
              ) : (
                <button
                  onClick={resetFlow}
                  className="w-full py-3 rounded-lg bg-white/10 hover:bg-white/20 text-white font-semibold transition-colors"
                >
                  Submit Another Intent
                </button>
              )}

              {/* Status Messages */}
              {flowStep === "queued" && (
                <div className="rounded-lg border border-green-500/30 bg-green-500/10 p-4 text-green-200">
                  Intent accepted! Pending count:{" "}
                  {(lastResult as Record<string, number>)?.pending_count ?? "?"}
                </div>
              )}

              {flowStep === "error" && (
                <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-4 text-red-200">
                  <p>Error: {errorMsg}</p>
                  <button onClick={resetFlow} className="mt-2 text-xs underline text-red-300">
                    Try again
                  </button>
                </div>
              )}
            </div>

            {/* Right: Privacy Sidebar */}
            <div className="space-y-4">
              {/* What YOU see */}
              <div className="rounded-xl border border-green-500/20 bg-green-500/5 p-4 space-y-3">
                <h3 className="text-sm font-semibold text-green-400">Your Data (Private)</h3>
                <div className="space-y-2 text-xs">
                  <div className="bg-black/30 rounded p-2">
                    <span className="text-gray-500">Amount: </span>
                    <span className="text-white font-mono">{amount || "---"} tokens</span>
                  </div>
                  <div className="bg-black/30 rounded p-2">
                    <span className="text-gray-500">Range: </span>
                    <span className="text-white font-mono">[{tickLower}, {tickUpper}]</span>
                  </div>
                  {signature && (
                    <div className="bg-black/30 rounded p-2 break-all">
                      <span className="text-gray-500">Signature: </span>
                      <span className="text-green-300 font-mono">{signature.slice(0, 20)}...{signature.slice(-8)}</span>
                    </div>
                  )}
                  <p className="text-green-400/70 mt-1">
                    All details stay in your browser + agent only
                  </p>
                </div>
              </div>

              {/* What MEV BOTS see */}
              <div className="rounded-xl border border-red-500/20 bg-red-500/5 p-4 space-y-3">
                <h3 className="text-sm font-semibold text-red-400">MEV Bot View (On-Chain)</h3>
                <div className="space-y-2 text-xs">
                  <div className="bg-black/30 rounded p-2">
                    <span className="text-gray-500">Intent hash: </span>
                    <span className="text-gray-300 font-mono break-all">
                      {intentHash
                        ? `${intentHash.slice(0, 14)}...${intentHash.slice(-8)}`
                        : "0x???...??? (nothing yet)"}
                    </span>
                  </div>
                  <div className="bg-black/30 rounded p-2">
                    <span className="text-gray-500">Batch root: </span>
                    <span className="text-gray-300 font-mono">
                      {flowStep === "queued"
                        ? "0x (pending batch execution)"
                        : "0x???...??? (not batched yet)"}
                    </span>
                  </div>
                  <div className="bg-black/30 rounded p-2">
                    <span className="text-gray-500">Token pair: </span>
                    <span className="text-red-400">hidden</span>
                  </div>
                  <div className="bg-black/30 rounded p-2">
                    <span className="text-gray-500">Amount: </span>
                    <span className="text-red-400">hidden</span>
                  </div>
                  <div className="bg-black/30 rounded p-2">
                    <span className="text-gray-500">Tick range: </span>
                    <span className="text-red-400">hidden</span>
                  </div>
                  <p className="text-red-400/70 mt-1">
                    MEV bots cannot front-run your LP position
                  </p>
                </div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
