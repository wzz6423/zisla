/**
 * Small math helpers shared by every scene.
 *
 * Every animation in the showcase is a pure function of the timeline position,
 * so all of these take an explicit `t` instead of accumulating frame deltas.
 * That is what makes scrubbing the progress bar frame-accurate.
 */

export const clamp = (value: number, min: number, max: number): number =>
  value < min ? min : value > max ? max : value;

export const clamp01 = (value: number): number => clamp(value, 0, 1);

export const lerp = (from: number, to: number, t: number): number => from + (to - from) * t;

/** Hermite interpolation on the 0..1 range; zero derivative at both ends. */
export const smoothstep = (t: number): number => {
  const x = clamp01(t);
  return x * x * (3 - 2 * x);
};

export const easeInCubic = (t: number): number => {
  const x = clamp01(t);
  return x * x * x;
};

export const easeOutCubic = (t: number): number => 1 - Math.pow(1 - clamp01(t), 3);

export const easeOutQuint = (t: number): number => 1 - Math.pow(1 - clamp01(t), 5);

export const easeInOutCubic = (t: number): number => {
  const x = clamp01(t);
  return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
};

/** Overshoots slightly past 1 before settling, for panel entrances. */
export const easeOutBack = (t: number): number => {
  const x = clamp01(t);
  const c1 = 1.32;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
};

/** Normalized progress of `time` through the `[start, end]` window. */
export const progress = (time: number, start: number, end: number): number =>
  clamp01((time - start) / Math.max(1e-6, end - start));

/**
 * A value that ramps up over `inDuration`, holds, then ramps down over
 * `outDuration`. Used for staggered element entrances.
 */
export const envelope = (
  time: number,
  start: number,
  inDuration: number,
  outStart: number,
  outDuration: number,
): number => {
  const rise = easeOutCubic(progress(time, start, start + inDuration));
  const fall = 1 - easeInCubic(progress(time, outStart, outStart + outDuration));
  return clamp01(rise * fall);
};

/** Deterministic pseudo-random generator so every reload composes the same frame. */
export const createRandom = (seed: number): (() => number) => {
  let state = seed >>> 0 || 1;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    state >>>= 0;
    return state / 0x1_0000_0000;
  };
};