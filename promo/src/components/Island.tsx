import type {CSSProperties, ReactNode} from 'react';
import {BAR_HEIGHT, ISLAND, NOTCH_WIDTH, STAGE, alpha, black, clamp01, lerp, white} from '../theme';
import {GLASS_BLUR} from './Glass';

export type IslandProgress = {value: number; tint: string};

type IslandProps = {
  // 0 = 收起，1 = 展开；弹簧过冲时会略大于 1，外框跟着过冲，内容不缩放
  reveal: number;
  // 展开后的岛高
  height: number;
  // 收起态单侧翼宽，0 表示只剩刘海
  wing?: number;
  left?: ReactNode;
  right?: ReactNode;
  progress?: IslandProgress;
  opacity?: number;
  children?: ReactNode;
};

const CROWN_FADE: readonly (readonly [number, number])[] = [
  [0, 1],
  [0.15, 0.939],
  [0.3, 0.784],
  [0.5, 0.5],
  [0.7, 0.216],
  [0.85, 0.061],
  [1, 0],
];

// 黑冠让岛体上半截与刘海连成一块：岛高 153 时是 122 实心 + 31 渐变，≥196 时是 132 + 64
const crownFor = (height: number) => {
  const t = clamp01((height - 153) / (196 - 153));
  return {solid: lerp(122, 132, t), fade: lerp(31, 64, t)};
};

const crownGradient = (solid: number, fade: number): string =>
  `linear-gradient(to bottom, #000 0px, ${CROWN_FADE.map(([at, a]) => `${black(a)} ${solid + fade * at}px`).join(', ')})`;

export const Island = ({reveal, height, wing = 0, left, right, progress, opacity = 1, children}: IslandProps) => {
  const open = clamp01(reveal);
  const collapsedWidth = NOTCH_WIDTH + wing * 2;
  const collapsedHeight = BAR_HEIGHT + (progress ? 2 : 0);
  const width = lerp(collapsedWidth, ISLAND.width, reveal);
  const radius = lerp(ISLAND.collapsedBottomRadius, ISLAND.expandedBottomRadius, open);
  const crown = crownFor(height);
  // 收起内容与展开内容在揭示的前 20% 内交接，避免两套内容叠在刘海两侧
  const swap = clamp01(reveal * 5);
  const rimMask = `linear-gradient(to bottom, transparent ${crown.solid * 0.7}px, #000 ${crown.solid + crown.fade}px)`;
  const wingStyle: CSSProperties = {width: wing, height: BAR_HEIGHT, padding: '0 5px', opacity: 1 - swap};

  return (
    <div
      style={{
        position: 'absolute',
        top: 0,
        left: (STAGE.width - width) / 2,
        width,
        height: lerp(collapsedHeight, height, reveal),
        borderRadius: `0 0 ${radius}px ${radius}px`,
        overflow: 'hidden',
        opacity,
        backdropFilter: GLASS_BLUR,
        WebkitBackdropFilter: GLASS_BLUR,
        boxShadow: `0 ${18 * open}px ${56 * open}px ${black(0.5 * open)}`,
      }}
    >
      <div className="absolute inset-0" style={{background: 'rgba(24,24,28,0.5)'}} />
      <div className="absolute inset-0" style={{background: `linear-gradient(to bottom, ${black(0.23)}, ${black(0)})`}} />
      <div
        className="absolute inset-x-0 top-0"
        style={{height: crown.solid + crown.fade, background: crownGradient(crown.solid, crown.fade)}}
      />
      <div className="absolute inset-0 bg-black" style={{opacity: 1 - clamp01(reveal * 1.6)}} />
      <div
        className="absolute inset-0"
        style={{
          borderRadius: 'inherit',
          border: `1px solid ${white(0.14)}`,
          borderTop: 'none',
          boxShadow: `inset 0 0 26px ${white(0.04)}, inset 0 -1px 0 ${white(0.08)}`,
          opacity: open,
          maskImage: rimMask,
          WebkitMaskImage: rimMask,
        }}
      />
      <div
        className="absolute top-0"
        style={{left: (width - ISLAND.width) / 2, width: ISLAND.width, height, opacity: swap}}
      >
        {children}
      </div>
      {wing > 0 && swap < 1 ? (
        <>
          <div
            className="absolute top-0 flex items-center justify-center overflow-hidden"
            style={{...wingStyle, right: `calc(50% + ${NOTCH_WIDTH / 2}px)`}}
          >
            {left}
          </div>
          <div
            className="absolute top-0 flex items-center justify-center overflow-hidden"
            style={{...wingStyle, left: `calc(50% + ${NOTCH_WIDTH / 2}px)`}}
          >
            {right}
          </div>
        </>
      ) : null}
      {progress && swap < 1 ? (
        <div
          className="absolute"
          style={{
            left: radius,
            right: radius,
            bottom: 1.5,
            height: 2,
            borderRadius: 1,
            background: white(0.07),
            opacity: 1 - swap,
          }}
        >
          <div
            style={{
              width: `${clamp01(progress.value) * 100}%`,
              height: 1,
              marginTop: 0.5,
              borderRadius: 0.5,
              background: `linear-gradient(to right, ${alpha(progress.tint, 0.64)}, ${alpha(progress.tint, 0.98)}, ${alpha(progress.tint, 0.7)})`,
            }}
          />
        </div>
      ) : null}
    </div>
  );
};

// 模块切换：进入页从 26pt 外、带 5pt 模糊归位，移出页朝反方向离开。direction 为 1 表示切到右侧的 tab。
export const modulePhase = (progress: number, direction: 1 | -1, entering: boolean): CSSProperties => {
  const away = entering ? 1 - clamp01(progress) : clamp01(progress);
  const sign = entering ? direction : -direction;
  return {
    opacity: 1 - away,
    transform: `translateX(${26 * sign * away}px) scale(${1 - 0.015 * away})`,
    filter: away > 0.001 ? `blur(${5 * away}px)` : undefined,
  };
};
