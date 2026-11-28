import {Check, FileText} from 'lucide-react';
import {ShelfModule} from '../ShelfModule';
import type {ShelfItem} from '../../content';
import {ZislaMotion, easeOutAt, springAt} from '../../motion';
import {clamp01, color, white} from '../../theme';
import {shelfItemPoint} from '../shelfLayout';
import {TourPointerTrack} from './TourSurface';

const files: readonly ShelfItem[] = [
  {name: 'Cover.png', kind: 'image', tint: '#8cb6ed'},
  {name: 'Review table.png', kind: 'image', tint: '#f3bf87'},
  {name: 'Walkthrough.mp4', kind: 'video', tint: '#a894e9'},
];

export const shelfSelectionAt = (frame: number) => ({
  selection: frame < 26 ? undefined : frame < 58 ? [] : frame < 80 ? [0] : [0, 1],
  menu: frame >= 98 && frame < 134,
  processing: frame >= 134 && frame < 170,
  completed: frame >= 170,
});

export const ShelfSelectionTour = ({frame}: {frame: number}) => {
  const state = shelfSelectionAt(frame);
  const menuOpacity = state.menu ? easeOutAt(frame, [98, 106], [0, 1]) : 0;
  const resultIn = state.processing || state.completed ? clamp01(springAt(frame, 60, 134, ZislaMotion.notice, 16)) : 0;
  return <div className="absolute inset-0" data-feature="shelf.mediaActions">
    <ShelfModule items={files} enter={3} selection={state.selection} />
    {state.menu ? (
      <div
        className="absolute"
        role="menu"
        data-shelf-selection-menu
        style={{
          left: 505,
          top: 116,
          width: 228,
          borderRadius: 8,
          background: '#28282d',
          padding: 6,
          fontSize: 11,
          lineHeight: '27px',
          boxShadow: '0 15px 45px rgba(0,0,0,.5)',
          opacity: menuOpacity,
          transform: `scale(${0.96 + 0.04 * menuOpacity})`,
          transformOrigin: 'top right',
        }}
      >
        <div data-shelf-media-action="zipAndImages">Compress to ZIP · Resize &amp; Convert</div>
        <div role="menuitem" data-shelf-media-action="imagesToPDF" style={{padding: '0 7px', borderRadius: 4, background: color.blue}}>Images to PDF</div>
        <div>Recognize to Quick Notes</div>
        <div data-shelf-media-action="importStudio" style={{color: color.secondary}}>Import to Recording Studio library</div>
      </div>
    ) : null}
    {state.processing || state.completed ? (
      <div
        className="absolute flex items-center gap-[12px]"
        data-shelf-conversion-result
        style={{
          left: 111,
          right: 18,
          bottom: 18,
          padding: '12px 14px',
          borderRadius: 8,
          background: white(0.06),
          fontSize: 12,
          opacity: resultIn,
          transform: `translateY(${(1 - resultIn) * 8}px)`,
        }}
      >
        {state.completed ? <Check size={17} color={color.green} /> : <FileText size={17} color={color.blue} />}
        <div><div style={{fontWeight: 600, color: state.completed ? color.green : color.label}}>{state.completed ? 'Review images.pdf saved' : 'Combining 2 selected images…'}</div><div style={{marginTop: 5, color: color.secondary}}>Cover.png + Review table.png · Original files retained</div></div>
      </div>
    ) : null}
    <TourPointerTrack frame={frame} actions={[{at: 20, x: 448, y: 16}, {at: 52, x: shelfItemPoint(0).x, y: shelfItemPoint(0).y + 27}, {at: 74, x: shelfItemPoint(1).x, y: shelfItemPoint(1).y + 27}, {at: 92, x: 708, y: 103}, {at: 128, x: 591, y: 160}]} />
  </div>;
};
