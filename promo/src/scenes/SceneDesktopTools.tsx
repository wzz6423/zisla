import {useCurrentFrame, useVideoConfig} from 'remotion';
import {BatteryTourModule, CleaningTourModule, CleanupTourModule, FocusTourModule, KeyboardTourModule, MixerTourModule, PresenterTourModule, SystemHistoryTourModule} from '../modules/tour/DesktopTourModule';
import {TourSurface, tourAt} from '../modules/tour/TourSurface';

export const DESKTOP_TOUR_DURATION = 1500;
export const DESKTOP_TOUR_STEPS = [
  {id: 'mixer', title: 'Give every app its own volume.', caption: 'Adjust playing apps independently and mute only the one you choose.', from: 0, duration: 180, features: ['volumeMixer']},
  {id: 'keyboard', title: 'Make typing sound and feel your own.', caption: 'Twenty voices, local typing trends and a per-key heatmap.', from: 180, duration: 180, features: ['keyboardSound']},
  {id: 'focus', title: 'Stay focused. Keep the screen awake.', caption: 'Focus and rest timers, keep-awake and idle-sleep controls.', from: 360, duration: 240, features: ['toolbox', 'focus', 'powerAssertions']},
  {id: 'cleaning', title: 'A moment to clean the screen and keys.', caption: 'Cover the screen or block keyboard input, then return to work.', from: 600, duration: 180, features: ['screenCleaning', 'keyboardCleaning', 'trash']},
  {id: 'presenter', title: 'Read your script. Check your camera.', caption: 'A scrolling teleprompter and a camera mirror, with clear stop controls.', from: 780, duration: 180, features: ['teleprompter', 'cameraMirror']},
  {id: 'system', title: 'See your Mac’s work over time.', caption: 'CPU, GPU, memory, disk and network, with history and spreadsheet export.', from: 960, duration: 240, features: ['system', 'systemHistory']},
  {id: 'battery', title: 'See where the power goes.', caption: 'Battery health, nearby devices and modes that follow the power source.', from: 1200, duration: 180, features: ['battery', 'automaticPowerMode']},
  {id: 'cleanup', title: 'Review it. Move it to Trash.', caption: 'Inspect cleanup candidates, keep review items and confirm the selected move.', from: 1380, duration: 120, features: ['systemCleanup']},
] as const;

export const desktopTourAt = (frame: number, duration = DESKTOP_TOUR_DURATION) => tourAt(DESKTOP_TOUR_STEPS, frame, duration, DESKTOP_TOUR_DURATION);

export const SceneDesktopTools = ({duration = DESKTOP_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = desktopTourAt(frame, duration);
  return (
    <TourSurface title={state.step.title} caption={state.step.caption} frame={state.frame} fps={fps}>
      {state.step.id === 'mixer' ? <MixerTourModule frame={state.frame} /> : null}
      {state.step.id === 'keyboard' ? <KeyboardTourModule frame={state.frame} /> : null}
      {state.step.id === 'focus' ? <FocusTourModule frame={state.frame} /> : null}
      {state.step.id === 'cleaning' ? <CleaningTourModule frame={state.frame} /> : null}
      {state.step.id === 'presenter' ? <PresenterTourModule frame={state.frame} /> : null}
      {state.step.id === 'system' ? <SystemHistoryTourModule frame={state.frame} globalFrame={globalFrom + frame} /> : null}
      {state.step.id === 'battery' ? <BatteryTourModule frame={state.frame} /> : null}
      {state.step.id === 'cleanup' ? <CleanupTourModule frame={state.frame} /> : null}
    </TourSurface>
  );
};
