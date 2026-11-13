import type {ReactNode} from 'react';
import {color, white} from '../theme';

type TerminalWindowProps = {
  command: string;
  // 已输入字符数（可含小数），用 typedChars 逐帧推进
  typed: number;
  frame: number;
  x: number;
  y: number;
  width: number;
  height: number;
  title?: string;
  opacity?: number;
  scale?: number;
  output?: ReactNode;
};

export const typedChars = (frame: number, start: number, length: number, charsPerSecond = 30, fps = 60): number =>
  Math.max(0, Math.min(length, ((frame - start) * charsPerSecond) / fps));

export const Caret = ({frame, frameRate = 60, opacity = 1}: {frame: number; frameRate?: number; opacity?: number}) => (
  <span
    className="inline-block"
    style={{
      width: 7,
      height: 13,
      marginLeft: 1,
      verticalAlign: '-2px',
      background: white(0.92),
      opacity: opacity * (frame % (frameRate === 60 ? 34 : 40) < 22 ? 1 : 0.05),
    }}
  />
);

export const TerminalWindow = ({
  command,
  typed,
  frame,
  x,
  y,
  width,
  height,
  title = 'zisla — zsh',
  opacity = 1,
  scale = 1,
  output,
}: TerminalWindowProps) => {
  const shown = command.slice(0, Math.floor(typed));
  return (
    <div
      className="absolute flex flex-col overflow-hidden"
      style={{
        left: x,
        top: y,
        width,
        height,
        opacity,
        transform: `scale(${scale})`,
        transformOrigin: 'center',
        borderRadius: 10,
        background: 'rgba(11,11,13,0.93)',
        border: `1px solid ${white(0.11)}`,
        boxShadow: '0 34px 80px rgba(0,0,0,0.62)',
      }}
    >
      <div className="flex h-7 shrink-0 items-center gap-2 px-3">
        <div className="flex items-center gap-[6px]">
          {['#ff5f57', '#febc2e', '#28c840'].map((dot) => (
            <div key={dot} style={{width: 11, height: 11, borderRadius: 6, background: dot}} />
          ))}
        </div>
        <div className="flex-1 text-center text-[11px] font-medium text-label-3">{title}</div>
        <div style={{width: 45}} />
      </div>
      <div style={{height: 1, background: white(0.08)}} />
      <div className="flex-1 px-3 py-[10px] font-mono text-[12.5px] leading-[19px]">
        <div style={{whiteSpace: 'pre-wrap', wordBreak: 'break-all'}}>
          <span style={{color: color.green}}>➜</span>
          <span style={{color: color.cyan}}> ~ </span>
          <span>{shown}</span>
          <Caret frame={frame} />
        </div>
        {output}
      </div>
    </div>
  );
};

export const TerminalLine = ({children, opacity = 1, tint}: {children: ReactNode; opacity?: number; tint?: string}) => (
  <div className="truncate" style={{opacity, color: tint ?? white(0.72)}}>
    {children}
  </div>
);
