// Contract addresses on Sepolia
// Update these after running setup-pool.sh
export const CONTRACTS = {
  POOL_MANAGER: "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543" as `0x${string}`,
  POSITION_MANAGER: "0x429ba70129df741b2ca2a85bc3a2a3328e5c09b4" as `0x${string}`,
  PERMIT2: "0x000000000022D473030F116dDEE9F6B43aC78BA3" as `0x${string}`,
  HOOK: "0x08ee384c6AbA8926657E2f10dFeeE53a91Aa4e00" as `0x${string}`,
  EXECUTOR: "0x79dcDc67710C70be8Ef52e67C8295Fd0dA8A5722" as `0x${string}`,
  COMMIT: "0x5f4E461b847fCB857639D1Ec7277485286b7613F" as `0x${string}`,
  // Tokens - update after running setup-pool.sh
  TOKEN_A: "0x486C739A8A219026B6AB13aFf557c827Db4E267e" as `0x${string}`,
  TOKEN_B: "0xfB6458d361Bd6F428d8568b0A2828603e89f1c4E" as `0x${string}`,
} as const;

export const AGENT_API = process.env.NEXT_PUBLIC_AGENT_API || "http://localhost:8000";

export const CHAIN_ID = 11155111; // Sepolia

export const POOL_FEE = 3000;
export const TICK_SPACING = 60;
