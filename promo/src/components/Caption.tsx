import type {ReactNode} from 'react';
import {GLASS_BLUR} from './Glass';
import {black, white} from '../theme';

type CaptionProps = {
  text: string;
  opacity?: number;
  bottom?: number;
  size?: number;
};

export const Caption = ({text, opacity = 1, bottom = 52, size = 20}: CaptionProps) => (
  <div className="absolute inset-x-0 flex justify-center" style={{bottom, opacity}}>
    <div
      className="rounded-full px-[18px] py-[9px] font-medium"
      style={{
        fontSize: size,
        lineHeight: `${size + 6}px`,
        background: black(0.44),
        backdropFilter: GLASS_BLUR,
        WebkitBackdropFilter: GLASS_BLUR,
        border: `1px solid ${white(0.1)}`,
      }}
    >
      {text}
    </div>
  </div>
);

type HeadlineProps = {
  lines: readonly string[];
  opacity?: number;
  // 距画面顶部的距离
  top?: number;
  size?: number;
  weight?: number;
  align?: 'center' | 'left';
  children?: ReactNode;
};

export const Headline = ({lines, opacity = 1, top, size = 52, weight = 600, align = 'center', children}: HeadlineProps) => (
  <div
    className="absolute inset-x-0 flex flex-col"
    style={{top, opacity, alignItems: align === 'center' ? 'center' : 'flex-start', paddingLeft: align === 'left' ? 96 : 0}}
  >
    {lines.map((line) => (
      <div
        key={line}
        className="font-semibold"
        style={{fontSize: size, lineHeight: `${Math.round(size * 1.14)}px`, fontWeight: weight, letterSpacing: '-0.022em', textShadow: '0 3px 30px rgba(0,0,0,0.6)'}}
      >
        {line}
      </div>
    ))}
    {children}
  </div>
);

// 场景之间的黑场遮罩。场景自身保持不透明，靠这一层做进出场，玻璃材质才不会失效。
export const Blackout = ({opacity}: {opacity: number}) => (
  <div className="pointer-events-none absolute inset-0 bg-black" style={{opacity}} />
);
