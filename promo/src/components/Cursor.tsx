import type {FC} from 'react';

// 箭头尖端位于 (x, y)
export const Cursor: FC<{x: number; y: number; pressed?: number; opacity?: number}> = ({
  x,
  y,
  pressed = 0,
  opacity = 1,
}) => (
  <svg
    width={20}
    height={26}
    viewBox="0 0 20 26"
    className="absolute"
    style={{
      left: x - 2,
      top: y - 2,
      opacity,
      transform: `scale(${1 - pressed * 0.1})`,
      transformOrigin: '2px 2px',
      filter: 'drop-shadow(0 1px 1.5px rgba(0,0,0,0.45))',
    }}
  >
    <path
      d="M2 2 L2 20.4 L6.5 16.3 L9.5 23.5 L12.6 22.2 L9.7 15.2 L15.9 15.2 Z"
      fill="#000"
      stroke="#fff"
      strokeWidth={1.3}
      strokeLinejoin="round"
    />
  </svg>
);

// 点击时从光标尖端扩散的一圈提示，progress 为 0→1
export const ClickRipple: FC<{x: number; y: number; progress: number}> = ({x, y, progress}) => {
  if (progress <= 0 || progress >= 1) {
    return null;
  }
  const size = 10 + progress * 34;
  return (
    <div
      className="absolute rounded-full"
      style={{
        left: x - size / 2,
        top: y - size / 2,
        width: size,
        height: size,
        border: '1.5px solid rgba(255,255,255,0.9)',
        opacity: 1 - progress,
      }}
    />
  );
};
