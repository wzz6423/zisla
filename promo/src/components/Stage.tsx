import type {FC, ReactNode} from 'react';
import {AbsoluteFill, useVideoConfig} from 'remotion';
import {STAGE} from '../theme';

// 1280×720 pt 的逻辑画布，等比放大到合成尺寸（1080p 为 1.5×，4K 为 3×）
export const Stage: FC<{children: ReactNode; opacity?: number}> = ({children, opacity = 1}) => {
  const {width} = useVideoConfig();
  return (
    <AbsoluteFill style={{backgroundColor: '#000', opacity}}>
      <div
        className="relative overflow-hidden font-sans text-label"
        style={{
          width: STAGE.width,
          height: STAGE.height,
          transform: `scale(${width / STAGE.width})`,
          transformOrigin: '0 0',
        }}
      >
        {children}
      </div>
    </AbsoluteFill>
  );
};

// 让画布上的 (x, y) 尽量落在画面中心；平移量被钳制，推近时不会露出画布之外
export const Camera: FC<{scale: number; x: number; y: number; children: ReactNode}> = ({scale, x, y, children}) => {
  const translateX = Math.min(0, Math.max(STAGE.width * (1 - scale), STAGE.width / 2 - x * scale));
  const translateY = Math.min(0, Math.max(STAGE.height * (1 - scale), STAGE.height / 2 - y * scale));
  return (
    <div
      className="absolute left-0 top-0"
      style={{
        width: STAGE.width,
        height: STAGE.height,
        transform: `translate(${translateX}px, ${translateY}px) scale(${scale})`,
        transformOrigin: '0 0',
      }}
    >
      {children}
    </div>
  );
};
