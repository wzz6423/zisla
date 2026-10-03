/**
 * Scene chapters.
 *
 * Chapters overlap by `CHAPTER_OVERLAP` seconds: an outgoing chapter keeps
 * rendering (fading out) while the incoming one is already fading in, so a cut
 * never shows an empty frame. `start` is the moment a chapter begins its own
 * animation, which is also the point its titles appear.
 */
import type { ChapterId } from './script';

export interface Chapter {
  id: ChapterId;
  /** Timeline position where this chapter's animation and titles begin. */
  start: number;
  /** How long the chapter owns the stage before the next one takes over. */
  duration: number;
}

export const CHAPTER_OVERLAP = 0.9;

const DURATIONS: Record<ChapterId, number> = {
  opening: 7.4,
  context: 9.2,
  features: 14.4,
  highlights: 14.4,
  outro: 8.6,
};

const build = (): Chapter[] => {
  const list: Chapter[] = [];
  let cursor = 0;
  (Object.keys(DURATIONS) as ChapterId[]).forEach((id) => {
    list.push({ id, start: cursor, duration: DURATIONS[id] });
    cursor += DURATIONS[id];
  });
  return list;
};

export const chapters: readonly Chapter[] = build();

export const totalDuration: number = chapters.reduce((sum, chapter) => sum + chapter.duration, 0);

export interface ChapterState {
  chapter: Chapter;
  index: number;
  /** 0..1 visibility, already multiplied by the shared crossfade. */
  weight: number;
  /** Seconds since the chapter started, clamped to its own duration. */
  local: number;
  /** 0..1 position inside the chapter. */
  ratio: number;
}

/** Resolves the timeline position into a weighted state for every chapter. */
export const sampleChapters = (time: number): ChapterState[] =>
  chapters.map((chapter, index) => {
    const isFirst = index === 0;
    const isLast = index === chapters.length - 1;
    const fadeInStart = chapter.start - (isFirst ? 0 : CHAPTER_OVERLAP);
    const fadeIn = isFirst ? 1 : smooth01((time - fadeInStart) / CHAPTER_OVERLAP);
    // The last chapter holds to the end of the timeline: fading it out would
    // dissolve the end card on the final frame.
    const fadeOut = isLast ? 1 : 1 - smooth01((time - (chapter.start + chapter.duration)) / CHAPTER_OVERLAP);
    const weight = Math.min(fadeIn, fadeOut);
    const local = Math.min(Math.max(time - chapter.start, 0), chapter.duration);
    return {
      chapter,
      index,
      weight,
      local,
      ratio: chapter.duration > 0 ? local / chapter.duration : 0,
    };
  });

const smooth01 = (t: number): number => {
  const x = t < 0 ? 0 : t > 1 ? 1 : t;
  return x * x * (3 - 2 * x);
};