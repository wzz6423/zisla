/**
 * Playback clock.
 *
 * Time is advanced from measured frame deltas and clamped per frame, so a
 * backgrounded tab resumes where it left off instead of jumping. Every consumer
 * reads `time`, which makes the whole animation a pure function of one number —
 * the property that lets the progress bar scrub accurately.
 */
import { chapters, totalDuration } from './chapters';

export interface Transport {
  time: number;
  playing: boolean;
  /** False when the viewer has taken manual control of the timeline. */
  duration: number;
  play(): void;
  pause(): void;
  toggle(): void;
  seek(time: number): void;
  /** Jumps to a chapter start. */
  seekChapter(id: string): boolean;
  restart(): void;
  /** Called once per animation frame with the elapsed seconds. */
  advance(delta: number): void;
  onChange(listener: () => void): void;
  dispose(): void;
}

const MAX_DELTA = 1 / 12;

export const createTransport = (onEnded?: () => void): Transport => {
  const listeners = new Set<() => void>();
  let time = 0;
  let playing = false;
  let ended = false;

  const emit = (): void => {
    listeners.forEach((listener) => listener());
  };

  const play = (): void => {
    // Replaying from the very end restarts rather than sitting on the last frame.
    if (time >= totalDuration - 1e-3) time = 0;
    ended = false;
    playing = true;
    emit();
  };

  const pause = (): void => {
    playing = false;
    emit();
  };

  const seek = (value: number): void => {
    time = Math.min(Math.max(0, value), totalDuration);
    ended = false;
    emit();
  };

  const transport: Transport = {
    get time() {
      return time;
    },
    get playing() {
      return playing;
    },
    duration: totalDuration,
    play,
    pause,
    toggle: () => (playing ? pause() : play()),
    seek,
    /** Jumps to a chapter start; returns false for an unknown id. */
    seekChapter: (id) => {
      const chapter = chapters.find((entry) => entry.id === id);
      if (!chapter) return false;
      // Land just after the crossfade so the chapter is fully opaque on arrival.
      seek(chapter.start + 0.05);
      return true;
    },
    restart: () => {
      time = 0;
      ended = false;
      playing = true;
      emit();
    },
    advance: (delta) => {
      if (!playing) return;
      time += Math.min(delta, MAX_DELTA);
      if (time >= totalDuration) {
        time = totalDuration;
        playing = false;
        if (!ended) {
          ended = true;
          onEnded?.();
        }
        emit();
      }
    },
    onChange: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    dispose: () => listeners.clear(),
  };

  return transport;
};