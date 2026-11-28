import type {ReactNode} from 'react';
import {Clock} from 'lucide-react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {Caption, Headline} from '../components/Caption';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {Island} from '../components/Island';
import {IslandBody, StatusHeader, TABS, formatTime} from '../components/IslandChrome';
import {BackgroundSoundsTourModule, BatteryTourModule, CleanupTourModule, CompactFocusControls, FocusTourModule, KeyboardTourModule, MixerTourModule, PresenterTourModule, ScreenCleaningCover, SystemHistoryTourModule, batteryTourAt, focusTourAt, keyboardTourAt, systemHistoryTourAt} from '../modules/tour/DesktopTourModule';
import {NativeModuleSurface, TourPointer, TourSurface, TourPointerTrack, tourAt} from '../modules/tour/TourSurface';
import {ZislaMotion, easeOutAt, springAt} from '../motion';
import {clamp01, color, islandHeightFor} from '../theme';

export const DESKTOP_TOUR_DURATION = 1140;
export const DESKTOP_TOUR_STEPS = [
  {id: 'mixer', title: 'Per-app volume mixer.', caption: 'Balance active audio sources independently or mute with one click', from: 0, duration: 110, features: ['volumeMixer']},
  {id: 'keyboard', title: 'Mechanical acoustics & local input stats.', caption: '20 switch voices · Custom packs · Typing & voice dashboard · Key heatmap', from: 110, duration: 135, features: ['keyboardSound']},
  {id: 'focus', title: 'Pomodoro, named timers, and keep-awake.', caption: 'Multiple countdowns · Compact notch controls · Prevent sleep', from: 245, duration: 170, features: ['toolbox', 'focus', 'namedCountdown', 'powerAssertions']},
  {id: 'sounds', title: 'System background sounds.', caption: 'Built-in ambient audio that pauses automatically on lock or sleep', from: 415, duration: 90, features: ['backgroundSounds']},
  {id: 'cleaning', title: 'Clean screen, keys, and junk in one place.', caption: 'Blackout cover · F1–F12 key lock · Clean Junk shortcut', from: 505, duration: 180, features: ['screenCleaning', 'keyboardCleaning', 'trash']},
  {id: 'presenter', title: 'Teleprompter & camera mirror.', caption: 'Smooth hover-controlled script scroll · Instant mirrored check', from: 685, duration: 100, features: ['teleprompter', 'cameraMirror']},
  {id: 'system', title: 'Chip-level telemetry & minute history.', caption: 'CPU, GPU, RAM, disk, fans & network — browse or export to .xlsx', from: 785, duration: 150, features: ['system', 'systemHistory']},
  {id: 'battery', title: 'Live power flow & battery health.', caption: 'Adapter wattage split · Charge to 100% · Automatic power modes', from: 935, duration: 110, features: ['battery', 'chargeToFull', 'automaticPowerMode']},
  {id: 'cleanup', title: 'Transparent disk cleanup.', caption: 'Caches, duplicate apps & orphan AI workspaces — review before Trash', from: 1045, duration: 95, features: ['systemCleanup']},
] as const;

export const desktopTourAt = (frame: number, duration = DESKTOP_TOUR_DURATION) => tourAt(DESKTOP_TOUR_STEPS, frame, duration, DESKTOP_TOUR_DURATION);

const DesktopWindowSurface = ({title, caption, width, height, scale = 1, frame = 30, children}: {title: string; caption: string; width: number; height: number; scale?: number; frame?: number; children: ReactNode}) => {
  const labelIn = easeOutAt(frame, [0, 10], [0, 1]);
  return <>
    <Wallpaper dim={0.28} />
    <MenuBar appName="zisla" />
    <Notch />
    <Headline lines={[title]} top={51} size={32} opacity={labelIn} />
    <div className="absolute" style={{left: (1280 - width * scale) / 2, top: 103, width, height, transform: `scale(${scale})`, transformOrigin: 'top left'}}>{children}</div>
    <Caption text={caption} size={17} bottom={22} opacity={labelIn} />
  </>;
};

const FocusSurface = ({frame, fps, title, caption}: {frame: number; fps: number; title: string; caption: string}) => {
  const state = focusTourAt(frame);
  const collapse = clamp01(springAt(frame, fps, 50, ZislaMotion.islandRecycle, 10));
  const reopen = clamp01(springAt(frame, fps, 128, ZislaMotion.islandReveal, 14));
  const reveal = frame >= 128 ? reopen : 1 - collapse;
  const status = state.completed ? 'Focus completed · Tea 02:58 still running' : state.finished ? 'Rest ready · 5 minutes' : state.paused ? 'Focus paused · Remaining time retained' : frame < 24 ? 'Pomodoro + independent named countdowns' : frame < 34 ? 'Focus running · Tea 03:00' : frame < 44 ? 'Display awake' : 'Display awake · Idle sleep prevented';
  return <>
    <Wallpaper dim={0.22} />
    <MenuBar />
    <Island reveal={reveal} height={islandHeightFor(136)} wing={92} left={<div className="flex items-center gap-[6px]" style={{fontSize: 12}}><Clock size={13} /><span className="font-rounded tabular">{formatTime(Math.ceil(state.remaining))}</span></div>} right={<CompactFocusControls frame={frame} />}>
      {!state.compact ? <IslandBody header={<StatusHeader />} active={TABS.toolbox}><FocusTourModule frame={frame} /></IslandBody> : null}
    </Island>
    <Notch />
    {state.compact ? <TourPointerTrack frame={frame} actions={[{at: 66, x: 761, y: 17}, {at: 90, x: 761, y: 17}]} /> : null}
    <div data-focus-status className="absolute inset-x-0" style={{top: state.compact ? 97 : 324, textAlign: 'center', color: state.completed ? color.green : color.secondary, fontSize: 13}}>{status}</div>
    <Headline lines={[title]} top={400} size={34} opacity={easeOutAt(frame, [0, 10], [0, 1])} />
    <Caption text={caption} size={17} bottom={35} opacity={easeOutAt(frame, [0, 10], [0, 1])} />
  </>;
};

export const SceneDesktopTools = ({duration = DESKTOP_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = desktopTourAt(frame, duration);
  if (state.step.id === 'mixer') {
    return (
      <NativeModuleSurface title={state.step.title} caption={state.frame >= 72 ? 'Safari at 30% · Music muted' : state.step.caption} module="mixer" height={152} frame={state.frame} fps={fps}>
        <MixerTourModule frame={state.frame} />
      </NativeModuleSurface>
    );
  }
  if (state.step.id === 'keyboard') {
    const keyboard = keyboardTourAt(state.frame);
    if (keyboard.phase === 'settings') return <DesktopWindowSurface title={state.step.title} caption="20 voices · Installed custom pack: BCP (Suit80)" width={960} height={680} scale={0.8} frame={state.frame}><GlassPanel radius={12} style={{inset: 0}}><KeyboardTourModule frame={state.frame} /></GlassPanel></DesktopWindowSurface>;
    const dashReveal = clamp01(springAt(state.frame, fps, 54, ZislaMotion.islandReveal, 16));
    return <><Wallpaper dim={0.22} /><MenuBar /><Island reveal={dashReveal} height={islandHeightFor(420)}><IslandBody header={<StatusHeader />} active={TABS.keyboard}><KeyboardTourModule frame={state.frame} /></IslandBody></Island><Notch /><Headline lines={[state.step.title]} top={590} size={29} /><Caption text={state.frame >= 88 ? 'Typing stats updated · 14 characters added' : 'Key presses update the local dashboard'} size={15} bottom={27} /></>;
  }
  if (state.step.id === 'focus') return <FocusSurface frame={state.frame} fps={fps} title={state.step.title} caption={state.step.caption} />;
  if (state.step.id === 'cleaning') {
    const cleaningFrame = state.frame;
    if (cleaningFrame >= 24 && cleaningFrame < 54) return <ScreenCleaningCover frame={cleaningFrame} />;
    const cleaning = cleaningFrame >= 74 && cleaningFrame < 136;
    const noticeIn = cleaning ? easeOutAt(cleaningFrame, [74, 80], [0, 1]) : 0;
    return <NativeModuleSurface title={state.step.title} caption={cleaning ? 'Keyboard input blocked · Includes F1–F12' : cleaningFrame >= 136 ? 'Screen restored · Keyboard input resumed' : state.step.caption} module="toolbox" height={136} frame={cleaningFrame < 24 ? cleaningFrame : undefined} fps={fps}><FocusTourModule frame={169} />{cleaning ? <div data-keyboard-cleaning-notice className="absolute flex items-center justify-center gap-[8px]" style={{right: 0, top: 94, width: 248, height: 40, borderRadius: 8, background: '#28282e', fontSize: 11, opacity: noticeIn, transform: `translateY(${(1 - noticeIn) * 6}px)`}}><span>Keyboard input blocked</span><span style={{color: color.blue}}>End cleaning</span><TourPointer frame={cleaningFrame} at={130} x={218} y={20} /></div> : cleaningFrame < 24 ? <TourPointer frame={cleaningFrame} at={18} x={370} y={68} /> : cleaningFrame < 74 ? <TourPointer frame={cleaningFrame} at={68} x={626} y={68} /> : null}</NativeModuleSurface>;
  }
  if (state.step.id === 'system') {
    const system = systemHistoryTourAt(state.frame);
    if (system.phase === 'live') return <NativeModuleSurface title={state.step.title} caption={state.step.caption} module="cpu" height={295} frame={state.frame} fps={fps}><SystemHistoryTourModule frame={state.frame} globalFrame={globalFrom + frame} /></NativeModuleSurface>;
    return <DesktopWindowSurface title={state.step.title} caption={system.exported ? 'System history.xlsx saved · All recorded readings included' : state.step.caption} width={720} height={560} scale={0.95} frame={state.frame - 36}><SystemHistoryTourModule frame={state.frame} globalFrame={globalFrom + frame} /></DesktopWindowSurface>;
  }
  if (state.step.id === 'battery') {
    const battery = batteryTourAt(state.frame);
    const islandReveal = clamp01(springAt(state.frame, fps, 0, ZislaMotion.islandReveal, 16));
    return <><Wallpaper dim={0.22} /><MenuBar /><Island reveal={islandReveal} height={islandHeightFor(460)}><IslandBody header={<StatusHeader />} active={TABS.cpu}><BatteryTourModule frame={state.frame} /></IslandBody></Island><Notch /><Headline lines={[state.step.title]} top={625} size={26} opacity={easeOutAt(state.frame, [0, 10], [0, 1])} /><Caption text={battery.onBattery ? battery.lowPower ? 'Battery supplies the Mac · Low power mode applied' : 'Battery supplies the Mac · Automatic power mode' : battery.fullyCharged ? battery.lowPower ? 'Fully charged snapshot · Low power mode applied' : 'Fully charged snapshot · Adapter powers this Mac' : battery.chargingRequested ? 'Charge to 100% requested' : state.step.caption} size={15} bottom={18} /></>;
  }
  if (state.step.id === 'cleanup') return <DesktopWindowSurface title={state.step.title} caption={state.step.caption} width={560} height={430} scale={1.15} frame={state.frame}><CleanupTourModule frame={state.frame} /></DesktopWindowSurface>;
  return (
    <TourSurface title={state.step.title} caption={state.step.caption} frame={state.frame} fps={fps}>
      {state.step.id === 'sounds' ? <BackgroundSoundsTourModule frame={state.frame} /> : null}
      {state.step.id === 'presenter' ? <PresenterTourModule frame={state.frame} /> : null}
    </TourSurface>
  );
};
