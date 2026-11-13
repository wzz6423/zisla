import type {CSSProperties, ReactNode} from 'react';
import type {LucideIcon} from 'lucide-react';
import {alpha, clamp01, color, white} from '../theme';

export const GLASS_BLUR = 'blur(24px) saturate(180%)';

type GlassPanelProps = {
  children?: ReactNode;
  radius?: number;
  tint?: string;
  opacity?: number;
  className?: string;
  style?: CSSProperties;
};

// backdrop-filter 只有在祖先都不带 opacity / filter 时才取得到背后的画面，
// 所以淡入淡出必须作用在面板自己身上，不能包一层半透明容器。
export const GlassPanel = ({
  children,
  radius = 18,
  tint = 'rgba(28,28,32,0.52)',
  opacity = 1,
  className,
  style,
}: GlassPanelProps) => (
  <div
    className={className}
    style={{
      position: 'absolute',
      borderRadius: radius,
      background: tint,
      backdropFilter: GLASS_BLUR,
      WebkitBackdropFilter: GLASS_BLUR,
      border: `1px solid ${color.strokeCard}`,
      boxShadow: `inset 0 1px 0 ${white(0.12)}, inset 0 0 28px ${white(0.035)}, 0 26px 70px rgba(0,0,0,0.5)`,
      overflow: 'hidden',
      opacity,
      ...style,
    }}
  >
    {children}
  </div>
);

export const Hairline = ({vertical = false, style}: {vertical?: boolean; style?: CSSProperties}) => (
  <div
    className="shrink-0 self-stretch"
    style={{background: white(0.08), ...(vertical ? {width: 1} : {height: 1}), ...style}}
  />
);

type IconButtonProps = {
  icon: LucideIcon;
  compact?: boolean;
  active?: boolean;
  activeColor?: string;
  filled?: boolean;
};

export const IconButton = ({
  icon: Icon,
  compact = false,
  active = false,
  activeColor = color.blue,
  filled = false,
}: IconButtonProps) => {
  const size = compact ? 24 : 28;
  return (
    <div
      className="flex shrink-0 items-center justify-center rounded-full"
      style={{
        width: size,
        height: size,
        background: active ? alpha(activeColor, 0.16) : color.fillControl,
        color: active ? activeColor : color.label,
      }}
    >
      <Icon size={compact ? 11 : 13} strokeWidth={2.5} fill={filled ? 'currentColor' : 'none'} />
    </div>
  );
};

type TextButtonProps = {
  icon: LucideIcon;
  label: string;
  // 0–1，影片里用来提示“这里可以点”
  highlight?: number;
};

export const TextButton = ({icon: Icon, label, highlight = 0}: TextButtonProps) => (
  <div
    className="flex shrink-0 items-center gap-1 rounded-[6px] px-[5px] py-[3px] text-[10px] font-medium"
    style={{
      color: highlight > 0.01 ? color.label : color.secondary,
      background: white(0.14 * highlight),
    }}
  >
    <Icon size={11} strokeWidth={2.2} />
    <span>{label}</span>
  </div>
);

// 七根频谱条的电平。真实应用读 Core Audio tap，这里用几组不同频率的正弦叠出同样的观感。
export const waveLevels = (frame: number, energy = 1, seed = 0): number[] =>
  Array.from({length: 7}, (_, index) => {
    const phase = seed * 1.7 + index * 1.31;
    const value =
      0.5 +
      0.28 * Math.sin(frame * 0.21 + phase) +
      0.2 * Math.sin(frame * 0.093 + phase * 2.3) +
      0.12 * Math.sin(frame * 0.37 + phase * 0.7);
    return clamp01(value * energy);
  });

type WaveformProps = {width: number; height: number; levels: readonly number[]; tint?: string};

export const Waveform = ({width, height, levels, tint = color.coverTint}: WaveformProps) => {
  const spacing = Math.min(2.4, width * 0.055);
  const barWidth = Math.max(2, (width - spacing * 6) / 7);
  return (
    <div className="flex shrink-0 items-center" style={{width, height, gap: spacing}}>
      {levels.map((level, index) => (
        <div
          key={index}
          style={{
            width: barWidth,
            height: Math.max(3, height * (0.16 + level * 0.84)),
            borderRadius: barWidth / 2,
            background: alpha(tint, 0.94),
          }}
        />
      ))}
    </div>
  );
};

type ProgressTrackProps = {value: number; tint: string; width: number | string; height?: number};

export const ProgressTrack = ({value, tint, width, height = 4}: ProgressTrackProps) => (
  <div className="shrink-0 overflow-hidden" style={{width, height, borderRadius: height / 2, background: white(0.14)}}>
    <div style={{width: `${clamp01(value) * 100}%`, height: '100%', borderRadius: height / 2, background: tint}} />
  </div>
);
