import {CircleChevronDown, FileArchive, Image as ImageIcon, X} from 'lucide-react';
import {GLASS_BLUR} from './Glass';
import {NOTCH_WIDTH, STAGE, black, clamp01, color, white} from '../theme';
import {SHELF_LAYOUT, shelfMenuPlacement} from '../modules/shelfLayout';

const CENTER = STAGE.width / 2;

export const ShelfContextMenu = ({anchor, opacity, highlight}: {anchor: {x: number; y: number}; opacity: number; highlight: number}) => {
  const placement = shelfMenuPlacement(anchor, STAGE);
  return (
    <div
      role="menu"
      aria-label="Shelf file actions"
      className="absolute py-[5px] text-[12px] leading-[18px]"
      style={{
        left: placement.x,
        top: placement.y,
        width: SHELF_LAYOUT.menuWidth,
        background: 'rgba(28,28,32,0.86)',
        backdropFilter: GLASS_BLUR,
        WebkitBackdropFilter: GLASS_BLUR,
        border: `1px solid ${white(0.12)}`,
        borderRadius: 8,
        boxShadow: '0 12px 34px rgba(0,0,0,0.5)',
        opacity: clamp01(opacity),
        transform: `scale(${0.96 + 0.04 * clamp01(opacity)})`,
        transformOrigin: placement.transformOrigin,
      }}
    >
      {['Open', 'Show in Finder', 'Copy', 'Send to Quick Notes'].map((label, index) => (
        <div key={label} role="menuitem" className="mx-[3px] rounded-[4px] px-[7px] py-[3px]" style={{background: index === 1 && highlight > 0.5 ? color.blue : 'transparent'}}>
          {label}
        </div>
      ))}
      <div style={{height: 1, background: color.divider, margin: '4px 0'}} />
      <div role="menuitem" className="px-[10px] py-[3px]">Remove</div>
    </div>
  );
};

// Completed downloads use the application's top-edge quick-action bar.
const TOAST = {width: 560, height: 34};
const TOAST_SIDE = (TOAST.width - NOTCH_WIDTH) / 2;

type QuickActionToastProps = {
  title: string;
  detail: string;
  action: string;
  opacity?: number;
  // Remaining lifetime shown along the bottom edge.
  countdown?: number;
  actionGlow?: number;
};

export const QuickActionToast = ({title, detail, action, opacity = 1, countdown = 1, actionGlow = 0}: QuickActionToastProps) => (
  <div
    className="absolute flex items-center overflow-hidden"
    style={{
      left: CENTER - TOAST.width / 2,
      top: 0,
      width: TOAST.width,
      height: TOAST.height,
      borderRadius: '0 0 14px 14px',
      background: '#000',
      opacity: clamp01(opacity),
      transform: `translateY(${(1 - clamp01(opacity)) * -TOAST.height}px)`,
      boxShadow: `0 14px 34px ${black(0.55 * clamp01(opacity))}`,
    }}
  >
    <div className="flex shrink-0 items-center gap-[10px] overflow-hidden" style={{width: TOAST_SIDE, padding: '0 8px 0 14px'}}>
      <div className="flex shrink-0 items-center justify-center" style={{width: 26, height: 26}}>
        <FileArchive size={13} strokeWidth={2.2} color={white(0.75)} />
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[2px]">
        <div className="truncate text-[12px] leading-[14px] font-medium" style={{color: white(0.92)}}>
          {title}
        </div>
        <div className="truncate text-[9.5px] leading-[11px]" style={{color: white(0.55)}}>
          {detail}
        </div>
      </div>
    </div>
    <div className="h-full shrink-0" style={{width: NOTCH_WIDTH}} />
    <div className="flex shrink-0 items-center justify-end gap-[8px]" style={{width: TOAST_SIDE, padding: '0 14px 0 8px'}}>
      <div
        className="rounded-full px-3 py-[6px] text-[11px] leading-[13px] font-medium"
        style={{background: white(0.14 + 0.1 * actionGlow), color: white(0.95)}}
      >
        {action}
      </div>
      <div className="flex items-center justify-center" style={{width: 19, height: 24}}>
        <CircleChevronDown size={13} strokeWidth={2.4} color={white(0.92)} />
      </div>
      <div className="flex items-center justify-center" style={{width: 20, height: 20}}>
        <X size={9} strokeWidth={3} color={white(0.45)} />
      </div>
    </div>
    <div className="absolute inset-x-0 bottom-0" style={{height: 2, background: white(0.14)}}>
      <div style={{width: `${clamp01(countdown) * 100}%`, height: 2, background: white(0.45)}} />
    </div>
  </div>
);

type DragGhostProps = {
  x: number;
  y: number;
  name: string;
  tint: string;
  // Drag lift amount, normalized to 0–1.
  hold?: number;
  opacity?: number;
};

export const DragGhost = ({x, y, name, tint, hold = 0, opacity = 1}: DragGhostProps) => (
  <div
    className="absolute flex flex-col items-center gap-[6px]"
    style={{
      left: x,
      top: y,
      opacity: clamp01(opacity),
      transform: `translate(-50%, -50%) scale(${0.94 + 0.12 * hold}) rotate(${-4 + 4 * hold}deg)`,
    }}
  >
    <div
      className="flex items-center justify-center"
      style={{
        width: 92,
        height: 92,
        borderRadius: 12,
        background: 'rgba(38,38,44,0.78)',
        backdropFilter: GLASS_BLUR,
        WebkitBackdropFilter: GLASS_BLUR,
        border: `1px solid ${white(0.16)}`,
        boxShadow: '0 22px 44px rgba(0,0,0,0.55)',
      }}
    >
      <ImageIcon size={44} strokeWidth={1.4} color={tint} />
    </div>
    <div
      className="rounded-full px-[10px] py-[4px] text-[10px] font-medium"
      style={{background: black(0.62), border: `1px solid ${white(0.1)}`}}
    >
      {name}
    </div>
  </div>
);
