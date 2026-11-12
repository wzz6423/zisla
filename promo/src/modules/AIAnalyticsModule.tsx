import {ChartColumn, Gauge, TriangleAlert} from 'lucide-react';
import {ProviderLogo} from '../components/IslandChrome';
import type {Provider} from '../content';
import {brands, tokenAbbreviation} from '../content';
import {ISLAND, MODULE_HEIGHT, color} from '../theme';
import {RIGHT_WIDTH} from './AIModule';

type ModelUsage = {
  provider: Provider;
  model: string;
  inputTokens: number;
  outputTokens: number;
};

// These fictional samples share the same selected day as the film's trend and heatmap.
export const aiModelUsage: readonly ModelUsage[] = [
  {provider: 'claude', model: 'Sonnet 4.5', inputTokens: 156_000, outputTokens: 78_000},
  {provider: 'codex', model: 'GPT-5.1 Codex', inputTokens: 148_000, outputTokens: 64_000},
  {provider: 'gemini', model: 'Gemini 2.5 Pro', inputTokens: 107_000, outputTokens: 48_000},
];

export const aiModelTokenTotal = aiModelUsage.reduce((total, usage) => total + usage.inputTokens + usage.outputTokens, 0);

type GatewayBalance = {
  provider: Provider;
  name: string;
  available: number;
  used: number;
  currency: string;
  checkedAt: string;
  minimumBalance: number;
};

// Monetary values represent fictional gateway credits, rather than provider subscription quotas.
export const aiGatewayBalances: readonly GatewayBalance[] = [
  {provider: 'claude', name: 'Claude gateway', available: 72.4, used: 27.6, currency: 'USD', checkedAt: '2026-11-11T09:41:00+08:00', minimumBalance: 10},
  {provider: 'codex', name: 'Codex gateway', available: 68.5, used: 31.5, currency: 'USD', checkedAt: '2026-11-11T09:41:00+08:00', minimumBalance: 10},
  {provider: 'gemini', name: 'Backup gateway', available: 8.6, used: 41.4, currency: 'USD', checkedAt: '2026-11-11T09:41:00+08:00', minimumBalance: 10},
];

const DailyModelUsageList = () => (
  <section className="flex shrink-0 flex-col gap-2" style={{width: RIGHT_WIDTH}}>
    <div className="flex h-[14px] items-center gap-[5px] text-[11px] font-semibold">
      <ChartColumn size={12} strokeWidth={2.4} />
      <span>Daily model usage</span>
    </div>
    <div className="tabular flex h-[14px] items-center justify-between font-mono text-[10px] text-label-2">
      <span>Nov 11, 2026</span>
      <span>{tokenAbbreviation(aiModelTokenTotal)} Token</span>
    </div>
    <div className="flex flex-col gap-2">
      {aiModelUsage.map((usage) => (
        <div key={`${usage.provider}:${usage.model}`} className="flex flex-col gap-[2px]">
          <div className="flex h-[14px] items-center gap-[5px] text-[10px] font-semibold">
            <ProviderLogo provider={usage.provider} size={13} />
            <span>{brands[usage.provider].name}</span>
          </div>
          <div className="flex h-[14px] items-center justify-between gap-[6px] text-[11px] font-medium">
            <span>{usage.model}</span>
            <span className="tabular font-mono font-semibold">{tokenAbbreviation(usage.inputTokens + usage.outputTokens)}</span>
          </div>
          <div className="tabular flex h-[10px] items-center justify-between font-mono text-[9px] text-label-2">
            <span>Input {tokenAbbreviation(usage.inputTokens)}</span>
            <span>Output {tokenAbbreviation(usage.outputTokens)}</span>
          </div>
        </div>
      ))}
    </div>
  </section>
);

const AccountBalanceCard = ({balance}: {balance: GatewayBalance}) => {
  const lowBalance = balance.available < balance.minimumBalance;
  return (
    <div
      className="flex min-w-0 flex-col gap-[5px] p-[10px]"
      style={{background: color.fillCard, border: `1px solid ${color.strokeCard}`, borderRadius: ISLAND.moduleInnerRadius}}
    >
      <div className="flex h-[14px] items-center gap-[5px] text-[11px] font-semibold">
        <ProviderLogo provider={balance.provider} size={13} />
        <span>{balance.name}</span>
      </div>
      <div className="flex h-[24px] items-baseline gap-[5px]">
        <span className="text-[9px] text-label-2">Available</span>
        <span className="font-rounded tabular text-[22px] font-semibold" style={{color: lowBalance ? color.yellow : color.green}}>
          {balance.available.toFixed(2)}
        </span>
        <span className="text-[9px] text-label-2">{balance.currency}</span>
      </div>
      <div className="tabular h-[11px] font-mono text-[10px] text-label-2">
        Used {balance.used.toFixed(2)} {balance.currency}
      </div>
      <div className="flex h-[13px] items-center gap-[4px] text-[9px] font-medium" style={{color: color.yellow}}>
        {lowBalance ? (
          <>
            <TriangleAlert size={11} strokeWidth={2.2} />
            <span>Low balance · min {balance.minimumBalance.toFixed(2)} {balance.currency}</span>
          </>
        ) : null}
      </div>
      <div className="mt-auto h-[11px] font-mono text-[9px] text-label-2">Checked {balance.checkedAt.slice(11, 16)}</div>
    </div>
  );
};

export const AIAnalyticsModule = () => (
  <div className="flex flex-col items-end gap-4" style={{height: MODULE_HEIGHT.ai}}>
    <DailyModelUsageList />
    <section className="flex min-h-0 w-full flex-1 flex-col gap-2">
      <div className="flex h-[14px] shrink-0 items-center gap-[5px] text-[11px] font-semibold">
        <Gauge size={12} strokeWidth={2.4} />
        <span>Account balance</span>
      </div>
      <div className="grid min-h-0 flex-1 grid-cols-3 gap-3">
        {aiGatewayBalances.map((balance) => <AccountBalanceCard key={balance.name} balance={balance} />)}
      </div>
    </section>
  </div>
);
