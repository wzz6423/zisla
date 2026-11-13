import type {CSSProperties, ReactNode} from 'react';
import {Check, ChevronDown, LoaderCircle} from 'lucide-react';
import {GlassPanel} from '../../components/Glass';
import {Cursor, ClickRipple} from '../../components/Cursor';
import {Caption, Headline} from '../../components/Caption';
import {MenuBar, Notch, Wallpaper} from '../../components/Desktop';
import {Island} from '../../components/Island';
import {IslandBody, StatusHeader, TABS} from '../../components/IslandChrome';
import {FilmMotion, linear, springAt} from '../../motion';
import {clamp01, color, islandHeightFor, white} from '../../theme';

export type TourStep = {id: string; title: string; caption: string; from: number; duration: number; features: readonly string[]};

export const tourAt = <T extends TourStep>(steps: readonly T[], frame: number, duration: number, nominalDuration: number) => {
  const position = Math.min(nominalDuration - 1, Math.max(0, frame * (nominalDuration - 1) / (duration - 1)));
  const step = steps.find((candidate) => position >= candidate.from && position < candidate.from + candidate.duration)!;
  return {step, frame: position - step.from};
};

export const TourSurface = ({title, caption, frame, fps, children}: {title: string; caption: string; frame: number; fps: number; children: ReactNode}) => (
  <>
    <Wallpaper dim={0.32} />
    <MenuBar />
    <Notch />
    <Headline lines={[title]} top={100} size={36} align="left" opacity={clamp01(springAt(frame, fps, 0, FilmMotion.title, 22))} />
    <GlassPanel radius={22} opacity={clamp01(springAt(frame, fps, 0, FilmMotion.pop, 22))} style={{left: 120, top: 174, width: 1040, height: 446}}>
      {children}
    </GlassPanel>
    <Caption text={caption} size={17} bottom={35} />
  </>
);

export const NativeModuleSurface = ({title, caption, module, height, children}: {title: string; caption: string; module: keyof typeof TABS; height: number; children: ReactNode}) => (
  <>
    <Wallpaper dim={0.22} />
    <MenuBar />
    <Island reveal={1} height={islandHeightFor(height)}>
      <IslandBody header={<StatusHeader />} active={TABS[module]}>{children}</IslandBody>
    </Island>
    <Notch />
    <Headline lines={[title]} top={Math.max(400, islandHeightFor(height) + 40)} size={34} />
    <Caption text={caption} size={17} bottom={35} />
  </>
);

export const TourHeading = ({title, children}: {title: string; children?: ReactNode}) => (
  <div className="flex shrink-0 items-center gap-[12px]" style={{height: 42}}>
    <div style={{fontSize: 23, fontWeight: 600, letterSpacing: '-0.02em'}}>{title}</div>
    <div className="flex-1" />
    {children}
  </div>
);

export const TourAction = ({label, active = false, busy = false}: {label: string; active?: boolean; busy?: boolean}) => (
  <div className="flex shrink-0 items-center justify-center gap-[6px]" style={{padding: '8px 12px', borderRadius: 7, background: active ? color.blue : color.fillControl, fontSize: 14, fontWeight: 500, lineHeight: '18px'}}>
    {busy ? <LoaderCircle size={15} /> : null}
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

export const TourResult = ({children, pending = false}: {children: ReactNode; pending?: boolean}) => (
  <div className="flex shrink-0 items-center gap-[8px]" style={{fontSize: 16, lineHeight: '22px', color: pending ? color.secondary : color.green}}>
    {pending ? <LoaderCircle size={16} /> : <Check size={17} strokeWidth={2.4} />}
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

export const TourPointer = ({frame, at, x, y}: {frame: number; at: number; x: number; y: number}) => (
  <>
    <ClickRipple x={x} y={y} progress={linear(frame, [at, at + 22], [0, 1])} />
    <Cursor x={x + 45 * (1 - clamp01((frame - at + 24) / 24))} y={y + 34 * (1 - clamp01((frame - at + 24) / 24))} pressed={frame >= at && frame < at + 6 ? 1 : 0} opacity={Math.min(linear(frame, [at - 30, at - 18], [0, 1]), linear(frame, [at + 26, at + 42], [1, 0]))} />
  </>
);
