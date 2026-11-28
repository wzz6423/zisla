import {useCurrentFrame, useVideoConfig} from 'remotion';
import {InformationTourModule, LockScreenTourModule, ManagementTourModule, PermissionsTourModule, QuickActionsTourModule, WindowsTourModule} from '../modules/tour/SettingsTourModule';
import {TourSurface, tourAt} from '../modules/tour/TourSurface';
import {RecommendedDesktopTour} from '../modules/tour/RecommendedDesktopTour';
import {LidCloseDesktopPreview, LID_PREVIEW_TIMING} from '../modules/tour/LidCloseDesktopPreview';

export const SETTINGS_TOUR_DURATION = 940;
export const SETTINGS_TOUR_STEPS = [
  {id: 'windows', title: 'Live window previews.', caption: 'Hover Dock icons or use Command-Tab, then click to switch', from: 0, duration: 88, features: ['windowPreviews']},
  {id: 'quickActions', title: 'Quick Actions on copy (⌘N).', caption: 'Live currency conversion · Smart detectors · Safe app repair', from: 88, duration: 200, features: ['copyAssistant', 'applicationRepair']},
  {id: 'information', title: 'Tailor module order, search & care.', caption: 'Drag-to-reorder island · 17-language search · Save locations · Wellbeing', from: 288, duration: 152, features: ['island.featureOrder', 'saveLocations', 'userCare']},
  {id: 'permissions', title: 'Clear permission overview.', caption: 'Live authorization status with one-click requests & drag helper', from: 440, duration: 108, features: ['permissions']},
  {id: 'lockScreen', title: 'Ambient lock screen.', caption: 'Date, battery, weather, and Now Playing — without stealing focus', from: 548, duration: 76, features: ['lockScreen']},
  {id: 'management', title: 'AI CLI & Skills manager.', caption: 'Detect, install & update CLIs · Sync local Skills across agents', from: 624, duration: 132, features: ['aiManagement']},
  {id: 'recommended', title: 'Curated Mac companions.', caption: 'Optional third-party tools like Zshell · Depth-aware lid close', from: 756, duration: 184, features: ['recommendedTools', 'lidClose']},
] as const;

export const settingsTourAt = (frame: number, duration = SETTINGS_TOUR_DURATION) => tourAt(SETTINGS_TOUR_STEPS, frame, duration, SETTINGS_TOUR_DURATION);

export const SceneSettings = ({duration = SETTINGS_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = settingsTourAt(frame, duration);
  if (state.step.id === 'lockScreen') return <LockScreenTourModule frame={state.frame} globalFrame={globalFrom + frame} clockAnchor={globalFrom + state.step.from * (duration - 1) / (SETTINGS_TOUR_DURATION - 1)} />;
  if (state.step.id === 'windows') return <WindowsTourModule frame={state.frame} />;
  if (state.step.id === 'quickActions') return <QuickActionsTourModule frame={state.frame} />;
  if (state.step.id === 'recommended') return state.frame < LID_PREVIEW_TIMING.start ? <RecommendedDesktopTour frame={state.frame} /> : <LidCloseDesktopPreview frame={state.frame} />;
  return (
    <TourSurface title={state.step.title} caption={state.step.caption} frame={state.frame} fps={fps}>
      {state.step.id === 'information' ? <InformationTourModule frame={state.frame} /> : null}
      {state.step.id === 'permissions' ? <PermissionsTourModule frame={state.frame} /> : null}
      {state.step.id === 'management' ? <ManagementTourModule frame={state.frame} /> : null}
    </TourSurface>
  );
};
