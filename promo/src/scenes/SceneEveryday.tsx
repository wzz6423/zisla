import {useCurrentFrame, useVideoConfig} from 'remotion';
import {AgendaTourModule, BriefingTourModule, ClipboardTourModule, ContextNotesTourModule, NotesTourModule, VoiceTourModule} from '../modules/tour/EverydayTourModule';
import {TourSurface, tourAt} from '../modules/tour/TourSurface';

export const EVERYDAY_TOUR_DURATION = 1560;
export const EVERYDAY_TOUR_STEPS = [
  {id: 'notes', title: 'Write it down. Keep the original.', caption: 'Quick Notes saves your Markdown drafts back to Apple Notes.', from: 0, duration: 240, features: ['quickNotes']},
  {id: 'clipboard', title: 'Find what you copied. Use it again.', caption: 'Search clipboard history, filter by type, copy and save favourites.', from: 240, duration: 240, features: ['clipboard']},
  {id: 'agenda', title: 'Your next task and the weather, together.', caption: 'Calendar, reminders, several places and timely care reminders.', from: 480, duration: 240, features: ['agenda', 'userCare']},
  {id: 'context', title: 'A note that remembers the place.', caption: 'Attach the window, save a reminder, and return to the same context.', from: 720, duration: 240, features: ['contextNotes']},
  {id: 'briefing', title: 'Turn your day into a shareable PNG.', caption: 'Eight templates, selected metrics, preview and scheduled exports.', from: 960, duration: 300, features: ['dailyBriefing']},
  {id: 'voice', title: 'Say it. Clean it up. Keep working.', caption: 'Toggle or hold to talk, with vocabularies and optional model cleanup.', from: 1260, duration: 300, features: ['voice']},
] as const;

export const everydayTourAt = (frame: number, duration = EVERYDAY_TOUR_DURATION) => tourAt(EVERYDAY_TOUR_STEPS, frame, duration, EVERYDAY_TOUR_DURATION);

export const SceneEveryday = ({duration = EVERYDAY_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = everydayTourAt(frame, duration);
  return (
    <TourSurface title={state.step.title} caption={state.step.caption} frame={state.frame} fps={fps}>
      {state.step.id === 'notes' ? <NotesTourModule frame={state.frame} /> : null}
      {state.step.id === 'clipboard' ? <ClipboardTourModule frame={state.frame} /> : null}
      {state.step.id === 'agenda' ? <AgendaTourModule frame={state.frame} /> : null}
      {state.step.id === 'context' ? <ContextNotesTourModule frame={state.frame} /> : null}
      {state.step.id === 'briefing' ? <BriefingTourModule frame={state.frame} /> : null}
      {state.step.id === 'voice' ? <VoiceTourModule frame={state.frame} globalFrame={globalFrom + frame} /> : null}
    </TourSurface>
  );
};
