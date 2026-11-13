import type {ReactNode} from 'react';
import type {LucideIcon} from 'lucide-react';
import {AudioLines, CircleArrowDown, Sparkles, Timer} from 'lucide-react';
import {ProgressTrack} from '../components/Glass';
import {AlbumArt, BrowserGlyph, ProviderLogo, formatTime} from '../components/IslandChrome';
import {aiTasks, brands, download, focus, track} from '../content';
import type {AiTask} from '../content';
import {clamp01, color} from '../theme';

export type HomeCardKind = 'focus' | 'ai' | 'media' | 'download';

type HomeModuleProps = {
  cards: readonly HomeCardKind[];
  downloadProgress?: number;
  aiProgress?: number;
  // Keep the countdown in film time across scene boundaries.
  focusRemaining?: number;
  tasks?: readonly AiTask[];
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

export const HomeModule = ({cards, downloadProgress = 0, aiProgress = 0, focusRemaining = focus.remaining, tasks = aiTasks.slice(0, 1)}: HomeModuleProps) => {
  const groups = [...new Set(tasks.map((task) => task.provider))].map((provider) => ({provider, tasks: tasks.filter((task) => task.provider === provider)}));
  const entries = cards.flatMap<{kind: HomeCardKind; group: typeof groups[number] | undefined}>((kind) => kind === 'ai' ? groups.map((group) => ({kind, group})) : [{kind, group: undefined}]);
  return (
    <div className="absolute inset-0 flex flex-wrap content-start gap-2 px-[9px] py-[7px]">
      {entries.map(({kind, group}) => (
        <div key={group?.provider ?? kind} className="h-16 shrink-0" style={{width: entries.length === 1 ? 734 : 363}}>
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
            {group ? (
              <div className="flex w-full items-center gap-2" data-feature="ai.applicationSummary" data-provider={group.provider} data-task-count={group.tasks.length}>
                <ProviderLogo provider={group.provider} size={24} />
                <div className="flex min-w-0 flex-1 flex-col gap-[5px]">
                  <div className="truncate text-[10px] leading-[12px] font-semibold">{group.tasks.length > 1 ? brands[group.provider].name : group.tasks[0]!.title}</div>
                  <div className="text-[9px] font-medium text-label-2">{group.tasks.length} running</div>
                  {group.tasks.length === 1 ? <div className="flex items-center gap-2">
                    <ProgressTrack value={aiProgress} tint={brands[group.provider].color} width={270} height={3} />
                    <Percent value={aiProgress} />
                  </div> : null}
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
