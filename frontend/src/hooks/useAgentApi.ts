"use client";

import { useQuery } from "@tanstack/react-query";
import { AGENT_API } from "@/config/contracts";

async function fetchJson<T>(path: string): Promise<T> {
  const res = await fetch(`${AGENT_API}${path}`);
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export interface AgentConfig {
  chain_id: number;
  hook_address: string;
  executor_address: string;
  commit_address: string;
  pool_manager: string;
  position_manager: string;
  token_a: string;
  token_b: string;
  pool_key: {
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    hooks: string;
  };
}

export interface BatchStatusResponse {
  pending_intents: number;
  last_batch_root: string | null;
  last_batch_tx: string | null;
  batches_executed: number;
}

export interface PendingIntent {
  user: string;
  tick_lower: number;
  tick_upper: number;
  amount: string;
  nonce: number;
  deadline: number;
}

export interface BatchHistoryEntry {
  root: string;
  tx_hash: string;
  intent_count: number;
  timestamp: number;
}

export interface AdaptiveStats {
  k_multiplier: number;
  total_batches: number;
  recent_avg_il: number;
  total_gas: number;
}

export interface SuggestedRange {
  tick_lower: number;
  tick_upper: number;
  k_multiplier: number;
  price: number;
  volatility: number;
}

export function useAgentConfig() {
  return useQuery<AgentConfig>({
    queryKey: ["agent-config"],
    queryFn: () => fetchJson("/config"),
    staleTime: 60_000,
  });
}

export function useBatchStatus(refetchInterval = 5000) {
  return useQuery<BatchStatusResponse>({
    queryKey: ["batch-status"],
    queryFn: () => fetchJson("/batch/status"),
    refetchInterval,
  });
}

export function usePendingIntents(refetchInterval = 5000) {
  return useQuery<PendingIntent[]>({
    queryKey: ["pending-intents"],
    queryFn: () => fetchJson("/intents/pending"),
    refetchInterval,
  });
}

export function useBatchHistory(refetchInterval = 5000) {
  return useQuery<BatchHistoryEntry[]>({
    queryKey: ["batch-history"],
    queryFn: () => fetchJson("/batch/history"),
    refetchInterval,
  });
}

export function useAdaptiveStats(refetchInterval = 10000) {
  return useQuery<AdaptiveStats>({
    queryKey: ["adaptive-stats"],
    queryFn: () => fetchJson("/adaptive/stats"),
    refetchInterval,
  });
}

export function useSuggestedRange(price: number, volatility: number) {
  return useQuery<SuggestedRange>({
    queryKey: ["suggested-range", price, volatility],
    queryFn: () =>
      fetchJson(`/optimizer/suggest?price=${price}&volatility=${volatility}`),
    enabled: price > 0 && volatility > 0,
  });
}

export async function submitIntent(intent: Record<string, unknown>) {
  const res = await fetch(`${AGENT_API}/intents`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(intent),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: "Unknown error" }));
    throw new Error(err.detail || `API error: ${res.status}`);
  }
  return res.json();
}
