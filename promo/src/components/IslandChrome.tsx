import type {ReactNode} from 'react';
import {Img} from 'remotion';
import type {LucideIcon} from 'lucide-react';
import {
  Airplay,
  AudioLines,
  Calendar,
  ChartLine,
  Check,
  CircleArrowDown,
  CircleChevronDown,
  Clipboard,
  FastForward,
  Gauge,
  Globe,
  Heart,
  Inbox,
  Keyboard,
  LayoutGrid,
  Mail,
  Music,
  NotepadText,
  Pause,
  Pin,
  Play,
  Rewind,
  Settings,
  Shuffle,
  SlidersHorizontal,
  Wrench,
} from 'lucide-react';
import {providerLogo} from '../assets';
import type {AiTask, Provider} from '../content';
import {brands, clock, monitors, track} from '../content';
import {clamp01, color, white} from '../theme';
import {IconButton, Waveform} from './Glass';

export const TABS = {
  home: 0,
  shelf: 1,
  clipboard: 2,
  download: 3,
  agenda: 4,
  toolbox: 5,
  notes: 6,
  ai: 7,
  keyboard: 8,
  mail: 9,
  cpu: 10,
  mixer: 11,
} as const;

const TAB_ICONS: readonly LucideIcon[] = [
  LayoutGrid,
  Inbox,
  Clipboard,
  CircleArrowDown,
  Calendar,
  Wrench,
  NotepadText,
  ChartLine,
  Keyboard,
  Mail,
  Gauge,
  SlidersHorizontal,
];

export const ProviderLogo = ({provider, size}: {provider: Provider; size: number}) => (
  <Img src={providerLogo[provider]} className="shrink-0" style={{width: size, height: size, objectFit: 'contain'}} />
);

const LANTERNS: readonly (readonly [number, number, number])[] = [
  [20, 44, 14],
  [47, 20, 18],
  [69, 50, 12],
  [37, 70, 9],
];

// 虚构专辑《Night Cartography》的封面，纯 CSS 绘制
export const AlbumArt = ({size, radius}: {size: number; radius: number}) => {
  const [warm, rose, night] = track.art;
  return (
    <div
      className="relative shrink-0 overflow-hidden"
      style={{
        width: size,
        height: size,
        borderRadius: radius,
        background: `radial-gradient(circle at 26% 24%, ${warm} 0%, transparent 54%), radial-gradient(circle at 78% 76%, ${rose} 0%, transparent 60%), linear-gradient(145deg, ${night}, #0b0e24)`,
      }}
    >
      {LANTERNS.map(([x, y, scale], index) => (
        <div
          key={index}
          className="absolute rounded-full"
          style={{
            left: `${x}%`,
            top: `${y}%`,
            width: `${scale}%`,
            height: `${scale * 1.25}%`,
            background: 'radial-gradient(circle at 50% 40%, #fff3d6, #ffb86b 62%, rgba(255,150,80,0) 100%)',
            boxShadow: `0 0 ${size * 0.09}px rgba(255,190,120,0.85)`,
          }}
        />
      ))}
    </div>
  );
};

export const formatTime = (seconds: number): string => {
  const whole = Math.max(0, Math.floor(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
};

export const lyricAt = (frame: number, period = 132): {text: string; opacity: number} => {
  const safe = Math.max(0, frame);
  const index = Math.floor(safe / period) % track.lyrics.length;
  return {text: track.lyrics[index] ?? '', opacity: clamp01((safe % period) / 12)};
};

type NowPlayingHeaderProps = {
  elapsed: number;
  levels: readonly number[];
  lyric: {text: string; opacity: number};
  favorite?: boolean;
  playing?: boolean;
};

export const NowPlayingHeader = ({elapsed, levels, lyric, favorite = true, playing = true}: NowPlayingHeaderProps) => {
  const played = clamp01(elapsed / track.duration) * 100;
  return (
    <div className="flex h-[72px] flex-col justify-center gap-[5px]">
      <div className="flex items-center gap-[10px]">
        <div className="relative shrink-0">
          <AlbumArt size={54} radius={8} />
          <div
            className="absolute flex items-center justify-center"
            style={{right: 3, bottom: 3, width: 16, height: 16, borderRadius: 3.5, background: 'rgba(18,18,22,0.92)'}}
          >
            <Music size={9} strokeWidth={2.6} />
          </div>
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-[3px]">
          <div className="truncate text-[13px] leading-[16px] font-semibold">
            {track.title} · {track.artist}
          </div>
          <div className="truncate text-[10.5px] leading-[13px] font-medium text-label-2" style={{opacity: lyric.opacity}}>
            {lyric.text}
          </div>
        </div>
        <Waveform width={34} height={28} levels={levels} />
        <div className="flex gap-[2px]">
          <IconButton compact icon={Shuffle} />
          <IconButton compact icon={Heart} active={favorite} activeColor="rgb(255,106,106)" filled={favorite} />
          <IconButton compact icon={Airplay} />
          <IconButton compact icon={Rewind} filled />
          <IconButton compact icon={playing ? Pause : Play} filled />
          <IconButton compact icon={FastForward} filled />
        </div>
      </div>
      <div className="flex h-[9px] items-center gap-2">
        <span className="tabular font-mono text-[9px] font-medium text-label-2">{formatTime(elapsed)}</span>
        <div className="relative h-[2px] flex-1 rounded-full" style={{background: 'rgba(235,235,245,0.25)'}}>
          <div className="absolute top-0 left-0 h-full rounded-full" style={{width: `${played}%`, background: color.blue}} />
          <div
            className="absolute rounded-full"
            style={{left: `calc(${played}% - 4.5px)`, top: -3.5, width: 9, height: 9, background: white(0.96)}}
          />
        </div>
        <span className="tabular font-mono text-[9px] font-medium text-label-2">{formatTime(track.duration)}</span>
      </div>
    </div>
  );
};

// 没有媒体在播时的标题行：有 AI 任务就显示任务，否则只有日期与时钟
export const StatusHeader = ({task, progress}: {task?: AiTask; progress?: number}) => (
  <div className="flex h-[72px] items-center gap-3">
    {task ? (
      <>
        <ProviderLogo provider={task.provider} size={30} />
        <div className="flex flex-col gap-[2px]">
          <div className="text-[12px] leading-[15px] font-semibold">{task.title}</div>
          <div className="flex items-center gap-[6px] text-[9px] leading-[11px] font-medium text-label-2">
            <span>{brands[task.provider].name} running</span>
            {progress === undefined ? null : (
              <span className="tabular font-mono font-semibold text-label">{Math.round(progress * 100)}%</span>
            )}
          </div>
        </div>
      </>
    ) : (
      <>
        <Calendar size={15} strokeWidth={2.2} />
        <span className="text-[12px] font-semibold">{clock.date}</span>
      </>
    )}
    <div className="flex-1" />
    <div className="font-rounded tabular text-[19px] font-semibold">{clock.time}</div>
  </div>
);

// active 可以是小数：选中透镜在两个 tab 之间滑动时由调用方传入插值后的位置
export const Toolbar = ({active}: {active: number}) => (
  <div className="flex h-[30px] items-center justify-between">
    <div className="relative flex gap-[2px]">
      <div
        className="absolute top-0"
        style={{
          left: active * 30,
          width: 28,
          height: 30,
          borderRadius: 8,
          background:
            'linear-gradient(to bottom, rgba(0,0,0,0.82), rgba(0,0,0,0.56) 30%, rgba(0,0,0,0.10) 68%, rgba(0,0,0,0))',
          border: `0.75px solid ${white(0.24)}`,
          boxShadow: '0 1px 3px rgba(0,0,0,0.16)',
        }}
      />
      {TAB_ICONS.map((Icon, index) => (
        <div
          key={index}
          className="relative flex h-[30px] w-[28px] items-center justify-center"
          style={{color: Math.round(active) === index ? color.label : color.secondary}}
        >
          <Icon size={12} strokeWidth={2.4} />
        </div>
      ))}
    </div>
    <div className="flex items-center gap-2">
      <div className="flex items-center gap-1 rounded-full px-[6px] py-[4px]" style={{background: white(0.1)}}>
        {monitors.map((monitor) => (
          <div key={monitor.label} className="flex w-[26px] flex-col items-center leading-[11px]">
            <div className="font-rounded tabular text-[9px] font-semibold">{Math.round(monitor.value * 100)}%</div>
            <div className="text-[9px] font-medium text-label-2">{monitor.label}</div>
          </div>
        ))}
      </div>
      <div className="flex h-[28px] items-center rounded-full pr-[7px]" style={{background: white(0.1)}}>
        <div className="flex h-6 w-6 items-center justify-center">
          <AudioLines size={12} strokeWidth={2.4} />
        </div>
        <span className="text-[9px] font-semibold">Rain</span>
        <CircleChevronDown size={13} strokeWidth={2} className="ml-[5px] text-label-2" />
      </div>
      <IconButton icon={Pin} />
      <IconButton icon={Settings} />
    </div>
  </div>
);

type IslandBodyProps = {header: ReactNode; active: number; children?: ReactNode};

// 展开态的三段式：标题行、工具栏、模块区。模块区的子元素自行绝对定位，方便做切换动画。
export const IslandBody = ({header, active, children}: IslandBodyProps) => (
  <div className="absolute inset-0 flex flex-col">
    <div
      className="font-rounded tabular absolute text-[13px] font-semibold"
      style={{top: 10, right: 24, color: white(0.92)}}
    >
      {clock.uptime}
    </div>
    <div style={{padding: '16px 14px 4px'}}>{header}</div>
    <div style={{padding: '0 12px 7px'}}>
      <Toolbar active={active} />
    </div>
    <div className="min-h-0 flex-1" style={{padding: 12}}>
      <div className="relative h-full w-full overflow-hidden" style={{borderRadius: '0 0 22px 22px'}}>
        {children}
      </div>
    </div>
  </div>
);

export const CompactPercent = ({value}: {value: number}) => (
  <div className="font-rounded tabular text-[13px] font-semibold text-white">{Math.round(clamp01(value) * 100)}%</div>
);

export const CompactCheck = () => <Check size={15} strokeWidth={3.2} color={color.green} />;

// 浏览器下载用的通用替身图标，不使用任何真实浏览器的标志
export const BrowserGlyph = ({size}: {size: number}) => (
  <div
    className="flex shrink-0 items-center justify-center"
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.24,
      background: 'linear-gradient(160deg, #5b8cff, #2b4fd6)',
      boxShadow: `inset 0 0.5px 0 ${white(0.4)}`,
    }}
  >
    <Globe size={size * 0.62} strokeWidth={2.2} color="#fff" />
  </div>
);
