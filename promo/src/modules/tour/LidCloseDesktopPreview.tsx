import {Caption, Headline} from '../../components/Caption';
import {clamp01, STAGE} from '../../theme';
import {ease, easeOutAt} from '../../motion';
import {ZshellTourDesktop} from './RecommendedDesktopTour';

export const LID_PREVIEW_TIMING = {start: 108, closed: 140, opening: 150, restored: 182} as const;

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
    ? easeOutAt(frame, [timing.start, timing.closed], [125, 55])
    : frame < timing.opening ? 55 : ease(frame, [timing.opening, timing.restored], [55, 125]);
  const progress = clamp01((90 - angle) / 60);
  return {angle, progress, active: frame >= timing.start && frame < timing.restored, restored: frame >= timing.restored, ...lidDepthAt(angle)};
};

export const LidCloseDesktopPreview = ({frame}: {frame: number}) => {
  const state = lidPreviewAt(frame);
  const captionOpacity = ease(frame, [LID_PREVIEW_TIMING.start, LID_PREVIEW_TIMING.start + 12], [0, 1]);
  return <div className="absolute inset-0" data-feature="lidClose">
    <div data-lid-fullscreen-overlay className="absolute inset-0" style={{background: '#000', overflow: 'hidden'}}>
      <div data-lid-depth-sheet className="absolute left-0 top-0" style={{width: STAGE.width, height: STAGE.height, transform: state.matrix, transformOrigin: '0 0'}}>
        <ZshellTourDesktop />
        <div className="absolute inset-0" style={{background: 'linear-gradient(to top, rgba(0,0,0,0.08), rgba(0,0,0,0.4))', opacity: Math.pow(state.progress, 0.7)}} />
      </div>
    </div>
    <Headline lines={['Close the lid. Open it again.']} top={85} size={34} opacity={captionOpacity} />
    <Caption text="Lid-close animation · A smooth return to your desktop" size={17} bottom={35} opacity={captionOpacity} />
  </div>;
};
