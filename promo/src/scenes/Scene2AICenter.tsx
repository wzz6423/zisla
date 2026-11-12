import {Check, ShieldCheck, X} from 'lucide-react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {Island, modulePhase} from '../components/Island';
import {CompactPercent, IslandBody, ProviderLogo, StatusHeader, TABS} from '../components/IslandChrome';
import {Camera} from '../components/Stage';
import {TerminalLine, TerminalWindow, typedChars} from '../components/Terminal';
import {aiTasks, brands, copy} from '../content';
import type {AiTask} from '../content';
import {AIModule} from '../modules/AIModule';
import {FilmMotion, ZislaMotion, ease, linear, springAt, track} from '../motion';
import {MODULE_HEIGHT, STAGE, alpha, black, clamp01, color, islandHeightFor, lerp, white} from '../theme';

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
const PRIVACY_AT = 480;

const TERMINAL = {width: 760, height: 168};

const READS = ['Task state', 'Progress', 'Token counts', 'Provider'];
const NEVER = ['Prompts', 'Answer bodies'];

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
    [398, 601_000],
  ]);

  const reveal = springAt(frame, fps, EXPAND_AT, ZislaMotion.islandReveal, 42);
  const wing = lerp(0, 40, clamp01(springAt(frame, fps, WING_AT, ZislaMotion.notice, 30)));
  const moduleIn = clamp01((frame - EXPAND_AT - 8) / 24);
  const rowEnter = springAt(frame, fps, EXPAND_AT + 14, ZislaMotion.surfaceResize, 40);

  const terminalIn = springAt(frame, fps, 6, FilmMotion.gentle, 36);
  const terminalDrop = ease(frame, [EXPAND_AT - 14, EXPAND_AT + 30], [0, 1]);
  const terminalY = lerp(300, 514, terminalDrop) + (1 - terminalIn) * 24;

  const zoom = ease(frame, [250, 470], [1, 1.1]);

  const dim = linear(frame, [PRIVACY_AT, PRIVACY_AT + 34], [0, 1]);
  const shield = springAt(frame, fps, PRIVACY_AT + 14, FilmMotion.pop, 40);
  const title = springAt(frame, fps, PRIVACY_AT + 34, FilmMotion.title, 36);
  const subtitle = springAt(frame, fps, PRIVACY_AT + 52, FilmMotion.title, 36);
  const detail = linear(frame, [PRIVACY_AT + 150, PRIVACY_AT + 176], [0, 1]);

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
          opacity={clamp01(terminalIn)}
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
          </IslandBody>
        </Island>
        <Notch />

        {/* 命令送出的一瞬，在终端与刘海之间拉一条提示线，交代数据是从本地 CLI 进来的 */}
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

      <div
        className="absolute inset-0"
        style={{
          background: black(0.74 * dim),
          backdropFilter: `blur(${14 * dim}px)`,
          WebkitBackdropFilter: `blur(${14 * dim}px)`,
        }}
      />
      {frame >= PRIVACY_AT ? (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <div
            className="flex items-center justify-center rounded-full"
            style={{
              width: 92,
              height: 92,
              background: alpha(color.green, 0.14),
              border: `1px solid ${alpha(color.green, 0.5)}`,
              boxShadow: `0 0 ${50 + 14 * Math.sin(frame * 0.08)}px ${alpha(color.green, 0.34)}`,
              opacity: clamp01(shield),
              transform: `scale(${0.6 + 0.4 * shield})`,
            }}
          >
            <ShieldCheck size={46} strokeWidth={1.8} color={color.green} />
          </div>
          <div
            className="font-semibold"
            style={{
              marginTop: 26,
              fontSize: 54,
              lineHeight: '60px',
              letterSpacing: '-0.025em',
              opacity: clamp01(title),
              transform: `translateY(${(1 - title) * 16}px)`,
            }}
          >
            {copy.privacy.title}
          </div>
          <div
            className="font-semibold"
            style={{
              marginTop: 4,
              fontSize: 54,
              lineHeight: '60px',
              letterSpacing: '-0.025em',
              color: color.green,
              opacity: clamp01(subtitle),
              transform: `translateY(${(1 - subtitle) * 16}px)`,
            }}
          >
            {copy.privacy.subtitle}
          </div>
          <div className="flex items-center gap-[8px]" style={{marginTop: 30}}>
            {READS.map((label, index) => {
              const enter = springAt(frame, fps, PRIVACY_AT + 78 + index * 7, FilmMotion.pop, 30);
              return (
                <div
                  key={label}
                  className="flex items-center gap-[6px] rounded-full px-[12px] py-[6px] text-[13px] font-medium"
                  style={{
                    background: white(0.1),
                    border: `1px solid ${white(0.14)}`,
                    opacity: clamp01(enter),
                    transform: `scale(${0.86 + 0.14 * enter})`,
                  }}
                >
                  <Check size={13} strokeWidth={3} color={color.green} />
                  {label}
                </div>
              );
            })}
            {NEVER.map((label, index) => {
              const enter = springAt(frame, fps, PRIVACY_AT + 112 + index * 8, FilmMotion.pop, 30);
              const strike = linear(frame, [PRIVACY_AT + 126 + index * 8, PRIVACY_AT + 142 + index * 8], [0, 1]);
              return (
                <div
                  key={label}
                  className="relative flex items-center gap-[6px] rounded-full px-[12px] py-[6px] text-[13px] font-medium"
                  style={{
                    background: alpha(color.red, 0.12),
                    border: `1px solid ${alpha(color.red, 0.42)}`,
                    color: white(0.62),
                    opacity: clamp01(enter),
                    transform: `scale(${0.86 + 0.14 * enter})`,
                  }}
                >
                  <X size={13} strokeWidth={3} color={color.red} />
                  {label}
                  <div
                    className="absolute"
                    style={{left: 30, right: 12, top: '50%', height: 1.5, background: color.red, transform: `scaleX(${strike})`, transformOrigin: 'left'}}
                  />
                </div>
              );
            })}
          </div>
          <div className="text-center text-[14px] leading-[20px] text-label-2" style={{marginTop: 22, width: 620, opacity: detail}}>
            {copy.privacy.detail}
          </div>
        </div>
      ) : null}
    </>
  );
};
