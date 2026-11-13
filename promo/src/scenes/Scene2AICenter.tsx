import {ChevronLeft, ChevronRight, RotateCw, ShieldCheck} from 'lucide-react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {ClickRipple, Cursor} from '../components/Cursor';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {Island, modulePhase} from '../components/Island';
import {IslandBody, ProviderLogo, StatusHeader, TABS} from '../components/IslandChrome';
import {Camera} from '../components/Stage';
import {TerminalWindow} from '../components/Terminal';
import {aiTasks, copy} from '../content';
import type {AiTask} from '../content';
import {AI_HEATMAP_TARGET, AIModule, TrendChart} from '../modules/AIModule';
import {AIAnalyticsModule, AccountQuotaRing, DailyModelUsageList, aiBalancesAt, aiModelTokenTotal, quotaValue} from '../modules/AIAnalyticsModule';
import {FilmMotion, ZislaMotion, ease, linear, springAt, track} from '../motion';
import {MODULE_HEIGHT, NOTCH_WIDTH, STAGE, alpha, clamp01, color, islandHeightFor, lerp} from '../theme';

const COMMAND = 'zislactl update --id build-01 --provider claude --title "Refactoring core" --progress 74';
export const AI_DURATION = 960;
export const AI_ACTIONS = {sent: 24, wing: 30, expand: 90, selectDay: 192, models: 222, settings: 318, viewHistory: 354, history: 378, historyDay: 390, export: 420, save: 450, saved: 474, balance: 570, lowQuota: 738, collapse: 780} as const;

const TERMINAL = {width: 760, height: 168};
const HISTORY_WINDOW = {x: 260, y: 40, width: 760, height: 640};
const HISTORY_TARGETS = {view: {x: 443, y: 204}, day: {x: 948, y: 365}, export: {x: 967, y: 82}, save: {x: 821, y: 377}, close: {x: 277, y: 54}};

const taskById = (id: string): AiTask => aiTasks.find((task) => task.id === id) ?? (aiTasks[0] as AiTask);

export const aiSceneStateAt = (frame: number, duration = AI_DURATION) => {
  const local = frame * AI_DURATION / duration;
  return {
    local,
    selected: local >= AI_ACTIONS.selectDay,
    lowQuota: local >= AI_ACTIONS.lowQuota,
    scroll: track(local, [[AI_ACTIONS.models, 0], [AI_ACTIONS.models + 42, 180], [AI_ACTIONS.balance, 180], [AI_ACTIONS.balance + 42, 322]]),
    settings: local >= AI_ACTIONS.settings + 12 && local < AI_ACTIONS.history,
    history: local >= AI_ACTIONS.history && local < AI_ACTIONS.balance,
    historySelected: local >= AI_ACTIONS.historyDay,
    exporting: local >= AI_ACTIONS.export && local < AI_ACTIONS.saved,
    saved: local >= AI_ACTIONS.saved,
    cursor: {
      x: track(local, [[0, 1040], [AI_ACTIONS.expand - 6, STAGE.width / 2], [AI_ACTIONS.selectDay - 12, 264 + AI_HEATMAP_TARGET.x], [AI_ACTIONS.selectDay + 6, 264 + AI_HEATMAP_TARGET.x], [AI_ACTIONS.models - 6, 994], [AI_ACTIONS.settings, 1000], [AI_ACTIONS.viewHistory - 6, HISTORY_TARGETS.view.x], [AI_ACTIONS.history, HISTORY_TARGETS.view.x], [AI_ACTIONS.historyDay, HISTORY_TARGETS.day.x], [AI_ACTIONS.export, HISTORY_TARGETS.export.x], [AI_ACTIONS.save - 6, HISTORY_TARGETS.save.x], [AI_ACTIONS.saved, HISTORY_TARGETS.save.x], [AI_ACTIONS.balance - 12, HISTORY_TARGETS.close.x], [AI_ACTIONS.balance - 6, HISTORY_TARGETS.close.x], [AI_ACTIONS.balance + 18, 994], [AI_ACTIONS.collapse - 12, 994], [AI_ACTIONS.collapse, 1050]]),
      y: track(local, [[0, 470], [AI_ACTIONS.expand - 6, 18], [AI_ACTIONS.selectDay - 12, AI_HEATMAP_TARGET.y], [AI_ACTIONS.selectDay + 6, AI_HEATMAP_TARGET.y], [AI_ACTIONS.models - 6, 350], [AI_ACTIONS.settings, 111], [AI_ACTIONS.viewHistory - 6, HISTORY_TARGETS.view.y], [AI_ACTIONS.history, HISTORY_TARGETS.view.y], [AI_ACTIONS.historyDay, HISTORY_TARGETS.day.y], [AI_ACTIONS.export, HISTORY_TARGETS.export.y], [AI_ACTIONS.save - 6, HISTORY_TARGETS.save.y], [AI_ACTIONS.saved, HISTORY_TARGETS.save.y], [AI_ACTIONS.balance - 12, HISTORY_TARGETS.close.y], [AI_ACTIONS.balance - 6, HISTORY_TARGETS.close.y], [AI_ACTIONS.balance + 18, 350], [AI_ACTIONS.collapse - 12, 350], [AI_ACTIONS.collapse, 480]]),
    },
  };
};

const UsageHistorySettings = () => <div className="absolute" data-feature="ai.usage.settings" style={{left: 350, top: 78, width: 580}}>
  <GlassPanel radius={12} tint="rgba(28,28,32,0.98)" style={{width: 580, padding: 24}}>
    <div className="mb-5 text-[18px] font-semibold">Settings · AI usage</div>
    <div className="mb-4 text-[13px] text-label-2">AI usage history</div>
    <div className="flex gap-3 text-[12px]">
      <span className="rounded-[6px] px-4 py-2" style={{background: color.fillControl}}>View History</span>
      <span className="rounded-[6px] px-4 py-2" style={{background: color.fillControl}}>Export</span>
      <span className="rounded-[6px] px-4 py-2" style={{background: color.fillControl}}>Clear</span>
    </div>
  </GlassPanel>
</div>;

const UsageHistoryWindow = ({state}: {state: ReturnType<typeof aiSceneStateAt>}) => <div className="absolute flex flex-col" data-feature="ai.usage.history" data-export-stage={state.saved ? 'saved' : state.exporting ? 'saving' : 'ready'} style={{left: HISTORY_WINDOW.x, top: HISTORY_WINDOW.y, width: HISTORY_WINDOW.width, height: HISTORY_WINDOW.height, borderRadius: 12, background: '#242426', border: `1px solid ${color.strokeCard}`, boxShadow: '0 24px 70px rgba(0,0,0,0.5)'}}>
  <div className="flex h-[28px] shrink-0 items-center gap-[7px] px-3">
    {['#ff5f57', '#febc2e', '#28c840'].map((tint) => <span key={tint} className="rounded-full" style={{width: 10, height: 10, background: tint}} />)}
  </div>
  <div className="flex min-h-0 flex-1 flex-col gap-[14px] px-[18px] pb-[18px]">
    <div className="flex h-[28px] shrink-0 items-center gap-3">
      <span className="text-[16px] font-semibold">AI usage history</span><span className="flex-1" />
      <span className="text-[11px]">Clear</span>
      <span className="rounded-[6px] px-3 py-[6px] text-[11px] font-semibold" data-feature="ai.usage.export" style={{background: color.blue}}>Export</span>
    </div>
    <div className="flex h-[24px] shrink-0 items-center gap-3 text-[11px]">
      <span className="text-label-2">Time range</span>
      <div className="flex rounded-[6px] p-[2px]" style={{width: 280, background: color.fillControl}}>{['24 hours', '7 days', '30 days', 'All'].map((range) => <span key={range} className="flex-1 rounded-[4px] py-[3px] text-center" style={{background: range === '7 days' ? color.fillCard : undefined}}>{range}</span>)}</div>
      <span className="flex-1" /><RotateCw size={13} />
    </div>
    <div className="h-px shrink-0" style={{background: color.divider}} />
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-hidden">
      <TrendChart reveal={1} todayTokens={aiModelTokenTotal} width={722} height={180} />
      <div className="flex gap-[1.5px] text-[9px]" data-feature="ai.usage.history.days">
        {['11/05', '11/06', '11/07', '11/08', '11/09', '11/10', '11/11'].map((day, index) => <div key={day} className="flex flex-1 flex-col items-center gap-[3px]">
          <span style={{width: 12, height: 12, borderRadius: 1, background: alpha(color.green, [0.45, 0.7, 0.25, 0.7, 0.7, 1, 0.7][index]!), outline: index === 6 && state.historySelected ? '1px solid white' : undefined, outlineOffset: -1}} /><span>{day}</span>
        </div>)}
      </div>
      {state.historySelected ? <DailyModelUsageList width={722} /> : null}
    </div>
    <div className="flex h-[18px] shrink-0 items-center text-[11px] text-label-2">
      {state.saved ? <span data-feature="ai.usage.exported">Saved to AI usage.xlsx</span> : null}
    </div>
  </div>
  {state.exporting ? <div className="absolute flex flex-col gap-4 rounded-[8px] p-6 text-[12px]" data-feature="ai.usage.save" style={{left: 140, top: 206, width: 480, background: '#303034', border: `1px solid ${color.strokeCard}`, boxShadow: '0 18px 44px rgba(0,0,0,0.45)'}}>
    <div className="flex items-center gap-3"><span className="w-[66px]">Save As:</span><span className="flex-1 rounded-[5px] px-2 py-[6px]" style={{background: color.fillControl}}>AI usage.xlsx</span></div>
    <div className="flex items-center gap-3"><span className="w-[66px]">Where:</span><span className="flex flex-1 items-center gap-2 rounded-[5px] px-2 py-[6px]" style={{background: color.fillControl}}><ChevronLeft size={12} /><span className="flex-1">Documents</span><ChevronRight size={12} /></span></div>
    <div className="flex justify-end gap-3"><span className="rounded-[6px] px-4 py-[6px]" style={{background: color.fillControl}}>Cancel</span><span className="rounded-[6px] px-4 py-[6px]" style={{background: color.blue}}>Export</span></div>
  </div> : null}
</div>;

const CompactQuota = () => {
  const balance = aiBalancesAt(true)[0]!;
  const fiveHour = balance.windows[0]!;
  const weekly = balance.windows[1]!;
  const sideWidth = 64;
  return <div className="absolute top-0 flex items-center justify-between" data-feature="ai.quota.compact" data-severity="critical" data-notice-id="ai-balance-low-claude" style={{left: (STAGE.width - NOTCH_WIDTH) / 2 - sideWidth, width: NOTCH_WIDTH + sideWidth * 2, height: 34, borderRadius: '0 0 14px 14px', background: '#000'}}>
    <div className="flex items-center justify-center" style={{width: sideWidth}}><AccountQuotaRing balance={balance} outer={weekly} inner={fiveHour} diameter={26} /></div>
    <div className="flex flex-col gap-[1px] pl-3 text-[9px] leading-[13px] font-semibold" style={{width: sideWidth}}>
      <span data-feature="ai.quota.warning" style={{color: color.red}}>5h {quotaValue(fiveHour)}</span>
      <span style={{color: color.green}}>7d {quotaValue(weekly)}</span>
    </div>
  </div>;
};

export const Scene2AICenter = ({duration = AI_DURATION}: {duration?: number; globalFrom?: number}) => {
  const sourceFrame = useCurrentFrame();
  const state = aiSceneStateAt(sourceFrame, duration);
  const frame = state.local;
  const {fps} = useVideoConfig();
  const seconds = frame / fps;

  const build = taskById('build-01');
  const progress = 0.74;

  const collapse = clamp01(springAt(frame, fps, AI_ACTIONS.collapse, ZislaMotion.islandRecycle, 36));
  const reveal = springAt(frame, fps, AI_ACTIONS.expand, ZislaMotion.islandReveal, 42) * (1 - collapse);
  const wing = lerp(0, 40, clamp01(springAt(frame, fps, AI_ACTIONS.wing, ZislaMotion.notice, 30)));
  const moduleIn = clamp01((frame - AI_ACTIONS.expand - 8) / 24);
  const rowEnter = springAt(frame, fps, AI_ACTIONS.expand + 14, ZislaMotion.surfaceResize, 40);

  const terminalIn = springAt(frame, fps, 6, FilmMotion.gentle, 36);
  const terminalDrop = ease(frame, [AI_ACTIONS.expand - 14, AI_ACTIONS.expand + 30], [0, 1]);
  const terminalY = lerp(300, 514, terminalDrop) + (1 - terminalIn) * 24;
  const terminalOut = linear(frame, [AI_ACTIONS.selectDay - 24, AI_ACTIONS.selectDay + 12], [1, 0]);

  const zoom = ease(frame, [AI_ACTIONS.expand + 30, AI_ACTIONS.models + 42], [1, 1.1]) - ease(frame, [AI_ACTIONS.settings, AI_ACTIONS.settings + 12], [0, 0.1]) + ease(frame, [AI_ACTIONS.balance, AI_ACTIONS.balance + 42], [0, 0.1]);
  const privacy = springAt(frame, fps, 276, FilmMotion.gentle, 36) * (1 - linear(frame, [AI_ACTIONS.settings, AI_ACTIONS.settings + 12], [0, 1]) + linear(frame, [AI_ACTIONS.balance, AI_ACTIONS.balance + 24], [0, 1]));
  const pressed = [AI_ACTIONS.selectDay, AI_ACTIONS.settings, AI_ACTIONS.viewHistory, AI_ACTIONS.historyDay, AI_ACTIONS.export, AI_ACTIONS.save, AI_ACTIONS.balance - 6].some((at) => frame >= at && frame < at + 6);

  return (
    <>
      <Camera scale={zoom} x={STAGE.width / 2} y={0}>
        <Wallpaper dim={0.16} />
        <MenuBar appName="Terminal" menus={['Shell', 'Edit', 'View', 'Window', 'Help']} />

        <TerminalWindow
          command={COMMAND}
          typed={COMMAND.length}
          frame={frame}
          x={(STAGE.width - TERMINAL.width) / 2}
          y={terminalY}
          width={TERMINAL.width}
          height={TERMINAL.height}
          opacity={clamp01(terminalIn) * terminalOut}
        />

        <Island
          reveal={reveal}
          height={islandHeightFor(MODULE_HEIGHT.ai)}
          wing={wing}
          left={<ProviderLogo provider="claude" size={20} />}
          right={<span className="font-rounded tabular text-[13px] font-semibold" data-active-tasks={3}>3</span>}
        >
          <IslandBody header={<StatusHeader task={build} progress={progress} />} active={TABS.ai}>
            <div className="absolute inset-0" style={modulePhase(moduleIn, 1, true)}>
              <div className="flex flex-col gap-4" style={{transform: `translateY(${-state.scroll}px)`}}>
                <AIModule
                    frame={frame}
                    rows={[
                      {task: build, progress, run: 401 + seconds, enter: rowEnter},
                      {task: taskById('test-07'), progress: 0.34 + seconds * 0.004, run: 533 + seconds},
                      {task: taskById('docs-02'), run: 194 + seconds},
                    ]}
                    trend={ease(frame, [AI_ACTIONS.expand + 20, AI_ACTIONS.expand + 80], [0, 1])}
                    todayTokens={aiModelTokenTotal}
                    heat={linear(frame, [AI_ACTIONS.expand + 24, AI_ACTIONS.expand + 88], [0, 1])}
                    todayLevel={3}
                    selection={state.selected ? 1 : 0}
                    selectedDay={state.selected ? <DailyModelUsageList /> : undefined}
                />
                <AIAnalyticsModule lowQuota={state.lowQuota} />
              </div>
            </div>
          </IslandBody>
        </Island>
        {frame >= AI_ACTIONS.collapse + 36 ? <CompactQuota /> : null}
        <Notch />
        {state.settings ? <UsageHistorySettings /> : null}
        {state.history ? <UsageHistoryWindow state={state} /> : null}

        {/* The connector establishes that task metadata enters through the local CLI. */}
        <div
          className="absolute"
          style={{
            left: STAGE.width / 2 - 0.75,
            top: 40,
            width: 1.5,
            height: 256,
            background: `linear-gradient(to top, ${alpha(color.claude, 0)}, ${alpha(color.claude, 0.9)})`,
            opacity: Math.min(linear(frame, [AI_ACTIONS.sent, AI_ACTIONS.sent + 8], [0, 1]), linear(frame, [AI_ACTIONS.sent + 18, AI_ACTIONS.sent + 44], [1, 0])),
            transform: `scaleY(${linear(frame, [AI_ACTIONS.sent, AI_ACTIONS.sent + 14], [0, 1])})`,
            transformOrigin: 'bottom',
          }}
        />
        <Cursor x={state.cursor.x} y={state.cursor.y} pressed={pressed ? 1 : 0} opacity={linear(frame, [AI_ACTIONS.collapse + 18, AI_ACTIONS.collapse + 36], [1, 0])} />
        <ClickRipple x={264 + AI_HEATMAP_TARGET.x} y={AI_HEATMAP_TARGET.y} progress={linear(frame, [AI_ACTIONS.selectDay, AI_ACTIONS.selectDay + 18], [0, 1])} />
      </Camera>

      <div data-feature="ai.privacy">
      <GlassPanel
        radius={18}
        opacity={clamp01(privacy)}
        className="flex items-center gap-[14px]"
        style={{left: STAGE.width / 2 - 330, bottom: 30, width: 660, padding: '16px 20px', transform: `translateY(${(1 - privacy) * 16}px)`}}
      >
        <ShieldCheck className="shrink-0" size={42} strokeWidth={1.8} color={color.green} />
        <div className="flex min-w-0 flex-col gap-[3px]">
          <div className="text-[20px] leading-[24px] font-semibold">{copy.privacy.title}</div>
          <div className="text-[20px] leading-[24px] font-semibold" style={{color: color.green}}>{copy.privacy.subtitle}</div>
          <div className="text-[11px] leading-[15px] text-label-2">{copy.privacy.detail}</div>
        </div>
      </GlassPanel>
      </div>
    </>
  );
};
