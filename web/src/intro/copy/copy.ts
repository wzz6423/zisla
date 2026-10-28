/**
 * Copy contract for the three.js introduction film.
 *
 * The film is a six-beat loop: the island forms, expands once, and then
 * four chapters are staged inside that single expanded surface before it
 * collapses and the wordmark returns. Every string below is spoken by the
 * narration track or UI labels.
 */

/** Beats the timeline can land on. `chapter` is 1-based. */
export type ChapterId = 1 | 2 | 3 | 4;

export const chapterIds = [1, 2, 3, 4] as const satisfies readonly ChapterId[];

export interface ChapterCopy {
  /** Dashed kicker above the headline, e.g. "AI WORKFLOW". */
  kicker: string;
  title: string;
  /** One or two sentences. The reveal animation fades this in last. */
  body: string;
  /**
   * Label pinned to the module card the chapter highlights. Kept to the names
   * the app and the website already use, so the film never invents a term.
   */
  module: string;
  /** Second label for chapters that light up two cards at once. */
  moduleAlt?: string;
}

export interface IntroCopy {
  meta: {
    title: string;
    description: string;
  };
  /** Small mono label above the opening headline. */
  kicker: string;
  /** Opening headline. Rendered as authored markup with <br> and <em>. */
  headline: string;
  /** Supporting line under the opening headline. */
  lede: string;
  /** Bottom-left caption for the one-beat island demonstration. */
  scene: string;
  chapters: Record<ChapterId, ChapterCopy>;
  outro: {
    kicker: string;
    /** Closing headline, authored markup like `headline`. */
    title: string;
    body: string;
    cta: string;
  };
  ui: {
    play: string;
    pause: string;
    replay: string;
    /** Accessible name for the chapter scrubber. */
    timeline: string;
    /** Accessible name for the language picker. */
    language: string;
    /** Toggle that removes every non-essential animation. */
    reduceMotion: string;
    /** Screen-reader live region announces the beat being staged. */
    screenReaderSummary: string;
    /** "Chapter {current} of {total}"; word order differs per locale. */
    chapterOf: string;
    /** Label on the link that closes the film. */
    download: string;
  };
}
