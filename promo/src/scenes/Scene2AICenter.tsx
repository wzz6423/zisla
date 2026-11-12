import {ShieldCheck} from 'lucide-react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {Island, modulePhase} from '../components/Island';
import {CompactPercent, IslandBody, ProviderLogo, StatusHeader, TABS} from '../components/IslandChrome';
import {Camera} from '../components/Stage';
import {TerminalLine, TerminalWindow, typedChars} from '../components/Terminal';
import {aiTasks, brands, copy} from '../content';
import type {AiTask} from '../content';
import {AIModule} from '../modules/AIModule';
import {AIAnalyticsModule, aiModelTokenTotal} from '../modules/AIAnalyticsModule';
import {FilmMotion, ZislaMotion, ease, linear, springAt, track} from '../motion';
import {MODULE_HEIGHT, STAGE, alpha, clamp01, color, islandHeightFor, lerp, white} from '../theme';

const COMMAND = 'zislactl update --id build-01 --provider claude --title "Refactoring core" --progress 68';
const FOLLOW_UPS = [
  {at: 306, text: 'zislactl update --id build-01 --provider claude --title "Refactoring core" --progress 74'},
  {at: 368, text: 'zislactl usage --provider claude --input-tokens 31200 --output-tokens 16800'},
  {at: 426, text: 'zislactl update --id build-01 --provider claude --title "Refactoring core" --progress 81'},
] as const;

const TYPE_START = 24;
const TYPE_SPEED = 48;
const SENT_AT = 140;
const WING_AT = 146;
const EXPAND_AT = 204;
const MODELS_AT = 420;
const BALANCE_AT = 552;
const PRIVACY_AT = 424;

const TERMINAL = {width: 760, height: 168};

const taskById = (id: string): AiTask => aiTasks.find((task) => task.id === id) ?? (aiTasks[0] as AiTask);

export const Scene2AICenter = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const seconds = frame / fps;

  const build = taskById('build-01');
  const progress = track(frame, [
    [0, 0.68],
    [312, 0.68],
    [334, 0.74],
    [432, 0.74],
    [454, 0.81],
  ]);
  const todayTokens = track(frame, [
    [0, 553_000],
    [374, 553_000],
    [398, aiModelTokenTotal],
  ]);

  const reveal = springAt(frame, fps, EXPAND_AT, ZislaMotion.islandReveal, 42);
  const wing = lerp(0, 40, clamp01(springAt(frame, fps, WING_AT, ZislaMotion.notice, 30)));
  const moduleIn = clamp01((frame - EXPAND_AT - 8) / 24);
  const rowEnter = springAt(frame, fps, EXPAND_AT + 14, ZislaMotion.surfaceResize, 40);

  const terminalIn = springAt(frame, fps, 6, FilmMotion.gentle, 36);
  const terminalDrop = ease(frame, [EXPAND_AT - 14, EXPAND_AT + 30], [0, 1]);
  const terminalY = lerp(300, 514, terminalDrop) + (1 - terminalIn) * 24;
  const terminalOut = linear(frame, [MODELS_AT - 12, MODELS_AT + 16], [1, 0]);

  const zoom = ease(frame, [250, 470], [1, 1.1]);

  const scroll = track(frame, [
    [MODELS_AT, 0],
    [MODELS_AT + 30, 200],
    [BALANCE_AT, 200],
    [BALANCE_AT + 30, MODULE_HEIGHT.ai],
  ]);
  const privacy = springAt(frame, fps, PRIVACY_AT, FilmMotion.gentle, 36);

  return (
    <>
      <Camera scale={zoom} x={STAGE.width / 2} y={0}>
        <Wallpaper dim={0.16} />
        <MenuBar appName="Terminal" menus={['Shell', 'Edit', 'View', 'Window', 'Help']} />

        <TerminalWindow
          command={COMMAND}
          typed={typedChars(frame, TYPE_START, COMMAND.length, TYPE_SPEED, fps)}
          frame={frame}
          x={(STAGE.width - TERMINAL.width) / 2}
          y={terminalY}
          width={TERMINAL.width}
          height={TERMINAL.height}
          opacity={clamp01(terminalIn) * terminalOut}
          output={FOLLOW_UPS.map((line) =>
            frame >= line.at ? (
              <TerminalLine key={line.at} tint={white(0.92)}>
                <span style={{color: color.green}}>➜</span>
                <span style={{color: color.cyan}}> ~ </span>
                {line.text.slice(0, Math.floor(typedChars(frame, line.at, line.text.length, 150, fps)))}
              </TerminalLine>
            ) : null,
          )}
        />

        <Island
          reveal={reveal}
          height={islandHeightFor(MODULE_HEIGHT.ai)}
          wing={wing}
          left={<ProviderLogo provider="claude" size={20} />}
          right={<CompactPercent value={progress} />}
          progress={frame >= WING_AT ? {value: progress, tint: brands.claude.color} : undefined}
        >
          <IslandBody header={<StatusHeader task={build} progress={progress} />} active={TABS.ai}>
            <div className="absolute inset-0" style={modulePhase(moduleIn, 1, true)}>
              <div style={{transform: `translateY(${-scroll}px)`}}>
                <div className="relative" style={{height: MODULE_HEIGHT.ai}}>
                  <AIModule
                    frame={frame}
                    rows={[
                      {task: build, progress, run: 401 + seconds, enter: rowEnter},
                      {task: taskById('test-07'), progress: 0.34 + seconds * 0.004, run: 533 + seconds},
                      {task: taskById('docs-02'), run: 194 + seconds},
                    ]}
                    trend={ease(frame, [EXPAND_AT + 20, EXPAND_AT + 96], [0, 1])}
                    todayTokens={todayTokens}
                    heat={linear(frame, [EXPAND_AT + 40, EXPAND_AT + 130], [0, 1])}
                    todayLevel={frame >= 386 ? 3 : 2}
                    selection={linear(frame, [340, 356], [0, 1])}
                  />
                </div>
                <AIAnalyticsModule />
              </div>
            </div>
          </IslandBody>
        </Island>
        <Notch />

        {/* The connector establishes that task metadata enters through the local CLI. */}
        <div
          className="absolute"
          style={{
            left: STAGE.width / 2 - 0.75,
            top: 40,
            width: 1.5,
            height: 256,
            background: `linear-gradient(to top, ${alpha(color.claude, 0)}, ${alpha(color.claude, 0.9)})`,
            opacity: Math.min(linear(frame, [SENT_AT, SENT_AT + 8], [0, 1]), linear(frame, [SENT_AT + 18, SENT_AT + 44], [1, 0])),
            transform: `scaleY(${linear(frame, [SENT_AT, SENT_AT + 14], [0, 1])})`,
            transformOrigin: 'bottom',
          }}
        />
      </Camera>

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
    </>
  );
};
