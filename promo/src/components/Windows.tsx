import type {ReactNode} from 'react';
import {ArrowDownToLine, Check, ChevronLeft, ChevronRight, FileArchive, FileText, Folder, Image as ImageIcon, Link, Lock, Search, Video} from 'lucide-react';
import {GLASS_BLUR, ProgressTrack} from './Glass';
import {download} from '../content';
import {clamp01, color, white} from '../theme';

const TrafficLights = () => (
  <div className="flex items-center gap-[6px]">
    {['#ff5f57', '#febc2e', '#28c840'].map((dot) => (
      <div key={dot} style={{width: 11, height: 11, borderRadius: 6, background: dot}} />
    ))}
  </div>
);

export type FinderItemKind = 'image' | 'archive' | 'folder' | 'video' | 'text';

export type FinderItem = {name: string; tint: string; kind: FinderItemKind};

export const FINDER_ICONS = {
  image: ImageIcon,
  archive: FileArchive,
  folder: Folder,
  video: Video,
  text: FileText,
} as const;

const TILE = {width: 104, height: 100};

type FinderWindowProps = {
  x: number;
  y: number;
  width?: number;
  height?: number;
  items: readonly FinderItem[];
  path?: string;
  selected?: number;
  // 0–1，选中高亮的浓度
  selectGlow?: number;
  opacity?: number;
  scale?: number;
};

export const FinderWindow = ({
  x,
  y,
  width = 648,
  height = 402,
  items,
  path = 'Downloads',
  selected = 0,
  selectGlow = 1,
  opacity = 1,
  scale = 1,
}: FinderWindowProps) => {
  return (
    <div
      className="absolute flex flex-col overflow-hidden"
      style={{
        left: x,
        top: y,
        width,
        height,
        opacity: clamp01(opacity),
        transform: `scale(${scale})`,
        transformOrigin: 'center',
        borderRadius: 10,
        background: 'rgba(30,30,34,0.86)',
        backdropFilter: GLASS_BLUR,
        WebkitBackdropFilter: GLASS_BLUR,
        border: `1px solid ${white(0.13)}`,
        boxShadow: '0 34px 80px rgba(0,0,0,0.62)',
      }}
    >
      <div className="flex h-[30px] shrink-0 items-center px-3">
        <TrafficLights />
        <div className="flex-1 text-center text-[11px] font-medium text-label-3">{path}</div>
        <div style={{width: 45}} />
      </div>
      <div className="flex h-[34px] shrink-0 items-center gap-2 px-3" style={{background: white(0.04)}}>
        <ChevronLeft size={15} strokeWidth={2.4} color={color.secondary} />
        <ChevronRight size={15} strokeWidth={2.4} color={color.tertiary} />
        <div className="text-[11px] font-semibold text-label-2">{path}</div>
        <div className="flex-1" />
        <div className="flex h-[22px] w-[150px] items-center gap-[6px] rounded-full px-[9px]" style={{background: white(0.08)}}>
          <Search size={10} strokeWidth={2.4} color={color.tertiary} />
          <span className="text-[10px] text-label-3">Search</span>
        </div>
      </div>
      <div style={{height: 1, background: color.divider}} />
      <div className="relative flex min-h-0 flex-1 flex-wrap content-start gap-[6px]" style={{padding: 18}}>
        {items.map((item, index) => {
          const Icon = FINDER_ICONS[item.kind];
          const isSelected = index === selected;
          return (
            <div
              key={item.name}
              className="relative flex flex-col items-center gap-[6px] px-[6px] py-[8px]"
              style={{width: TILE.width, height: TILE.height}}
            >
              {isSelected ? (
                <div
                  className="absolute inset-0 rounded-[6px]"
                  style={{background: white(0.14), opacity: selectGlow}}
                />
              ) : null}
              <div className="relative flex h-[46px] items-center justify-center">
                <Icon size={42} strokeWidth={1.2} color={item.tint} />
              </div>
              <div
                className="relative text-center text-[10px] leading-[12px] font-medium"
                style={{
                  display: '-webkit-box',
                  WebkitLineClamp: 2,
                  WebkitBoxOrient: 'vertical',
                  overflow: 'hidden',
                  // 选中的文件名垫一层深色底，压在蓝色高亮块上才读得清
                  background: isSelected ? 'rgba(10,10,12,0.55)' : 'transparent',
                  borderRadius: 3,
                  padding: isSelected ? '1px 3px' : 0,
                }}
              >
                {item.name}
              </div>
            </div>
          );
        })}
      </div>
      <div className="flex h-[22px] shrink-0 items-center justify-center text-[10px] text-label-3">
        {items.length} items
      </div>
      <div className="h-2" />
    </div>
  );
};

type BrowserWindowProps = {
  x: number;
  y: number;
  width?: number;
  height?: number;
  // 0–1，下载进度，用来点亮地址栏右侧的下载按钮
  progress?: number;
  opacity?: number;
  scale?: number;
  children?: ReactNode;
};

export const BrowserWindow = ({x, y, width = 760, height = 470, progress = 0, opacity = 1, scale = 1, children}: BrowserWindowProps) => (
  <div
    className="absolute flex flex-col overflow-hidden"
    style={{
      left: x,
      top: y,
      width,
      height,
      opacity: clamp01(opacity),
      transform: `scale(${scale})`,
      transformOrigin: 'center',
      borderRadius: 10,
      background: '#16161a',
      border: `1px solid ${white(0.12)}`,
      boxShadow: '0 34px 80px rgba(0,0,0,0.62)',
    }}
  >
    <div className="flex h-[34px] shrink-0 items-end gap-[10px] px-3">
      <div className="pb-[11px]">
        <TrafficLights />
      </div>
      <div
        className="flex h-[26px] items-center gap-[7px] rounded-t-[7px] px-[11px] text-[10.5px] font-medium"
        style={{background: '#22222a', width: 190}}
      >
        <div style={{width: 9, height: 9, borderRadius: 3, background: color.blue}} />
        <span className="truncate text-label-2">Launch assets — Draft</span>
      </div>
    </div>
    <div className="flex h-[38px] shrink-0 items-center gap-2 px-3" style={{background: 'rgba(10,10,12,0.6)'}}>
      <ChevronLeft size={14} strokeWidth={2.4} color={color.tertiary} />
      <div className="flex h-[24px] flex-1 items-center gap-[7px] rounded-full px-[11px]" style={{background: white(0.08)}}>
        <Lock size={10} strokeWidth={2.6} color={color.tertiary} />
        <span className="text-[10.5px] text-label-2">example.com/launch-assets</span>
        <div className="flex-1" />
        <Link size={11} strokeWidth={2.2} color={color.tertiary} />
      </div>
      <div className="relative flex items-center justify-center" style={{width: 24, height: 24}}>
        <ArrowDownToLine size={14} strokeWidth={2.3} color={progress > 0.01 ? color.blue : color.tertiary} />
        {progress > 0.01 ? (
          <div
            className="absolute -bottom-[2px] h-[2px] rounded-full"
            style={{width: 16 * clamp01(progress), background: color.blue}}
          />
        ) : null}
      </div>
    </div>
    <div className="relative min-h-0 flex-1" style={{background: 'radial-gradient(120% 90% at 50% 0%, #1e1e26 0%, #121216 70%)'}}>
      <div className="absolute inset-x-0 top-[38px] flex flex-col items-center gap-[18px]">
        <div className="flex flex-col items-center gap-[10px]">
          <div style={{width: 210, height: 16, borderRadius: 8, background: white(0.22)}} />
          <div style={{width: 320, height: 9, borderRadius: 5, background: white(0.1)}} />
          <div style={{width: 250, height: 9, borderRadius: 5, background: white(0.1)}} />
        </div>
        <div
          className="flex items-center gap-[8px] rounded-full px-[16px] py-[8px] text-[11.5px] font-semibold"
          style={{background: color.blue, boxShadow: `0 8px 22px ${color.blue}44`}}
        >
          <ArrowDownToLine size={13} strokeWidth={2.6} color="#fff" />
          <span style={{color: '#fff'}}>Download assets</span>
        </div>
        <div className="flex gap-[14px]">
          {[0, 1, 2].map((index) => (
            <div key={index} style={{width: 178, height: 116, borderRadius: 10, background: white(0.06), border: `1px solid ${white(0.07)}`}} />
          ))}
        </div>
      </div>
    </div>
    {children}
  </div>
);

type DownloadPopoverProps = {
  x: number;
  y: number;
  progress: number;
  opacity?: number;
  done?: boolean;
};

export const DownloadPopover = ({x, y, progress, opacity = 1, done = false}: DownloadPopoverProps) => {
  const value = clamp01(progress);
  return (
    <div
      className="absolute flex flex-col gap-[9px] p-[12px]"
      style={{
        left: x,
        top: y,
        width: 336,
        borderRadius: 12,
        background: 'rgba(30,30,34,0.9)',
        backdropFilter: GLASS_BLUR,
        WebkitBackdropFilter: GLASS_BLUR,
        border: `1px solid ${white(0.13)}`,
        boxShadow: '0 22px 52px rgba(0,0,0,0.6)',
        opacity: clamp01(opacity),
      }}
    >
      <div className="flex items-center gap-[10px]">
        <div
          className="flex shrink-0 items-center justify-center"
          style={{width: 34, height: 34, borderRadius: 8, background: done ? `${color.green}22` : white(0.08)}}
        >
          {done ? <Check size={18} strokeWidth={2.8} color={color.green} /> : <FileArchive size={18} strokeWidth={2} color={color.secondary} />}
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-[3px]">
          <div className="truncate text-[12.5px] leading-[15px] font-semibold">{download.name}</div>
          <div className="tabular text-[10px] leading-[12px] text-label-2">
            {done ? `${download.size} · ${download.path}` : `${(48.2 * value).toFixed(1)} MB of ${download.size} · 12.4 MB/s`}
          </div>
        </div>
      </div>
      <div className="flex items-center gap-[9px]">
        <ProgressTrack value={value} tint={done ? color.green : color.blue} width={264} height={3} />
        <span className="tabular w-[34px] text-right font-mono text-[10px] font-semibold">{Math.round(value * 100)}%</span>
      </div>
    </div>
  );
};
