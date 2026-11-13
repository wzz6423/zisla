import {useCurrentFrame, useVideoConfig} from 'remotion';
import {InformationTourModule, LockScreenTourModule, ManagementTourModule, PermissionsTourModule, QuickActionsTourModule, RecommendedTourModule, WindowsTourModule} from '../modules/tour/SettingsTourModule';
import {TourSurface, tourAt} from '../modules/tour/TourSurface';

export const SETTINGS_TOUR_DURATION = 1080;
export const SETTINGS_TOUR_STEPS = [
  {id: 'windows', title: 'See the window. Switch to it.', caption: 'Dock · Command-Tab · Click the window you need', from: 0, duration: 100, features: ['windowPreviews']},
  {id: 'quickActions', title: 'Copy something. Choose the next step.', caption: 'Convert currencies · Inspect and repair an app before opening', from: 100, duration: 300, features: ['copyAssistant', 'applicationRepair']},
  {id: 'information', title: 'Put your most-used tools first.', caption: 'Feature order · Scroll to Wellbeing', from: 400, duration: 160, features: ['island.featureOrder', 'userCare']},
  {id: 'permissions', title: 'System permissions, in one place.', caption: 'Review access. Request it when you need it.', from: 560, duration: 140, features: ['permissions']},
  {id: 'lockScreen', title: 'Useful information on the lock screen.', caption: 'Date · Status · Playback', from: 700, duration: 80, features: ['lockScreen']},
  {id: 'management', title: 'Manage the tools behind your AI work.', caption: 'Install a CLI · Scroll to Skills and sync', from: 780, duration: 150, features: ['aiManagement']},
  {id: 'recommended', title: 'Discover more tools. Keep control.', caption: 'Separate apps · Features → Lid-close animation', from: 930, duration: 150, features: ['recommendedTools', 'lidClose']},
] as const;

export const settingsTourAt = (frame: number, duration = SETTINGS_TOUR_DURATION) => tourAt(SETTINGS_TOUR_STEPS, frame, duration, SETTINGS_TOUR_DURATION);

export const SceneSettings = ({duration = SETTINGS_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = settingsTourAt(frame, duration);
  if (state.step.id === 'lockScreen') return <LockScreenTourModule frame={state.frame} globalFrame={globalFrom + frame} />;
  if (state.step.id === 'windows') return <WindowsTourModule frame={state.frame} />;
  if (state.step.id === 'quickActions') return <QuickActionsTourModule frame={state.frame} />;
  return (
    <TourSurface title={state.step.title} caption={state.step.caption} frame={state.frame} fps={fps}>
      {state.step.id === 'information' ? <InformationTourModule frame={state.frame} /> : null}
      {state.step.id === 'permissions' ? <PermissionsTourModule frame={state.frame} /> : null}
      {state.step.id === 'management' ? <ManagementTourModule frame={state.frame} /> : null}
      {state.step.id === 'recommended' ? <RecommendedTourModule frame={state.frame} /> : null}
    </TourSurface>
  );
};
