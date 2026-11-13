import {useCurrentFrame} from 'remotion';
import {AgendaTourModule, BriefingTourModule, ClipboardTourModule, ContextNotesTourModule, MeetingTourModule, NotesTourModule, VoiceTourModule} from '../modules/tour/EverydayTourModule';
import {NativeModuleSurface, tourAt} from '../modules/tour/TourSurface';

export const EVERYDAY_TOUR_DURATION = 1680;
export const EVERYDAY_TOUR_STEPS = [
  {id: 'notes', title: 'Write it. Keep it in Apple Notes.', caption: 'Markdown · Formatting · Native notes', from: 0, duration: 180, features: ['quickNotes']},
  {id: 'clipboard', title: 'Find it. Copy it. Use it again.', caption: 'Type filters · Search · Favourites · History retention', from: 180, duration: 180, features: ['clipboard']},
  {id: 'agenda', title: 'Weather, calendar and reminders.', caption: 'Complete a reminder. Keep the next event in view.', from: 360, duration: 180, features: ['agenda']},
  {id: 'meeting', title: 'Your meeting. Your notes. Together.', caption: 'Countdown · Join · Create or link a meeting note', from: 540, duration: 360, features: ['meetingCountdown', 'meetingNotes']},
  {id: 'context', title: 'A note that remembers the place.', caption: 'Window screenshot · Recurring reminder · Return to context', from: 900, duration: 240, features: ['contextNotes']},
  {id: 'briefing', title: 'Turn your day into a shareable PNG.', caption: 'Eight templates · Choose metrics and quotas · Scheduled exports', from: 1140, duration: 240, features: ['dailyBriefing']},
  {id: 'voice', title: 'Say it. Clean it up. Keep working.', caption: 'Hold to talk · Vocabularies · Local or remote cleanup', from: 1380, duration: 300, features: ['voice']},
] as const;

export const everydayTourAt = (frame: number, duration = EVERYDAY_TOUR_DURATION) => tourAt(EVERYDAY_TOUR_STEPS, frame, duration, EVERYDAY_TOUR_DURATION);

export const SceneEveryday = ({duration = EVERYDAY_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const state = everydayTourAt(frame, duration);
  if (state.step.id === 'meeting') return <MeetingTourModule frame={state.frame} title={state.step.title} caption={state.step.caption} />;
  if (state.step.id === 'briefing') return <BriefingTourModule frame={state.frame} />;
  if (state.step.id === 'context') return <NativeModuleSurface title={state.step.title} caption={state.step.caption} module="shelf" height={355}><ContextNotesTourModule frame={state.frame} /></NativeModuleSurface>;
  if (state.step.id === 'notes' || state.step.id === 'clipboard' || state.step.id === 'agenda') {
    return <NativeModuleSurface title={state.step.title} caption={state.step.caption} module={state.step.id === 'notes' ? 'notes' : state.step.id === 'clipboard' ? 'clipboard' : 'agenda'} height={state.step.id === 'agenda' ? 160 : state.step.id === 'clipboard' ? 355 : 401}>
      {state.step.id === 'notes' ? <NotesTourModule frame={state.frame} /> : state.step.id === 'clipboard' ? <ClipboardTourModule frame={state.frame} /> : <AgendaTourModule frame={state.frame} />}
    </NativeModuleSurface>;
  }
  return <VoiceTourModule frame={state.frame} globalFrame={globalFrom + frame} />;
};
