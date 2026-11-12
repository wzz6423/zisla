import type {FC} from 'react';
import {BatteryFull, Search, SlidersHorizontal, Wifi} from 'lucide-react';
import {BAR_HEIGHT, NOTCH_WIDTH, STAGE, black, white} from '../theme';

export const Wallpaper: FC<{dim?: number}> = ({dim = 0}) => (
  <div className="absolute inset-0" style={{backgroundColor: '#06070b'}}>
    <div
      className="absolute inset-0"
      style={{
        background: [
          'radial-gradient(70% 55% at 18% 108%, rgba(46,84,158,0.62) 0%, rgba(46,84,158,0) 70%)',
          'radial-gradient(60% 50% at 86% 104%, rgba(124,58,150,0.5) 0%, rgba(124,58,150,0) 68%)',
          'radial-gradient(46% 38% at 52% 34%, rgba(24,74,108,0.5) 0%, rgba(24,74,108,0) 72%)',
          'radial-gradient(30% 24% at 74% 22%, rgba(214,112,72,0.2) 0%, rgba(214,112,72,0) 74%)',
        ].join(', '),
      }}
    />
    <div
      className="absolute inset-0"
      style={{background: 'radial-gradient(120% 90% at 50% 40%, rgba(0,0,0,0) 40%, rgba(0,0,0,0.55) 100%)'}}
    />
    <div className="absolute inset-0" style={{backgroundColor: black(dim)}} />
  </div>
);

const DEFAULT_MENUS = ['File', 'Edit', 'View', 'Go', 'Window', 'Help'];

export const MenuBar: FC<{appName?: string; menus?: readonly string[]; opacity?: number}> = ({
  appName = 'Finder',
  menus = DEFAULT_MENUS,
  opacity = 1,
}) => (
  <div
    className="absolute left-0 top-0 flex items-center justify-between px-5 text-[13px]"
    style={{
      width: STAGE.width,
      height: BAR_HEIGHT,
      opacity,
      backgroundColor: black(0.16),
      backdropFilter: 'blur(24px) saturate(160%)',
      color: white(0.92),
    }}
  >
    <div className="flex items-center gap-[18px]">
      <span className="font-bold">{appName}</span>
      {menus.map((menu) => (
        <span key={menu} className="font-medium">
          {menu}
        </span>
      ))}
    </div>
    <div className="flex items-center gap-[14px] font-medium">
      <BatteryFull size={19} strokeWidth={1.7} />
      <Wifi size={15} strokeWidth={2} />
      <Search size={14} strokeWidth={2.2} />
      <SlidersHorizontal size={14} strokeWidth={2.2} />
      <span className="tabular">Wed Nov 11&nbsp;&nbsp;9:41 AM</span>
    </div>
  </div>
);

// 屏幕上的物理刘海：始终是黑色，盖在岛体之上
export const Notch: FC<{opacity?: number}> = ({opacity = 1}) => (
  <div
    className="absolute top-0 bg-black"
    style={{
      left: (STAGE.width - NOTCH_WIDTH) / 2,
      width: NOTCH_WIDTH,
      height: BAR_HEIGHT - 2,
      borderRadius: '0 0 9px 9px',
      opacity,
    }}
  />
);
