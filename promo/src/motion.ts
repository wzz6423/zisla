import {Easing, interpolate, spring} from 'remotion';

export type SpringPreset = {stiffness: number; damping: number};

// SwiftUI 的 duration/bounce 弹簧在 mass = 1 时的等价刚度与阻尼，
// 这样片中的回弹量与 mac/Sources/Zisla/MotionDesign.swift 里的 ZislaMotion 一致。
const swiftUISpring = (duration: number, bounce: number): SpringPreset => ({
  stiffness: ((2 * Math.PI) / duration) ** 2,
  damping: (4 * Math.PI * (1 - bounce)) / duration,
});

export const ZislaMotion = {
  islandReveal: swiftUISpring(0.22, 0.2),
  islandRecycle: swiftUISpring(0.22, 0),
  surfaceResize: swiftUISpring(0.34, 0.17),
  moduleSwitch: swiftUISpring(0.32, 0),
  selection: swiftUISpring(0.26, 0.23),
  hover: swiftUISpring(0.18, 0.15),
  notice: swiftUISpring(0.2, 0.15),
  // .spring(response: 0.3, dampingFraction: 0.85)
  quickAction: swiftUISpring(0.3, 0.15),
} as const;

// 字幕、镜头、便当格等影片层元素用的弹簧，不对应应用内动画
export const FilmMotion = {
  gentle: {stiffness: 90, damping: 20},
  title: {stiffness: 140, damping: 22},
  pop: {stiffness: 260, damping: 20},
} as const;

export const springAt = (
  frame: number,
  fps: number,
  start: number,
  preset: SpringPreset,
  durationInFrames?: number,
): number =>
  spring({
    frame: frame - start,
    fps,
    config: {mass: 1, stiffness: preset.stiffness, damping: preset.damping},
    durationInFrames,
  });

const easeInOut = Easing.bezier(0.42, 0, 0.58, 1);
const easeOut = Easing.bezier(0.16, 1, 0.3, 1);

export const ease = (frame: number, range: readonly [number, number], output: readonly [number, number]): number =>
  interpolate(frame, [range[0], range[1]], [output[0], output[1]], {
    easing: easeInOut,
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

export const easeOutAt = (frame: number, range: readonly [number, number], output: readonly [number, number]): number =>
  interpolate(frame, [range[0], range[1]], [output[0], output[1]], {
    easing: easeOut,
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

export const linear = (frame: number, range: readonly [number, number], output: readonly [number, number]): number =>
  interpolate(frame, [range[0], range[1]], [output[0], output[1]], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

// 在 [start, end] 内出现、之后消失的 0→1→0 包络
export const fadeWindow = (frame: number, start: number, end: number, fade = 14): number =>
  Math.min(linear(frame, [start, start + fade], [0, 1]), linear(frame, [end - fade, end], [1, 0]));

export type Keyframe = readonly [frame: number, value: number];

// 关键帧之间用缓入缓出衔接，光标轨迹和镜头运动都走它
export const track = (frame: number, keyframes: readonly Keyframe[]): number => {
  const first = keyframes[0];
  const last = keyframes[keyframes.length - 1];
  if (!first || !last) {
    return 0;
  }
  if (frame <= first[0]) {
    return first[1];
  }
  for (let index = 1; index < keyframes.length; index++) {
    const previous = keyframes[index - 1];
    const current = keyframes[index];
    if (previous && current && frame <= current[0]) {
      return ease(frame, [previous[0], current[0]], [previous[1], current[1]]);
    }
  }
  return last[1];
};
