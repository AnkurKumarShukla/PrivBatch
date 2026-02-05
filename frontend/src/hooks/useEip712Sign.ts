"use client";

import { useWalletClient } from "wagmi";
import { CHAIN_ID } from "@/config/contracts";

const EIP712_DOMAIN = {
  name: "PrivBatch",
  version: "1",
  chainId: CHAIN_ID,
} as const;

const EIP712_TYPES = {
  PoolKey: [
    { name: "currency0", type: "address" },
    { name: "currency1", type: "address" },
    { name: "fee", type: "uint24" },
    { name: "tickSpacing", type: "int24" },
    { name: "hooks", type: "address" },
  ],
  LPIntent: [
    { name: "user", type: "address" },
    { name: "pool", type: "PoolKey" },
    { name: "tickLower", type: "int24" },
    { name: "tickUpper", type: "int24" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

export interface IntentParams {
  user: `0x${string}`;
  pool: {
    currency0: `0x${string}`;
    currency1: `0x${string}`;
    fee: number;
    tickSpacing: number;
    hooks: `0x${string}`;
  };
  tickLower: number;
  tickUpper: number;
  amount: bigint;
  nonce: bigint;
  deadline: bigint;
}

export function useEip712Sign() {
  const { data: walletClient } = useWalletClient();

  async function signIntent(
    intent: IntentParams,
    hookAddress: `0x${string}`
  ): Promise<`0x${string}`> {
    if (!walletClient) throw new Error("Wallet not connected");

    const domain = {
      ...EIP712_DOMAIN,
      verifyingContract: hookAddress,
    };

    const message = {
      user: intent.user,
      pool: {
        currency0: intent.pool.currency0,
        currency1: intent.pool.currency1,
        fee: intent.pool.fee,
        tickSpacing: intent.pool.tickSpacing,
        hooks: intent.pool.hooks,
      },
      tickLower: intent.tickLower,
      tickUpper: intent.tickUpper,
      amount: intent.amount,
      nonce: intent.nonce,
      deadline: intent.deadline,
    };

    const signature = await walletClient.signTypedData({
      domain,
      types: EIP712_TYPES,
      primaryType: "LPIntent",
      message,
    });

    return signature;
  }

  return { signIntent, isReady: !!walletClient };
}
