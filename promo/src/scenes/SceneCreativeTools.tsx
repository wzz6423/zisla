import {useCurrentFrame} from 'remotion';
import {Caption, Headline} from '../components/Caption';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {RecordingStudioTour, ScreenshotsModule} from '../modules/ToolsModule';
import {CreativeToolsModule} from '../modules/CreativeToolsModule';
import {clamp01} from '../theme';

export const CREATIVE_TOUR_DURATION = 2160;
export const creativeGroups = [
  {id: 'capture', from: 0, duration: 360, title: 'Capture once. Keep every detail.', caption: 'HDR, annotation, slow auto-scroll, pins and local recognition.', features: ['capture']},
  {id: 'recording', from: 360, duration: 720, title: 'Record your screen. Shape the story.', caption: 'Capture, edit the timeline, preview captions and an AI proposal, then export.', features: ['recording']},
  {id: 'image', from: 1080, duration: 420, title: 'From the original to a useful image.', caption: 'Compare output sizes, recognize a table and apply a local freehand extraction.', features: ['imageTools']},
  {id: 'audio', from: 1500, duration: 360, title: 'The sound you need, saved locally.', caption: 'Set a time range, normalize the saved clip, then generate a test tone.', features: ['audioTools']},
  {id: 'pdf', from: 1860, duration: 300, title: 'Documents, finished on your Mac.', caption: 'Merge selected documents, then protect the resulting PDF.', features: ['pdf']},
] as const;

export const creativeTourAt = (frame: number, duration = CREATIVE_TOUR_DURATION) => {
  const position = Math.min(CREATIVE_TOUR_DURATION - 1, Math.max(0, frame * CREATIVE_TOUR_DURATION / duration));
  const group = creativeGroups.find((item) => position >= item.from && position < item.from + item.duration)!;
  return {group, frame: position - group.from};
};

export const SceneCreativeTools = ({duration = CREATIVE_TOUR_DURATION}: {duration?: number}) => {
  const {group, frame} = creativeTourAt(useCurrentFrame(), duration);
  return <>
    <Wallpaper dim={.36} /><MenuBar /><Notch />
    <Headline lines={[group.title]} top={102} size={36} align="left" opacity={clamp01(frame / 14)} />
    <GlassPanel style={{left: 96, top: 170, width: 1088, height: 466}} opacity={clamp01(frame / 12)}>
      <div data-feature={group.features.join(' ')} style={{position: 'absolute', inset: 0}}>
        {group.id === 'capture' ? <ScreenshotsModule frame={frame} /> : group.id === 'recording' ? <RecordingStudioTour frame={frame} /> : <CreativeToolsModule kind={group.id} frame={frame} />}
      </div>
    </GlassPanel>
    <Caption text={group.caption} size={16} bottom={34} />
  </>;
};
