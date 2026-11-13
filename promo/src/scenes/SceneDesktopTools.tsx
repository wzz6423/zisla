import type {ReactNode} from 'react';
import {Clock} from 'lucide-react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {Caption, Headline} from '../components/Caption';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {Island} from '../components/Island';
import {IslandBody, StatusHeader, TABS, formatTime} from '../components/IslandChrome';
import {BackgroundSoundsTourModule, BatteryTourModule, CleanupTourModule, CompactFocusControls, FocusTourModule, KeyboardTourModule, MixerTourModule, PresenterTourModule, ScreenCleaningCover, SystemHistoryTourModule, batteryTourAt, focusTourAt, keyboardTourAt, systemHistoryTourAt} from '../modules/tour/DesktopTourModule';
import {NativeModuleSurface, TourPointer, TourSurface, tourAt} from '../modules/tour/TourSurface';
import {color, islandHeightFor} from '../theme';

export const DESKTOP_TOUR_DURATION = 1620;
export const DESKTOP_TOUR_STEPS = [
  {id: 'mixer', title: 'Give every app its own volume.', caption: 'Adjust playing apps independently and mute only the one you choose.', from: 0, duration: 180, features: ['volumeMixer']},
  {id: 'keyboard', title: 'Make typing sound and feel your own.', caption: 'Twenty voices, local typing trends and a per-key heatmap.', from: 180, duration: 180, features: ['keyboardSound']},
  {id: 'focus', title: 'Focus, with controls right at hand.', caption: 'Start · Pause · Continue · Reset · Keep awake', from: 360, duration: 240, features: ['toolbox', 'focus', 'powerAssertions']},
  {id: 'sounds', title: 'Choose the sound around your work.', caption: 'Background sounds stop on lock, screen saver or sleep.', from: 600, duration: 120, features: ['backgroundSounds']},
  {id: 'cleaning', title: 'A moment to clean the screen and keys.', caption: 'Cover the screen or block keyboard input, then return to work.', from: 720, duration: 150, features: ['screenCleaning', 'keyboardCleaning', 'trash']},
  {id: 'presenter', title: 'Read your script. Check your camera.', caption: 'Scroll · Pause · Close the camera', from: 870, duration: 150, features: ['teleprompter', 'cameraMirror']},
  {id: 'system', title: 'See your Mac’s work over time.', caption: 'Live metrics · History · Spreadsheet export', from: 1020, duration: 270, features: ['system', 'systemHistory']},
  {id: 'battery', title: 'See where the power goes.', caption: 'Charge to 100% · Health · Automatic power modes', from: 1290, duration: 180, features: ['battery', 'chargeToFull', 'automaticPowerMode']},
  {id: 'cleanup', title: 'Review it. Move it to Trash.', caption: 'Keep review items. Confirm only the selected cleanup.', from: 1470, duration: 150, features: ['systemCleanup']},
] as const;

export const desktopTourAt = (frame: number, duration = DESKTOP_TOUR_DURATION) => tourAt(DESKTOP_TOUR_STEPS, frame, duration, DESKTOP_TOUR_DURATION);

const DesktopWindowSurface = ({title, caption, width, height, scale = 1, children}: {title: string; caption: string; width: number; height: number; scale?: number; children: ReactNode}) => <>
  <Wallpaper dim={0.28} />
  <MenuBar appName="zisla" />
  <Notch />
  <Headline lines={[title]} top={51} size={32} />
  <div className="absolute" style={{left: (1280 - width * scale) / 2, top: 103, width, height, transform: `scale(${scale})`, transformOrigin: 'top left'}}>{children}</div>
  <Caption text={caption} size={17} bottom={22} />
</>;

const FocusSurface = ({frame, title, caption}: {frame: number; title: string; caption: string}) => {
  const state = focusTourAt(frame);
  const status = state.completed ? 'Focus completed · One alert and notification' : state.finished ? 'Rest ready · 5 minutes' : state.paused ? 'Focus paused · Remaining time retained' : frame < 38 ? 'Ready for a two-second focus countdown' : frame < 57 ? 'Focus running' : frame < 60 ? 'Display awake' : 'Display awake · Idle sleep prevented';
  return <>
    <Wallpaper dim={0.22} />
    <MenuBar />
    <Island reveal={state.compact ? 0 : 1} height={islandHeightFor(136)} wing={82} left={<div className="flex items-center gap-[6px]" style={{fontSize: 12}}><Clock size={13} /><span className="font-rounded tabular">{formatTime(Math.ceil(state.remaining))}</span></div>} right={<CompactFocusControls frame={frame} />}>
      {!state.compact ? <IslandBody header={<StatusHeader />} active={TABS.toolbox}><FocusTourModule frame={frame} /></IslandBody> : null}
    </Island>
    <Notch />
    {state.compact ? <><TourPointer frame={frame} at={80} x={761} y={17} /><TourPointer frame={frame} at={112} x={761} y={17} /></> : null}
    <div data-focus-status className="absolute inset-x-0" style={{top: state.compact ? 97 : 324, textAlign: 'center', color: state.completed ? color.green : color.secondary, fontSize: 13}}>{status}</div>
    <Headline lines={[title]} top={400} size={34} />
    <Caption text={caption} size={17} bottom={35} />
  </>;
};

export const SceneDesktopTools = ({duration = DESKTOP_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = desktopTourAt(frame, duration);
  if (state.step.id === 'mixer') return <NativeModuleSurface title={state.step.title} caption={state.frame >= 126 ? 'Safari at 30% · Music muted' : state.step.caption} module="mixer" height={152}><MixerTourModule frame={state.frame} /></NativeModuleSurface>;
  if (state.step.id === 'keyboard') {
    const keyboard = keyboardTourAt(state.frame);
    if (keyboard.phase === 'settings') return <DesktopWindowSurface title={state.step.title} caption="20 voices · Installed custom pack: BCP (Suit80)" width={960} height={680} scale={0.8}><GlassPanel radius={12} style={{inset: 0}}><KeyboardTourModule frame={state.frame} /></GlassPanel></DesktopWindowSurface>;
    return <><Wallpaper dim={0.22} /><MenuBar /><Island reveal={1} height={islandHeightFor(420)}><IslandBody header={<StatusHeader />} active={TABS.keyboard}><KeyboardTourModule frame={state.frame} /></IslandBody></Island><Notch /><Headline lines={[state.step.title]} top={590} size={29} /><Caption text={state.frame >= 126 ? 'Typing stats updated · 14 characters added' : 'Key presses update the local dashboard'} size={15} bottom={27} /></>;
  }
  if (state.step.id === 'focus') return <FocusSurface frame={state.frame} title={state.step.title} caption={state.step.caption} />;
  if (state.step.id === 'cleaning') {
    const cleaningFrame = state.frame * 180 / 150;
    if (cleaningFrame >= 26 && cleaningFrame < 87) return <ScreenCleaningCover frame={cleaningFrame} />;
    const cleaning = cleaningFrame >= 94 && cleaningFrame < 150;
    return <NativeModuleSurface title={state.step.title} caption={cleaning ? 'Keyboard input blocked · Includes F1–F12' : cleaningFrame >= 150 ? 'Screen restored · Keyboard input resumed' : state.step.caption} module="toolbox" height={136}><FocusTourModule frame={239} />{cleaning ? <div data-keyboard-cleaning-notice className="absolute flex items-center justify-center gap-[8px]" style={{right: 0, top: 94, width: 248, height: 40, borderRadius: 8, background: '#28282e', fontSize: 11}}><span>Keyboard input blocked</span><span style={{color: color.blue}}>End cleaning</span><TourPointer frame={cleaningFrame} at={150} x={218} y={20} /></div> : <TourPointer frame={cleaningFrame} at={94} x={626} y={68} />}</NativeModuleSurface>;
  }
  if (state.step.id === 'system') {
    const system = systemHistoryTourAt(state.frame);
    if (system.phase === 'live') return <NativeModuleSurface title={state.step.title} caption={state.step.caption} module="cpu" height={295}><SystemHistoryTourModule frame={state.frame} globalFrame={globalFrom + frame} /></NativeModuleSurface>;
    const settings = system.phase === 'settings';
    return <DesktopWindowSurface title={state.step.title} caption={system.exported ? 'System history.xlsx saved · All recorded readings included' : state.step.caption} width={settings ? 960 : 720} height={settings ? 680 : 560} scale={settings ? 0.8 : 0.95}>{settings ? <GlassPanel radius={12} style={{inset: 0}}><SystemHistoryTourModule frame={state.frame} globalFrame={globalFrom + frame} /></GlassPanel> : <SystemHistoryTourModule frame={state.frame} globalFrame={globalFrom + frame} />}</DesktopWindowSurface>;
  }
  if (state.step.id === 'battery') {
    const batteryFrame = state.frame * 210 / 180;
    const battery = batteryTourAt(batteryFrame);
    return <><Wallpaper dim={0.22} /><MenuBar /><Island reveal={1} height={islandHeightFor(460)}><IslandBody header={<StatusHeader />} active={TABS.cpu}><BatteryTourModule frame={batteryFrame} /></IslandBody></Island><Notch /><Headline lines={[state.step.title]} top={625} size={26} /><Caption text={battery.lowPower ? 'Low power mode applied' : battery.onBattery ? 'Battery supplies the Mac · Automatic power mode' : battery.chargingRequested ? 'Charge to 100% requested' : state.step.caption} size={15} bottom={18} /></>;
  }
  if (state.step.id === 'cleanup') return <DesktopWindowSurface title={state.step.title} caption={state.step.caption} width={560} height={430} scale={1.15}><CleanupTourModule frame={state.frame} /></DesktopWindowSurface>;
  return (
    <TourSurface title={state.step.title} caption={state.step.caption} frame={state.frame} fps={fps}>
      {state.step.id === 'sounds' ? <BackgroundSoundsTourModule frame={state.frame} /> : null}
      {state.step.id === 'presenter' ? <PresenterTourModule frame={state.frame * 180 / 150} /> : null}
    </TourSurface>
  );
};
