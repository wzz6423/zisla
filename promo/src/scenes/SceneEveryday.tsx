import {useCurrentFrame, useVideoConfig} from 'remotion';
import {AgendaTourModule, BriefingTourModule, ClipboardTourModule, ContextNotesTourModule, MeetingTourModule, NotesTourModule, VoiceTourModule} from '../modules/tour/EverydayTourModule';
import {NativeModuleSurface, tourAt} from '../modules/tour/TourSurface';

export const EVERYDAY_TOUR_DURATION = 1080;
export const EVERYDAY_TOUR_STEPS = [
  {id: 'notes', title: 'Quick Notes, synced with Apple Notes.', caption: 'Live Markdown · ⌘1–9 & ⌘←/→ navigation · Auto-saved', from: 0, duration: 130, features: ['quickNotes']},
  {id: 'clipboard', title: 'Clipboard history that reads your images.', caption: 'On-device OCR search · Source app tags · Type filters', from: 130, duration: 150, features: ['clipboard']},
  {id: 'agenda', title: 'Your day at a glance.', caption: 'Local weather, calendar events, and checkable reminders', from: 280, duration: 120, features: ['agenda']},
  {id: 'meeting', title: 'Ten minutes before every call.', caption: 'Top-edge countdown · One-click join · Linked meeting notes', from: 400, duration: 262, features: ['meetingCountdown', 'meetingNotes']},
  {id: 'context', title: 'Notes pinned to the page or window.', caption: 'Window snapshots & repeating reminders that return in context', from: 662, duration: 125, features: ['contextNotes']},
  {id: 'briefing', title: 'Daily Briefing.', caption: '8 templates · Screen Time, typing & AI quotas · Scheduled PNG', from: 787, duration: 143, features: ['dailyBriefing']},
  {id: 'voice', title: 'Voice dictation, cleaned on the fly.', caption: 'Hold to talk · Custom hotwords · Local Ollama or remote polish', from: 930, duration: 150, features: ['voice']},
] as const;

export const everydayTourAt = (frame: number, duration = EVERYDAY_TOUR_DURATION) => tourAt(EVERYDAY_TOUR_STEPS, frame, duration, EVERYDAY_TOUR_DURATION);

export const SceneEveryday = ({duration = EVERYDAY_TOUR_DURATION, globalFrom = 0}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = everydayTourAt(frame, duration);
  if (state.step.id === 'meeting') return <MeetingTourModule frame={state.frame} title={state.step.title} caption={state.step.caption} />;
  if (state.step.id === 'briefing') return <BriefingTourModule frame={state.frame} />;
  if (state.step.id === 'context') {
    return (
      <NativeModuleSurface title={state.step.title} caption={state.step.caption} module="shelf" height={355} fromModule="agenda" fromHeight={160} frame={state.frame} fps={fps}>
        <ContextNotesTourModule frame={state.frame} />
      </NativeModuleSurface>
    );
  }
  if (state.step.id === 'notes') {
    return (
      <NativeModuleSurface title={state.step.title} caption={state.step.caption} module="notes" height={401} frame={state.frame} fps={fps}>
        <NotesTourModule frame={state.frame} />
      </NativeModuleSurface>
    );
  }
  if (state.step.id === 'clipboard') {
    return (
      <NativeModuleSurface title={state.step.title} caption={state.step.caption} module="clipboard" height={355} fromModule="notes" fromHeight={401} frame={state.frame} fps={fps}>
        <ClipboardTourModule frame={state.frame} />
      </NativeModuleSurface>
    );
  }
  if (state.step.id === 'agenda') {
    return (
      <NativeModuleSurface title={state.step.title} caption={state.step.caption} module="agenda" height={160} fromModule="clipboard" fromHeight={355} frame={state.frame} fps={fps}>
        <AgendaTourModule frame={state.frame} />
      </NativeModuleSurface>
    );
  }
  return <VoiceTourModule frame={state.frame} globalFrame={globalFrom + frame} />;
};
