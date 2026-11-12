import {useId} from 'react';
import type {CSSProperties, ReactNode} from 'react';
import type {LucideIcon} from 'lucide-react';
import {ChartLine, Cpu} from 'lucide-react';
import {Hairline, ProgressTrack} from '../components/Glass';
import {ProviderLogo} from '../components/IslandChrome';
import type {AiTask} from '../content';
import {brands, heatmap, tokenAbbreviation, tokenTrend} from '../content';
import {alpha, clamp01, color, white} from '../theme';

export type AiRow = {
  task: AiTask;
  progress?: number;
  // 已运行秒数
  run: number;
  // 0–1，任务刚出现时整行从 0 高度长出来
  enter?: number;
};

type AIModuleProps = {
  frame: number;
  rows: readonly AiRow[];
  // 0–1，趋势线从左向右画出
  trend: number;
  todayTokens: number;
  // 0–1，热力图按列浮现
  heat: number;
  todayLevel: number;
  // 0–1，今天那一格的选中描边与信息行
  selection: number;
};

const pad = (value: number): string => String(value).padStart(2, '0');

const runText = (seconds: number): string => {
  const whole = Math.max(0, Math.floor(seconds));
  return `${pad(Math.floor(whole / 3600))}:${pad(Math.floor((whole % 3600) / 60))}:${pad(whole % 60)}`;
};

const SectionTitle = ({icon: Icon, label, size, trailing}: {icon: LucideIcon; label: string; size: number; trailing?: ReactNode}) => (
  <div className="flex h-[14px] shrink-0 items-center gap-[5px] font-semibold" style={{fontSize: size}}>
    <Icon size={size + 1} strokeWidth={2.4} />
    <span>{label}</span>
    <div className="flex-1" />
    {trailing}
  </div>
);

const ThinkingOrb = ({frame}: {frame: number}) => {
  const pulse = 0.5 + 0.5 * Math.sin(frame * 0.16);
  const size = 9 + pulse * 3;
  return (
    <div className="flex h-5 w-5 shrink-0 items-center justify-center">
      <div
        className="rounded-full"
        style={{
          width: size,
          height: size,
          background: 'radial-gradient(circle at 40% 35%, #fff, rgba(255,255,255,0.55) 60%, rgba(255,255,255,0) 100%)',
          boxShadow: `0 0 ${5 + pulse * 5}px ${white(0.45 + pulse * 0.3)}`,
        }}
      />
    </div>
  );
};

const TaskRow = ({row, frame}: {row: AiRow; frame: number}) => {
  const enter = clamp01(row.enter ?? 1);
  const brand = brands[row.task.provider];
  return (
    <div className="shrink-0 overflow-hidden" style={{height: 54 * enter, opacity: enter}}>
      <div className="flex h-[54px] items-center gap-[9px] px-[2px]">
        <ProviderLogo provider={row.task.provider} size={20} />
        <div className="flex min-w-0 flex-1 flex-col gap-[2px]">
          <div className="flex items-center gap-2">
            <span className="truncate text-[11px] leading-[14px] font-semibold">{row.task.title}</span>
            <div className="flex-1" />
            <span className="font-mono text-[9px] font-bold text-label-2">{brand.name}</span>
          </div>
          <div className="text-[9px] leading-[11px] text-label-2">
            {row.task.detail} · {row.task.effort}
          </div>
          <div className="flex h-5 items-center gap-2">
            <span className="tabular truncate font-mono text-[9px] text-label-2">
              Start {row.task.start} · PID {row.task.pid} · Run {runText(row.run)}
            </span>
            <div className="flex-1" />
            {row.progress === undefined ? (
              <ThinkingOrb frame={frame} />
            ) : (
              <ProgressTrack value={row.progress} tint={brand.color} width={32} />
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

type Point = readonly [number, number];

// 与 Swift Charts 的 .monotone 插值同一类曲线：切线取相邻斜率的调和平均，保证不出现过冲
const monotonePath = (points: readonly Point[]): string => {
  const first = points[0];
  if (!first || points.length < 2) {
    return '';
  }
  const slopes: number[] = [];
  for (let index = 0; index < points.length - 1; index++) {
    const [x0, y0] = points[index] as Point;
    const [x1, y1] = points[index + 1] as Point;
    slopes.push((y1 - y0) / (x1 - x0));
  }
  const tangents = points.map((_, index) => {
    const before = slopes[index - 1];
    const after = slopes[index];
    if (before === undefined || after === undefined) {
      return before ?? after ?? 0;
    }
    return before * after <= 0 ? 0 : (2 * before * after) / (before + after);
  });
  let path = `M${first[0]},${first[1]}`;
  for (let index = 0; index < points.length - 1; index++) {
    const [x0, y0] = points[index] as Point;
    const [x1, y1] = points[index + 1] as Point;
    const third = (x1 - x0) / 3;
    path += ` C${x0 + third},${y0 + (tangents[index] ?? 0) * third} ${x1 - third},${y1 - (tangents[index + 1] ?? 0) * third} ${x1},${y1}`;
  }
  return path;
};

export const RIGHT_WIDTH = 377.5;
const CHART = {height: 128, left: 30, right: 14, top: 6, bottom: 22};
const CHART_MAX = 1_000_000;
const TICKS = [0, 250_000, 500_000, 750_000, 1_000_000];

const TrendChart = ({reveal, todayTokens}: {reveal: number; todayTokens: number}) => {
  const id = useId().replace(/[^a-zA-Z0-9]/g, '');
  const plotWidth = RIGHT_WIDTH - CHART.left - CHART.right;
  const plotHeight = CHART.height - CHART.top - CHART.bottom;
  const baseline = CHART.top + plotHeight;
  const yFor = (tokens: number): number => CHART.top + plotHeight * (1 - tokens / CHART_MAX);
  const count = tokenTrend.points.length;
  const points: Point[] = tokenTrend.points.map((point, index) => [
    CHART.left + (plotWidth * index) / (count - 1),
    yFor(index === count - 1 ? todayTokens : point.tokens),
  ]);
  const line = monotonePath(points);
  const last = points[count - 1] ?? [0, 0];
  const labelStyle: CSSProperties = {fontSize: 9, fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace', fill: color.secondary};
  return (
    <svg width={RIGHT_WIDTH} height={CHART.height} className="shrink-0">
      <defs>
        <linearGradient id={`${id}-fill`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color.blue} stopOpacity={0.28} />
          <stop offset="1" stopColor={color.blue} stopOpacity={0.02} />
        </linearGradient>
        <clipPath id={`${id}-clip`}>
          <rect x={CHART.left - 4} y={0} width={(plotWidth + 8) * clamp01(reveal)} height={CHART.height} />
        </clipPath>
      </defs>
      {TICKS.map((tick) => (
        <g key={tick}>
          <line x1={CHART.left} x2={RIGHT_WIDTH - CHART.right} y1={yFor(tick)} y2={yFor(tick)} stroke={white(0.12)} strokeWidth={0.5} />
          <text x={CHART.left - 6} y={yFor(tick) + 3} textAnchor="end" style={labelStyle}>
            {tick === 0 ? '0' : tokenAbbreviation(tick)}
          </text>
        </g>
      ))}
      <g clipPath={`url(#${id}-clip)`}>
        <path d={`${line} L${last[0]},${baseline} L${CHART.left},${baseline} Z`} fill={`url(#${id}-fill)`} />
        <path d={line} fill="none" stroke={color.blue} strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" />
        <circle cx={last[0]} cy={last[1]} r={3.2} fill="#fff" stroke={color.blue} strokeWidth={1.6} />
      </g>
      {tokenTrend.points.map((point, index) => (
        <text key={point.label} x={points[index]?.[0] ?? 0} y={CHART.height - 4} textAnchor="middle" style={labelStyle}>
          {point.label}
        </text>
      ))}
    </svg>
  );
};

const HEAT_GAP = 1.5;
const HEAT_HEIGHT = 110;
const CELL_WIDTH = (RIGHT_WIDTH - HEAT_GAP * (heatmap.weeks - 1)) / heatmap.weeks;
const CELL_HEIGHT = (HEAT_HEIGHT - HEAT_GAP * 6) / 7;
const HEAT_ALPHA = [0, 0.25, 0.45, 0.7, 1];

const heatStyle = (level: number): CSSProperties =>
  level <= 0
    ? {boxShadow: `inset 0 0 0 0.5px ${white(0.07)}`}
    : {background: alpha(color.green, HEAT_ALPHA[level] ?? 1)};

const Heatmap = ({reveal, todayLevel, selection, todayTokens}: {reveal: number; todayLevel: number; selection: number; todayTokens: number}) => {
  const cells: ReactNode[] = [];
  for (let week = 0; week < heatmap.weeks; week++) {
    for (let day = 0; day < 7; day++) {
      const isToday = week === heatmap.selected.week && day === heatmap.selected.day;
      // 今天之后的日期还没发生，真实界面里是空的
      if (week === heatmap.selected.week && day > heatmap.selected.day) {
        continue;
      }
      cells.push(
        <div
          key={`${week}-${day}`}
          className="absolute"
          style={{
            left: week * (CELL_WIDTH + HEAT_GAP),
            top: day * (CELL_HEIGHT + HEAT_GAP),
            width: CELL_WIDTH,
            height: CELL_HEIGHT,
            borderRadius: 1,
            opacity: clamp01(reveal * 34 - week - day * 0.5),
            ...heatStyle(isToday ? todayLevel : heatmap.level(week, day)),
            ...(isToday && selection > 0.01 ? {outline: `1px solid ${white(0.9 * selection)}`, outlineOffset: -1} : {}),
          }}
        />,
      );
    }
  }
  return (
    <div className="flex shrink-0 flex-col gap-[3px]">
      <div className="relative" style={{width: RIGHT_WIDTH, height: HEAT_HEIGHT}}>
        {cells}
      </div>
      <div className="relative h-[13px]">
        {heatmap.monthLabels.map((month) => (
          <span
            key={month.label}
            className="absolute font-mono text-[9px] leading-[13px] font-semibold"
            style={{left: month.week * (CELL_WIDTH + HEAT_GAP), color: white(0.75)}}
          >
            {month.label}
          </span>
        ))}
      </div>
      <div className="flex h-[11px] items-center gap-1 text-[9px] text-label-2">
        <span>Few</span>
        {HEAT_ALPHA.map((_, level) => (
          <div key={level} style={{width: 7, height: 7, borderRadius: 1, ...heatStyle(level)}} />
        ))}
        <span className="font-mono">Many · {tokenAbbreviation(heatmap.total)}</span>
      </div>
      <div className="tabular h-[13px] font-mono text-[9px] leading-[13px] text-label-2" style={{opacity: selection}}>
        {heatmap.selected.label} · {tokenAbbreviation(todayTokens)} Token
      </div>
    </div>
  );
};

export const AIModule = ({frame, rows, trend, todayTokens, heat, todayLevel, selection}: AIModuleProps) => {
  const active = rows.filter((row) => (row.enter ?? 1) > 0.5).length;
  return (
    <div className="absolute inset-0 flex gap-3">
      <div className="flex min-w-0 flex-1 flex-col gap-3">
        <SectionTitle
          icon={Cpu}
          label="Run task"
          size={10}
          trailing={<span className="tabular font-mono text-[9px] font-bold text-label-2">{active}</span>}
        />
        <div className="flex flex-col gap-[6px]">
          {rows.map((row) => (
            <TaskRow key={row.task.id} row={row} frame={frame} />
          ))}
        </div>
      </div>
      <Hairline vertical />
      <div className="flex shrink-0 flex-col gap-3" style={{width: RIGHT_WIDTH}}>
        <SectionTitle icon={ChartLine} label="Token usage trend" size={11} />
        <TrendChart reveal={trend} todayTokens={todayTokens} />
        <Heatmap reveal={heat} todayLevel={todayLevel} selection={selection} todayTokens={todayTokens} />
      </div>
    </div>
  );
};
