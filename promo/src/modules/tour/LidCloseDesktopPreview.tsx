import {Laptop, Play} from 'lucide-react';
import {Caption} from '../../components/Caption';
import {clamp01, color, STAGE, white} from '../../theme';
import {linear} from '../../motion';
import {ZshellTourDesktop} from './RecommendedDesktopTour';
import {TourHeading, TourPointer, TourResult, TourSurface, TourToggle} from './TourSurface';

export const LID_PREVIEW_TIMING = {click: 86, start: 92, closed: 138, opening: 144, release: 156, restored: 166} as const;

// Match DepthGeometry's bottom hinge and fixed eye; CSS coordinates grow downwards.
export const lidDepthAt = (angle: number) => {
  const {width, height} = STAGE;
  const current = angle * Math.PI / 180;
  const separation = Math.min(2 * Math.max(90 - angle, 0), 88) * Math.PI / 180;
  const along = height * 2.7 * Math.cos(current) + height / 2 * Math.sin(current);
  const depth = Math.max(height * 2.7 * Math.sin(current) - height / 2 * Math.cos(current), height / 10);
  const scale = depth / (depth + height * Math.sin(separation));
  const top = height - (along + (height * Math.cos(separation) - along) * scale);
  const projection = 1 / scale - 1;
  const inset = width / 2 * (1 - scale);
  const matrix = `matrix3d(1,0,0,0,${-width * projection / (2 * height)},${1 - top / (height * scale)},0,${-projection / height},0,0,1,0,${inset / scale},${top / scale},0,${1 / scale})`;
  return {matrix, scale, top, inset};
};

export const lidPreviewAt = (frame: number) => {
  const timing = LID_PREVIEW_TIMING;
  const angle = frame < timing.closed
    ? linear(frame, [timing.start, timing.closed], [125, 21])
    : frame < timing.opening ? 21 : linear(frame, [timing.opening, timing.release], [21, 125]);
  const progress = clamp01((90 - angle) / 60);
  return {angle, progress, active: frame >= timing.start && frame < timing.restored, restored: frame >= timing.restored, opacity: linear(frame, [timing.release, timing.restored], [1, 0]), ...lidDepthAt(angle)};
};

const LidFeatureSettings = ({restored}: {restored: boolean}) => <div className="absolute inset-0" data-recommended-section="features" style={{padding: '17px 40px'}}>
  <TourHeading title="Settings → Features" />
  <div style={{fontSize: 19, fontWeight: 600, margin: '18px 0'}}>Tools and monitoring</div>
  <div style={{padding: '14px 16px', borderRadius: 10, background: color.fillControl}}>
    <div className="flex items-center gap-[14px]"><Laptop size={21} color={color.secondary} /><div className="flex-1"><TourToggle label="Lid-close animation" on /><div style={{fontSize: 13, marginTop: 7, color: color.secondary}}>Depth transition when closing a compatible MacBook</div></div></div>
    <div style={{height: 1, margin: '14px 0', background: color.divider}} />
    <div className="flex items-center justify-between" style={{fontSize: 15}}><span>Preview animation</span><div data-lid-preview-action className="flex items-center justify-center gap-[5px]" style={{height: 24, padding: '0 10px', borderRadius: 6, background: white(0.08), border: `1px solid ${white(0.12)}`, fontSize: 10, fontWeight: 600}}><Play size={8} fill="currentColor" />Preview animation</div></div>
  </div>
  {restored ? <div style={{marginTop: 24}}><TourResult>Preview ended · Desktop restored</TourResult></div> : null}
</div>;

export const LidCloseDesktopPreview = ({frame}: {frame: number}) => {
  const state = lidPreviewAt(frame);
  const title = 'Watch the screen fold into depth.';
  const caption = 'Features · Lid-close animation · Full-screen preview';
  return <>
    <TourSurface title={title} caption={caption} frame={frame - 78} fps={60}><LidFeatureSettings restored={state.restored} />{!state.active && !state.restored ? <TourPointer frame={frame} at={LID_PREVIEW_TIMING.click} x={920} y={226} /> : null}</TourSurface>
    {state.active ? <><div data-lid-fullscreen-overlay className="absolute inset-0" style={{background: '#000', opacity: state.opacity, overflow: 'hidden'}}>
      <div data-lid-depth-sheet className="absolute left-0 top-0" style={{width: STAGE.width, height: STAGE.height, transform: state.matrix, transformOrigin: '0 0'}}>
        <ZshellTourDesktop />
        <div className="absolute inset-0" style={{background: 'linear-gradient(to top, rgba(0,0,0,0.08), rgba(0,0,0,0.4))', opacity: Math.pow(state.progress, 0.7)}} />
      </div>
    </div><Caption text={caption} size={17} bottom={35} /></> : null}
  </>;
};
