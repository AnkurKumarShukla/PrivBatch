"use client";

import { useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseEther, formatEther } from "viem";
import { MockERC20ABI } from "@/config/abis";
import { useAgentConfig } from "@/hooks/useAgentApi";

function TokenCard({
  label,
  address,
  userAddress,
}: {
  label: string;
  address: `0x${string}`;
  userAddress: `0x${string}` | undefined;
}) {
  const [amount, setAmount] = useState("1000");
  const { writeContract, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const { data: name } = useReadContract({
    address,
    abi: MockERC20ABI,
    functionName: "name",
  });

  const { data: symbol } = useReadContract({
    address,
    abi: MockERC20ABI,
    functionName: "symbol",
  });

  const { data: balance, refetch: refetchBalance } = useReadContract({
    address,
    abi: MockERC20ABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress },
  });

  const handleMint = () => {
    if (!userAddress || !amount) return;
    reset();
    writeContract({
      address,
      abi: MockERC20ABI,
      functionName: "mint",
      args: [userAddress, parseEther(amount)],
    });
  };

  // Refetch balance after confirmation
  if (isSuccess) {
    refetchBalance();
  }

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 space-y-4">
      <div>
        <h3 className="text-lg font-semibold">
          {label}: {(name as string) ?? "..."} ({(symbol as string) ?? "..."})
        </h3>
        <p className="text-xs font-mono text-gray-500 mt-1">{address}</p>
      </div>

      <div className="flex items-center justify-between">
        <span className="text-sm text-gray-400">Your Balance</span>
        <span className="text-xl font-semibold">
          {balance !== undefined
            ? parseFloat(formatEther(balance as bigint)).toLocaleString()
            : "---"}
        </span>
      </div>

      <div className="flex gap-3">
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="Amount"
          className="flex-1 rounded-lg bg-white/10 border border-white/10 px-4 py-2 text-white placeholder-gray-500 focus:outline-none focus:border-violet-500"
        />
        <button
          onClick={handleMint}
          disabled={isPending || isConfirming || !userAddress}
          className="px-6 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white font-medium transition-colors"
        >
          {isPending
            ? "Confirm..."
            : isConfirming
            ? "Minting..."
            : `Mint ${(symbol as string) ?? ""}`}
        </button>
      </div>

      {isSuccess && (
        <p className="text-sm text-green-400">
          Minted {amount} {(symbol as string) ?? ""} successfully!
        </p>
      )}
    </div>
  );
}

export default function MintPage() {
  const { address } = useAccount();
  const { data: config } = useAgentConfig();

  const tokenA = config?.token_a as `0x${string}` | undefined;
  const tokenB = config?.token_b as `0x${string}` | undefined;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">Mint Test Tokens</h1>
        <p className="mt-1 text-gray-400">
          Free testnet tokens for the PrivBatch demo
        </p>
      </div>

      {!address && (
        <div className="rounded-xl border border-yellow-500/30 bg-yellow-500/10 p-6 text-yellow-200">
          Connect your wallet to mint tokens
        </div>
      )}

      {address && !tokenA && (
        <div className="rounded-xl border border-yellow-500/30 bg-yellow-500/10 p-6 text-yellow-200">
          Token addresses not configured. Make sure the agent is running and
          TOKEN_A/TOKEN_B are set.
        </div>
      )}

      {address && tokenA && tokenB && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <TokenCard label="Token A" address={tokenA} userAddress={address} />
          <TokenCard label="Token B" address={tokenB} userAddress={address} />
        </div>
      )}
    </div>
  );
}
