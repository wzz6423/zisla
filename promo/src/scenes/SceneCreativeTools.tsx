import {useCurrentFrame} from 'remotion';
import {Caption, Headline} from '../components/Caption';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {RecordingStudioTour, ScreenshotsModule} from '../modules/ToolsModule';
import {CreativeToolsModule} from '../modules/CreativeToolsModule';
import {easeOutAt} from '../motion';

export const CREATIVE_TOUR_DURATION = 2160;
export const creativeGroups = [
  {id: 'capture', from: 0, duration: 360, title: 'Precision capture, long scroll, and pins.', caption: 'HDR · Annotations · Auto-scroll stitch · Table OCR to .xlsx · Scalable pins', features: ['capture']},
  {id: 'recording', from: 360, duration: 720, title: 'Screen Recording Studio.', caption: 'HDR capture · Portrait & voice polish · Multi-track edit · Captions & AI cut', features: ['recording']},
  {id: 'image', from: 1080, duration: 420, title: 'Nine local image tools.', caption: 'Format size comparison · Table recognition · Freehand extraction', features: ['imageTools']},
  {id: 'audio', from: 1500, duration: 360, title: 'Twenty-seven local audio tools.', caption: 'Trim, LUFS loudness normalization, effects & test tones via FFmpeg', features: ['audioTools']},
  {id: 'pdf', from: 1860, duration: 300, title: 'Fourteen offline PDF tools.', caption: 'Merge in order, split, watermark, or password-protect locally', features: ['pdf']},
] as const;

export const creativeTourAt = (frame: number, duration = CREATIVE_TOUR_DURATION) => {
  const position = Math.min(CREATIVE_TOUR_DURATION - 1, Math.max(0, frame * CREATIVE_TOUR_DURATION / duration));
  const group = creativeGroups.find((item) => position >= item.from && position < item.from + item.duration)!;
  return {group, frame: position - group.from};
};

export const SceneCreativeTools = ({duration = CREATIVE_TOUR_DURATION}: {duration?: number}) => {
  const {group, frame} = creativeTourAt(useCurrentFrame(), duration);
  const contentIn = easeOutAt(frame, [0, 12], [0, 1]);
  return <>
    <Wallpaper dim={.36} /><MenuBar /><Notch />
    <Headline lines={[group.title]} top={102} size={36} align="left" opacity={contentIn} />
    {/* Keep the workspace glass panel steady across tools and crossfade inner content to avoid dark flashes. */}
    <GlassPanel style={{left: 96, top: 170, width: 1088, height: 466}} opacity={1}>
      <div
        data-feature={group.features.join(' ')}
        style={{position: 'absolute', inset: 0, opacity: contentIn, transform: `translateY(${(1 - contentIn) * 6}px)`}}
      >
        {group.id === 'capture' ? <ScreenshotsModule frame={frame} /> : group.id === 'recording' ? <RecordingStudioTour frame={frame} /> : <CreativeToolsModule kind={group.id} frame={frame} />}
      </div>
    </GlassPanel>
    <Caption text={group.caption} size={16} bottom={34} opacity={contentIn} />
  </>;
};
