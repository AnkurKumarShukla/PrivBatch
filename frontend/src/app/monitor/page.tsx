"use client";

import { usePendingIntents, useBatchHistory } from "@/hooks/useAgentApi";

function ensure0x(hash: string) {
  if (!hash) return "";
  return hash.startsWith("0x") ? hash : `0x${hash}`;
}

function truncateAddress(addr: string) {
  if (!addr) return "";
  return `${addr.slice(0, 8)}...${addr.slice(-4)}`;
}

function truncateHash(hash: string) {
  if (!hash) return "";
  const h = ensure0x(hash);
  return `${h.slice(0, 10)}...${h.slice(-6)}`;
}

function formatDeadline(deadline: number) {
  const now = Math.floor(Date.now() / 1000);
  const diff = deadline - now;
  if (diff <= 0) return "Expired";
  const mins = Math.floor(diff / 60);
  const secs = diff % 60;
  return `${mins}m ${secs}s`;
}

function formatTimestamp(ts: number) {
  return new Date(ts * 1000).toLocaleString();
}

export default function MonitorPage() {
  const { data: pending } = usePendingIntents();
  const { data: history } = useBatchHistory();

  return (
    <div className="space-y-10">
      <div>
        <h1 className="text-2xl font-bold">Batch Monitor</h1>
        <p className="mt-1 text-gray-400">
          Live view of pending intents and executed batches
        </p>
      </div>

      {/* Pending Intents */}
      <div>
        <div className="flex items-center gap-3 mb-4">
          <h2 className="text-lg font-semibold">Pending Intents</h2>
          <span className="text-xs px-2 py-0.5 rounded bg-violet-500/20 text-violet-300 border border-violet-500/30">
            {pending?.length ?? 0} queued
          </span>
          <span className="text-xs text-gray-500">Polls every 5s</span>
        </div>

        <div className="overflow-x-auto rounded-xl border border-white/10">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-white/10 text-gray-400">
                <th className="px-4 py-3 text-left">User</th>
                <th className="px-4 py-3 text-right">Tick Lower</th>
                <th className="px-4 py-3 text-right">Tick Upper</th>
                <th className="px-4 py-3 text-right">Amount</th>
                <th className="px-4 py-3 text-right">Nonce</th>
                <th className="px-4 py-3 text-right">Deadline</th>
              </tr>
            </thead>
            <tbody>
              {(!pending || pending.length === 0) && (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-gray-500">
                    No pending intents
                  </td>
                </tr>
              )}
              {pending?.map((intent, i) => (
                <tr
                  key={i}
                  className="border-b border-white/5 hover:bg-white/5"
                >
                  <td className="px-4 py-3 font-mono text-xs">
                    {truncateAddress(intent.user)}
                  </td>
                  <td className="px-4 py-3 text-right font-mono">
                    {intent.tick_lower}
                  </td>
                  <td className="px-4 py-3 text-right font-mono">
                    {intent.tick_upper}
                  </td>
                  <td className="px-4 py-3 text-right font-mono text-xs">
                    {BigInt(intent.amount).toLocaleString()}
                  </td>
                  <td className="px-4 py-3 text-right">{intent.nonce}</td>
                  <td className="px-4 py-3 text-right text-gray-400">
                    {formatDeadline(intent.deadline)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Batch History */}
      <div>
        <h2 className="text-lg font-semibold mb-4">Batch History</h2>
        <div className="overflow-x-auto rounded-xl border border-white/10">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-white/10 text-gray-400">
                <th className="px-4 py-3 text-left">Batch Root</th>
                <th className="px-4 py-3 text-left">Transaction</th>
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
                <tr
                  key={i}
                  className="border-b border-white/5 hover:bg-white/5"
                >
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
