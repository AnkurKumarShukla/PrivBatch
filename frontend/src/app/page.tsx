"use client";

import { StatCard } from "@/components/StatCard";
import {
  useBatchStatus,
  useBatchHistory,
  useAdaptiveStats,
} from "@/hooks/useAgentApi";

function ensure0x(hash: string) {
  if (!hash) return "";
  return hash.startsWith("0x") ? hash : `0x${hash}`;
}

function truncateHash(hash: string) {
  if (!hash) return "";
  const h = ensure0x(hash);
  return `${h.slice(0, 10)}...${h.slice(-6)}`;
}

function formatTimestamp(ts: number) {
  return new Date(ts * 1000).toLocaleString();
}

export default function Dashboard() {
  const { data: status } = useBatchStatus();
  const { data: history } = useBatchHistory();
  const { data: adaptive } = useAdaptiveStats();

  const totalGasSaved = adaptive?.total_gas
    ? Math.round(adaptive.total_gas * 0.15)
    : 0;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">Dashboard</h1>
        <p className="mt-1 text-gray-400">
          PrivBatch Coordinator system overview
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          label="Pending Intents"
          value={status?.pending_intents ?? 0}
          sub="Awaiting batch"
        />
        <StatCard
          label="Batches Executed"
          value={status?.batches_executed ?? 0}
          sub="Total on-chain batches"
        />
        <StatCard
          label="Gas Saved (est.)"
          value={totalGasSaved.toLocaleString()}
          sub="vs. individual txs"
        />
        <StatCard
          label="k Multiplier"
          value={adaptive?.k_multiplier?.toFixed(4) ?? "2.0000"}
          sub="Adaptive range width"
        />
      </div>

      <div>
        <h2 className="text-lg font-semibold mb-4">Recent Batch History</h2>
        <div className="overflow-x-auto rounded-xl border border-white/10">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-white/10 text-gray-400">
                <th className="px-4 py-3 text-left">Batch Root</th>
                <th className="px-4 py-3 text-left">Tx Hash</th>
                <th className="px-4 py-3 text-right">Intents</th>
                <th className="px-4 py-3 text-right">Time</th>
              </tr>
            </thead>
            <tbody>
              {(!history || history.length === 0) && (
                <tr>
                  <td colSpan={4} className="px-4 py-8 text-center text-gray-500">
                    No batches executed yet
                  </td>
                </tr>
              )}
              {history?.map((batch, i) => (
                <tr key={i} className="border-b border-white/5 hover:bg-white/5">
                  <td className="px-4 py-3 font-mono text-xs">
                    {truncateHash(batch.root)}
                  </td>
                  <td className="px-4 py-3 font-mono text-xs">
                    <a
                      href={`https://sepolia.etherscan.io/tx/${ensure0x(batch.tx_hash)}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-violet-400 hover:text-violet-300 underline"
                    >
                      {truncateHash(batch.tx_hash)}
                    </a>
                  </td>
                  <td className="px-4 py-3 text-right">{batch.intent_count}</td>
                  <td className="px-4 py-3 text-right text-gray-400">
                    {formatTimestamp(batch.timestamp)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
