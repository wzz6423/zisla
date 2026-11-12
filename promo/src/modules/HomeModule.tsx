import type {ReactNode} from 'react';
import type {LucideIcon} from 'lucide-react';
import {AudioLines, CircleArrowDown, Sparkles, Timer} from 'lucide-react';
import {ProgressTrack} from '../components/Glass';
import {AlbumArt, BrowserGlyph, ProviderLogo, formatTime} from '../components/IslandChrome';
import {aiTasks, brands, download, focus, track} from '../content';
import {clamp01, color} from '../theme';

export type HomeCardKind = 'focus' | 'ai' | 'media' | 'download';

type HomeModuleProps = {
  cards: readonly HomeCardKind[];
  downloadProgress?: number;
  aiProgress?: number;
  // 番茄钟剩余秒数
  focusRemaining?: number;
};

const FOCUS_LENGTH = 25 * 60;

const cardMeta: Record<HomeCardKind, {title: string; tint: string; icon: LucideIcon}> = {
  focus: {title: 'Focus countdown', tint: color.orange, icon: Timer},
  ai: {title: 'AI work', tint: color.cyan, icon: Sparkles},
  media: {title: 'Now Playing', tint: color.cyan, icon: AudioLines},
  download: {title: 'Browser downloads', tint: color.green, icon: CircleArrowDown},
};

const Percent = ({value}: {value: number}) => (
  <span className="tabular w-[26px] text-right font-mono text-[9px] leading-[11px] font-semibold">
    {Math.round(clamp01(value) * 100)}%
  </span>
);

const Card = ({kind, children}: {kind: HomeCardKind; children: ReactNode}) => {
  const {title, tint, icon: Icon} = cardMeta[kind];
  return (
    <div className="flex h-16 flex-col gap-[5px] px-[9px] py-[7px]">
      <div className="flex items-center gap-[4px] text-[9px] leading-[11px] font-semibold" style={{color: tint}}>
        <Icon size={10} strokeWidth={2.4} />
        <span>{title}</span>
      </div>
      <div className="flex min-h-0 flex-1 items-center">{children}</div>
    </div>
  );
};

export const HomeModule = ({cards, downloadProgress = 0, aiProgress = 0, focusRemaining = focus.remaining}: HomeModuleProps) => {
  const task = aiTasks[0];
  return (
    <div className="absolute inset-0 flex flex-wrap content-start gap-2 px-[9px] py-[7px]">
      {cards.map((kind) => (
        <div key={kind} className="h-16 shrink-0" style={{width: cards.length === 1 ? 734 : 363}}>
          <Card kind={kind}>
            {kind === 'focus' ? (
              <div className="flex items-center gap-[9px]">
                <div className="font-rounded tabular text-[22px] leading-[26px] font-bold">{formatTime(focusRemaining)}</div>
                <div className="flex flex-col gap-[4px]">
                  <div className="text-[9px] leading-[11px] font-semibold text-label-2">{focus.phase} · In progress</div>
                  <ProgressTrack value={1 - clamp01(focusRemaining / FOCUS_LENGTH)} tint={color.orange} width={96} height={3} />
                </div>
              </div>
            ) : null}
            {kind === 'ai' && task ? (
              <div className="flex w-full items-center gap-2">
                <ProviderLogo provider={task.provider} size={24} />
                <div className="flex min-w-0 flex-1 flex-col gap-[5px]">
                  <div className="truncate text-[10px] leading-[12px] font-semibold">{task.title}</div>
                  <div className="flex items-center gap-2">
                    <ProgressTrack value={aiProgress} tint={brands[task.provider].color} width={270} height={3} />
                    <Percent value={aiProgress} />
                  </div>
                </div>
              </div>
            ) : null}
            {kind === 'media' ? (
              <div className="flex w-full items-center gap-2">
                <AlbumArt size={32} radius={5} />
                <div className="flex min-w-0 flex-1 flex-col">
                  <div className="truncate text-[10px] leading-[13px] font-semibold">{track.title}</div>
                  <div className="truncate text-[9px] leading-[12px] font-medium text-label-2">{track.artist}</div>
                </div>
              </div>
            ) : null}
            {kind === 'download' ? (
              <div className="flex w-full items-center gap-2">
                <BrowserGlyph size={24} />
                <div className="flex min-w-0 flex-1 flex-col gap-[5px]">
                  <div className="truncate text-[10px] leading-[12px] font-semibold">{download.name}</div>
                  <div className="flex items-center gap-2">
                    <ProgressTrack value={downloadProgress} tint={color.green} width={270} height={3} />
                    <Percent value={downloadProgress} />
                  </div>
                </div>
              </div>
            ) : null}
          </Card>
        </div>
      ))}
    </div>
  );
};
