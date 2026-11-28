import type {CSSProperties, ReactNode} from 'react';
import {Check, ChevronDown, LoaderCircle} from 'lucide-react';
import {GlassPanel} from '../../components/Glass';
import {Cursor, ClickRipple} from '../../components/Cursor';
import {Caption, Headline} from '../../components/Caption';
import {MenuBar, Notch, Wallpaper} from '../../components/Desktop';
import {Island, modulePhase} from '../../components/Island';
import {IslandBody, StatusHeader, TABS} from '../../components/IslandChrome';
import {ease, easeOutAt, FilmMotion, linear, springAt, ZislaMotion} from '../../motion';
import {clamp01, color, islandHeightFor, lerp, white} from '../../theme';

export type TourStep = {id: string; title: string; caption: string; from: number; duration: number; features: readonly string[]};

export const tourAt = <T extends TourStep>(steps: readonly T[], frame: number, duration: number, nominalDuration: number) => {
  const position = Math.min(nominalDuration - 1, Math.max(0, frame * (nominalDuration - 1) / (duration - 1)));
  const step = steps.find((candidate) => position >= candidate.from && position < candidate.from + candidate.duration)!;
  return {step, frame: position - step.from};
};

export const TourSurface = ({title, caption, frame, fps, children}: {title: string; caption: string; frame: number; fps: number; children: ReactNode}) => {
  const titleIn = clamp01(springAt(frame, fps, 0, FilmMotion.title, 22));
  const panelIn = clamp01(springAt(frame, fps, 0, FilmMotion.pop, 22));
  return (
    <>
      <Wallpaper dim={0.32} />
      <MenuBar />
      <Notch />
      <Headline lines={[title]} top={100} size={36} align="left" opacity={titleIn} />
      <GlassPanel radius={22} opacity={panelIn} style={{left: 120, top: 174, width: 1040, height: 446, transform: `translateY(${(1 - panelIn) * 8}px)`}}>
        {children}
      </GlassPanel>
      <Caption text={caption} size={17} bottom={35} opacity={easeOutAt(frame, [0, 12], [0, 1])} />
    </>
  );
};

type NativeModuleSurfaceProps = {
  title: string;
  caption: string;
  module: keyof typeof TABS;
  height: number;
  // Optional transition context so consecutive island tabs morph height, lens, and content smoothly.
  fromModule?: keyof typeof TABS;
  fromHeight?: number;
  frame?: number;
  fps?: number;
  reveal?: number;
  children: ReactNode;
};

export const NativeModuleSurface = ({
  title,
  caption,
  module,
  height,
  fromModule,
  fromHeight,
  frame,
  fps = 60,
  reveal = 1,
  children,
}: NativeModuleSurfaceProps) => {
  const morph = frame !== undefined && (fromHeight !== undefined || fromModule !== undefined);
  const resizeProgress = morph ? clamp01(springAt(frame, fps, 0, ZislaMotion.surfaceResize, 20)) : 1;
  const tabProgress = morph ? clamp01(springAt(frame, fps, 0, ZislaMotion.moduleSwitch, 18)) : 1;
  const contentProgress = morph ? clamp01(frame / 12) : 1;
  const currentHeight = islandHeightFor(fromHeight !== undefined ? lerp(fromHeight, height, resizeProgress) : height);
  const targetTab = TABS[module];
  const sourceTab = fromModule !== undefined ? TABS[fromModule] : targetTab;
  const activeTab = lerp(sourceTab, targetTab, tabProgress);
  const direction: 1 | -1 = targetTab >= sourceTab ? 1 : -1;
  const labelOpacity = frame !== undefined ? easeOutAt(frame, [0, 10], [0, 1]) : 1;

  return (
    <>
      <Wallpaper dim={0.22} />
      <MenuBar />
      <Island reveal={reveal} height={currentHeight}>
        <IslandBody header={<StatusHeader />} active={activeTab}>
          {morph ? (
            <div className="absolute inset-0" style={modulePhase(contentProgress, direction, true)}>
              {children}
            </div>
          ) : children}
        </IslandBody>
      </Island>
      <Notch />
      <Headline lines={[title]} top={Math.max(400, currentHeight + 40)} size={34} opacity={labelOpacity} />
      <Caption text={caption} size={17} bottom={35} opacity={labelOpacity} />
    </>
  );
};

export const TourHeading = ({title, children}: {title: string; children?: ReactNode}) => (
  <div className="flex shrink-0 items-center gap-[12px]" style={{height: 42}}>
    <div style={{fontSize: 23, fontWeight: 600, letterSpacing: '-0.02em'}}>{title}</div>
    <div className="flex-1" />
    {children}
  </div>
);

export const TourAction = ({label, active = false, busy = false, spinFrame = 0}: {label: string; active?: boolean; busy?: boolean; spinFrame?: number}) => (
  <div className="flex shrink-0 items-center justify-center gap-[6px]" style={{padding: '8px 12px', borderRadius: 7, background: active ? color.blue : color.fillControl, fontSize: 14, fontWeight: 500, lineHeight: '18px'}}>
    {busy ? <LoaderCircle size={15} style={{transform: `rotate(${spinFrame * 10}deg)`}} /> : null}
    {label}
  </div>
);

export const TourSelect = ({value}: {value: string}) => <div className="flex items-center gap-[10px]" style={{padding: '7px 10px', borderRadius: 6, background: color.fillControl, fontSize: 14}}>{value}<ChevronDown size={12} color={color.secondary} /></div>;

export const TourToggle = ({label, on}: {label: string; on: boolean}) => (
  <div className="flex items-center gap-[12px]" style={{fontSize: 15, lineHeight: '20px'}}>
    <div className="flex-1">{label}</div>
    <div style={{width: 34, height: 20, borderRadius: 10, padding: 2, background: on ? color.blue : white(0.2)}}>
      <div style={{width: 16, height: 16, borderRadius: 8, background: '#fff', transform: `translateX(${on ? 14 : 0}px)`}} />
    </div>
  </div>
);

export const TourResult = ({children, pending = false, spinFrame = 0}: {children: ReactNode; pending?: boolean; spinFrame?: number}) => (
  <div className="flex shrink-0 items-center gap-[8px]" style={{fontSize: 16, lineHeight: '22px', color: pending ? color.secondary : color.green}}>
    {pending ? <LoaderCircle size={16} style={{transform: `rotate(${spinFrame * 10}deg)`}} /> : <Check size={17} strokeWidth={2.4} />}
    {children}
  </div>
);

export const TourField = ({label, value}: {label: string; value: string}) => (
  <div className="flex items-center gap-[18px]" style={{fontSize: 15}}>
    <span className="shrink-0" style={{width: 100, color: color.secondary}}>{label}</span>
    <div className="flex-1" style={{padding: '8px 10px', borderRadius: 6, background: color.fillControl, border: '1px solid transparent'}}>{value}</div>
  </div>
);

export const TourCard = ({children, style}: {children: ReactNode; style?: CSSProperties}) => <div style={{padding: 16, borderRadius: 10, background: color.fillCard, border: `1px solid ${color.strokeCard}`, ...style}}>{children}</div>;

export const TourPointer = ({frame, at, x, y}: {frame: number; at: number; x: number; y: number}) => {
  const approach = easeOutAt(frame, [at - 24, at], [0, 1]);
  return (
    <>
      <ClickRipple x={x} y={y} progress={linear(frame, [at, at + 22], [0, 1])} />
      <Cursor x={x + 45 * (1 - approach)} y={y + 34 * (1 - approach)} pressed={frame >= at && frame < at + 6 ? 1 : 0} opacity={Math.min(linear(frame, [at - 30, at - 18], [0, 1]), linear(frame, [at + 26, at + 42], [1, 0]))} />
    </>
  );
};

type PointerAction = {at: number; x: number; y: number};

export const TourPointerTrack = ({frame, actions}: {frame: number; actions: readonly [PointerAction, ...PointerAction[]]}) => {
  const first = actions[0];
  const last = actions[actions.length - 1]!;
  const approach = easeOutAt(frame, [first.at - 24, first.at], [0, 1]);
  let x = first.x + 45 * (1 - approach);
  let y = first.y + 34 * (1 - approach);
  for (let index = 1; index < actions.length; index++) {
    const previous = actions[index - 1]!;
    const next = actions[index]!;
    if (frame < previous.at) break;
    const start = Math.max(previous.at + 6, next.at - 24);
    x = ease(frame, [start, next.at], [previous.x, next.x]);
    y = ease(frame, [start, next.at], [previous.y, next.y]);
    if (frame < next.at) break;
  }
  return <>
    {actions.map((action) => <ClickRipple key={action.at} x={action.x} y={action.y} progress={linear(frame, [action.at, action.at + 22], [0, 1])} />)}
    <Cursor x={x} y={y} pressed={actions.some((action) => frame >= action.at && frame < action.at + 6) ? 1 : 0} opacity={Math.min(linear(frame, [first.at - 30, first.at - 18], [0, 1]), linear(frame, [last.at + 26, last.at + 42], [1, 0]))} />
  </>;
};
