import {Img} from 'remotion';
import {Gauge, List} from 'lucide-react';
import cursorLogo from '../../../mac/Resources/BrandIcons/cursor.svg';
import openaiLogo from '../../../mac/Resources/BrandIcons/openai.svg';
import {ProviderLogo} from '../components/IslandChrome';
import type {Provider} from '../content';
import {tokenAbbreviation} from '../content';
import {ISLAND, alpha, color} from '../theme';
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

export type QuotaWindow = {
  id: string;
  kind: 'fiveHours' | 'weekly' | 'budget' | 'model';
  name?: string;
  remainingPercent?: number;
  remaining?: number;
  limit?: number;
  unit: 'percent' | 'usd';
  resetsAt: string;
  durationSeconds?: number;
};

export type AccountBalance = {
  provider: 'claude' | 'codex' | 'cursor';
  title: string;
  windows: readonly QuotaWindow[];
};

// Fictional observations use the native quota-window schema and preserve each provider's unit.
export const aiAccountBalances: readonly AccountBalance[] = [
  {provider: 'claude', title: 'Claude', windows: [
    {id: 'five_hour', kind: 'fiveHours', remainingPercent: 72, unit: 'percent', resetsAt: '2026-11-11T13:00:00+08:00', durationSeconds: 18_000},
    {id: 'seven_day', kind: 'weekly', remainingPercent: 44, unit: 'percent', resetsAt: '2026-11-15T09:00:00+08:00', durationSeconds: 604_800},
  ]},
  {provider: 'codex', title: 'Codex', windows: [
    {id: 'five_hour', kind: 'fiveHours', remainingPercent: 68, unit: 'percent', resetsAt: '2026-11-11T14:10:00+08:00', durationSeconds: 18_000},
    {id: 'seven_day', kind: 'weekly', remainingPercent: 31, unit: 'percent', resetsAt: '2026-11-16T09:00:00+08:00', durationSeconds: 604_800},
  ]},
  {provider: 'cursor', title: 'Cursor', windows: [
    {id: 'plan', kind: 'budget', remainingPercent: 68.5, remaining: 68.5, limit: 100, unit: 'usd', resetsAt: '2026-12-01T00:00:00+08:00'},
  ]},
];

export const quotaSeverity = (window: QuotaWindow) => window.remainingPercent !== undefined
  ? window.remainingPercent === 0 ? 'exhausted' : window.remainingPercent <= 10 ? 'critical' : window.remainingPercent <= 20 ? 'warning' : 'normal'
  : window.remaining === 0 ? 'exhausted' : 'normal';

export const quotaFraction = (window: QuotaWindow): number | undefined => window.remainingPercent !== undefined ? window.remainingPercent / 100
  : window.remaining !== undefined && window.limit !== undefined && window.limit > 0 ? window.remaining / window.limit : undefined;

export const quotaValue = (window: QuotaWindow) => window.unit === 'usd' && window.remaining !== undefined ? `$${window.remaining}`
  : window.remainingPercent !== undefined ? `${window.remainingPercent}%` : '—';

const quotaColor = (window: QuotaWindow) => ({normal: color.green, warning: color.yellow, critical: color.red, exhausted: '#8E8E93'})[quotaSeverity(window)];
const quotaLabel = (window: QuotaWindow) => window.name ?? ({fiveHours: '5h', weekly: '7d', budget: 'Available budget', model: 'Model quota'})[window.kind];

export const aiBalancesAt = (lowQuota: boolean): readonly AccountBalance[] => aiAccountBalances.map((balance) => balance.provider === 'claude' && lowQuota
  ? {...balance, windows: balance.windows.map((window) => window.kind === 'fiveHours' ? {...window, remainingPercent: 8} : window)} : balance);

const modelTokens = (tokens: number) => `${tokens / 1_000_000} M`;
const providerTitle = {claude: 'Claude', codex: 'ChatGPT', gemini: 'Gemini'} as const;

export const DailyModelUsageList = ({width = RIGHT_WIDTH}: {width?: number}) => (
  <section className="flex shrink-0 flex-col gap-3" data-feature="ai.usage.models" data-usage-date="2026-11-11" data-token-total={aiModelTokenTotal} style={{width}}>
    <div className="flex h-[14px] items-center gap-[5px] text-[11px] font-semibold">
      <List size={12} strokeWidth={2.4} />
      <span>Daily model usage</span>
    </div>
    <div className="flex flex-col gap-[7px]">
      <div className="tabular flex h-[14px] items-center justify-between font-mono text-[10px] font-semibold text-label-2">
        <span>Nov 11, 2026</span>
        <span>{tokenAbbreviation(aiModelTokenTotal)} Token</span>
      </div>
      {aiModelUsage.map((usage) => (
        <div key={`${usage.provider}:${usage.model}`} className="flex flex-col gap-[5px]" data-model={usage.model} data-token-total={usage.inputTokens + usage.outputTokens}>
          <div className="flex h-[14px] items-center gap-[5px] text-[11px] font-semibold">
            {usage.provider === 'codex' ? <Img src={openaiLogo} style={{width: 13, height: 13, objectFit: 'contain'}} /> : <ProviderLogo provider={usage.provider} size={13} />}
            <span>{providerTitle[usage.provider]}</span>
          </div>
          <div className="flex h-[14px] items-baseline justify-between gap-[6px] text-[10px] font-medium">
            <span>{usage.model}</span>
            <span className="tabular font-mono text-[9px] text-label-2">Input {modelTokens(usage.inputTokens)} · Output {modelTokens(usage.outputTokens)}</span>
          </div>
        </div>
      ))}
    </div>
  </section>
);

export const AccountQuotaRing = ({balance, outer, inner, diameter}: {balance: AccountBalance; outer?: QuotaWindow; inner?: QuotaWindow; diameter: number}) => {
  const strokeWidth = diameter * 4 / 42;
  const arc = (window: QuotaWindow, size: number) => {
    const radius = size / 2 - strokeWidth / 2 - 0.5;
    const circumference = Math.PI * 2 * radius;
    const fraction = quotaFraction(window);
    const tint = quotaColor(window);
    return <g key={window.id} data-quota-window={window.id} data-unit={window.unit} data-severity={quotaSeverity(window)} data-fraction={fraction}>
      <circle cx={diameter / 2} cy={diameter / 2} r={radius} fill="none" stroke={alpha(tint, 0.2)} strokeWidth={strokeWidth} />
      {fraction !== undefined && fraction > 0 ? <circle cx={diameter / 2} cy={diameter / 2} r={radius} fill="none" stroke={tint} strokeWidth={strokeWidth} strokeLinecap="round" strokeDasharray={`${circumference * fraction} ${circumference}`} transform={`rotate(-90 ${diameter / 2} ${diameter / 2})`} /> : null}
    </g>;
  };
  const logoSize = diameter * (inner ? 0.36 : 0.48);
  return <div className="relative shrink-0" style={{width: diameter, height: diameter}}>
    <svg width={diameter} height={diameter}>{outer ? arc(outer, diameter) : null}{inner ? arc(inner, diameter * 0.7) : null}</svg>
    <div className="absolute inset-0 flex items-center justify-center">
      {balance.provider === 'cursor' ? <Img src={cursorLogo} style={{width: logoSize, height: logoSize}} /> : <ProviderLogo provider={balance.provider} size={logoSize} />}
    </div>
  </div>;
};

const QuotaDetails = ({window}: {window: QuotaWindow}) => <div className="min-w-0 flex-1 text-[10px] leading-[16px]">
  <span className="text-label-2">{quotaLabel(window)} </span>
  <span className="font-rounded tabular text-[12px] font-semibold" style={{color: quotaColor(window)}}>{quotaValue(window)}</span>
  <span className="text-[9px] text-label-2"> · {window.resetsAt.slice(5, 10).replace('-', '/')} {window.resetsAt.slice(11, 16)} resets</span>
</div>;

export const AccountBalanceCard = ({balance}: {balance: AccountBalance}) => {
  const fiveHour = balance.windows.find((window) => window.kind === 'fiveHours' && !window.id.startsWith('additional:'));
  const weekly = balance.windows.find((window) => window.kind === 'weekly' && window.name === undefined);
  return (
    <div
      className="flex min-w-0 flex-col gap-[10px] p-3"
      data-feature={balance.provider === 'cursor' ? 'ai.budget.cursor' : `ai.quota.${balance.provider}`}
      data-account={balance.provider}
      style={{background: color.fillCard, border: `1px solid ${color.strokeCard}`, borderRadius: ISLAND.moduleInnerRadius}}
    >
      <div className="text-[11px] leading-[14px] font-semibold">{balance.title}</div>
      {fiveHour || weekly ? <div className="flex items-center gap-2">
        <AccountQuotaRing balance={balance} outer={weekly} inner={fiveHour} diameter={52} />
        <div className="flex min-w-0 flex-1 flex-col gap-2">{fiveHour ? <QuotaDetails window={fiveHour} /> : null}{weekly ? <QuotaDetails window={weekly} /> : null}</div>
      </div> : null}
      {balance.windows.filter((window) => window !== fiveHour && window !== weekly).map((window) => <div key={window.id} className="flex items-center gap-2">
        <AccountQuotaRing balance={balance} outer={window} diameter={42} />
        <QuotaDetails window={window} />
      </div>)}
    </div>
  );
};

export const AIAnalyticsModule = ({lowQuota = false}: {lowQuota?: boolean}) => (
  <section className="flex w-full flex-col gap-3" data-feature="ai.quota" data-low-quota={lowQuota}>
    <div className="flex h-[14px] shrink-0 items-center gap-[5px] text-[11px] font-semibold">
      <Gauge size={12} strokeWidth={2.4} />
      <span>Account quota remaining</span>
    </div>
    <div className="grid grid-cols-3 gap-3">
      {aiBalancesAt(lowQuota).map((balance) => <AccountBalanceCard key={balance.provider} balance={balance} />)}
    </div>
  </section>
);
