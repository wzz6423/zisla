import {useCurrentFrame, useVideoConfig} from 'remotion';
import {LockScreenTourModule, ManagementTourModule, PermissionsTourModule, QuickActionsTourModule, RecommendedTourModule, WindowsTourModule} from '../modules/tour/SettingsTourModule';
import {TourSurface, tourAt} from '../modules/tour/TourSurface';

export const SETTINGS_TOUR_DURATION = 1200;
export const SETTINGS_TOUR_STEPS = [
  {id: 'windows', title: 'See the window. Switch to it.', caption: 'Dock and Command-Tab previews activate the window you choose.', from: 0, duration: 180, features: ['windowPreviews']},
  {id: 'quickActions', title: 'Copy something. Choose the next step.', caption: 'Quick Actions recognises content and acts only when you choose.', from: 180, duration: 240, features: ['copyAssistant']},
  {id: 'permissions', title: 'System permissions, in one place.', caption: 'Review access, request supported permissions or open System Settings.', from: 420, duration: 180, features: ['permissions']},
  {id: 'lockScreen', title: 'Useful information on the lock screen.', caption: 'Date, status and playback in a separate lock-screen overlay.', from: 600, duration: 180, features: ['lockScreen']},
  {id: 'management', title: 'Manage the tools behind your AI work.', caption: 'Detect, install and update CLIs, then manage and sync local Skills.', from: 780, duration: 180, features: ['aiManagement']},
  {id: 'recommended', title: 'Discover more tools. Keep control.', caption: 'Separate desktop apps and a previewable lid-close transition.', from: 960, duration: 240, features: ['recommendedTools', 'lidClose']},
] as const;

export const settingsTourAt = (frame: number, duration = SETTINGS_TOUR_DURATION) => tourAt(SETTINGS_TOUR_STEPS, frame, duration, SETTINGS_TOUR_DURATION);

export const SceneSettings = ({duration = SETTINGS_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = settingsTourAt(frame, duration);
  if (state.step.id === 'lockScreen') return <LockScreenTourModule frame={state.frame} globalFrame={globalFrom + frame} />;
  return (
    <TourSurface title={state.step.title} caption={state.step.caption} frame={state.frame} fps={fps}>
      {state.step.id === 'windows' ? <WindowsTourModule frame={state.frame} /> : null}
      {state.step.id === 'quickActions' ? <QuickActionsTourModule frame={state.frame} /> : null}
      {state.step.id === 'permissions' ? <PermissionsTourModule frame={state.frame} /> : null}
      {state.step.id === 'management' ? <ManagementTourModule frame={state.frame} /> : null}
      {state.step.id === 'recommended' ? <RecommendedTourModule frame={state.frame} /> : null}
    </TourSurface>
  );
};
