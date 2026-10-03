/**
 * Overlay UI: chapter titles, transport bar and keyboard shortcuts.
 *
 * Text lives in the DOM rather than in the 3D scene so it stays crisp, wraps on
 * narrow windows, and is reachable by a screen reader. The overlay is also the
 * only place that auto-hides, which keeps the frame clean during playback.
 */
import { chapters, totalDuration } from './chapters';
import { formatTimecode, type ShowcaseCopy } from './script';
import type { Transport } from './transport';

export interface Overlay {
  element: HTMLElement;
  /** Re-reads the transport; call on every transport change. */
  sync(): void;
  /** Updates the on-screen chapter titles. */
  setChapter(id: string): void;
  destroy(): void;
}

const CHAPTER_ORDER = chapters.map((chapter) => chapter.id);
type ChapterOrderEntry = (typeof CHAPTER_ORDER)[number];

export const createOverlay = (
  container: HTMLElement,
  transport: Transport,
  copy: ShowcaseCopy,
  options: { onSeek: () => void; onReplay: () => void },
): Overlay => {
  const root = document.createElement('div');
  root.className = 'showcase-ui';

  // --- Chapter titles -------------------------------------------------------
  const captionBlock = document.createElement('div');
  captionBlock.className = 'showcase-caption';

  const kicker = document.createElement('p');
  kicker.className = 'showcase-kicker';

  const title = document.createElement('h1');
  title.className = 'showcase-title';

  const caption = document.createElement('p');
  caption.className = 'showcase-caption-text';

  captionBlock.append(kicker, title, caption);
  root.append(captionBlock);

  // --- Transport bar --------------------------------------------------------
  const bar = document.createElement('div');
  bar.className = 'showcase-bar';

  const playButton = document.createElement('button');
  playButton.type = 'button';
  playButton.className = 'showcase-button showcase-play';
  playButton.setAttribute('aria-label', copy.transport.pause);

  const playIcon = document.createElement('span');
  playIcon.className = 'showcase-icon showcase-icon-pause';
  playButton.append(playIcon);

  const timeLabel = document.createElement('span');
  timeLabel.className = 'showcase-time';

  // The range input is the scrubber; a plain <input type="range"> gives us
  // keyboard arrows and assistive-tech support for free.
  const scrubber = document.createElement('input');
  scrubber.type = 'range';
  scrubber.className = 'showcase-scrubber';
  scrubber.min = '0';
  scrubber.max = String(totalDuration);
  scrubber.step = '0.01';
  scrubber.value = '0';
  scrubber.setAttribute('aria-label', copy.transport.progress);
  scrubber.setAttribute('aria-valuemin', '0');
  scrubber.setAttribute('aria-valuemax', String(Math.floor(totalDuration)));

  const chapterList = document.createElement('ol');
  chapterList.className = 'showcase-chapters';
  chapterList.setAttribute('aria-label', copy.transport.chapters);

  const chapterButtons: HTMLButtonElement[] = chapters.map((chapter, index) => {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'showcase-chapter';
    button.textContent = copy.chapters[chapter.id].kicker;
    button.title = copy.transport.skipToChapter;
    button.setAttribute('aria-label', `${copy.transport.skipToChapter}: ${copy.chapters[chapter.id].title}`);
    button.addEventListener('click', () => {
      transport.seekChapter(chapter.id);
      options.onSeek();
    });
    item.append(button);
    chapterList.append(item);
    void index;
    return button;
  });

  const replayButton = document.createElement('button');
  replayButton.type = 'button';
  replayButton.className = 'showcase-button';
  replayButton.textContent = copy.transport.replay;
  replayButton.addEventListener('click', options.onReplay);

  const fullscreenButton = document.createElement('button');
  fullscreenButton.type = 'button';
  fullscreenButton.className = 'showcase-button';
  fullscreenButton.textContent = '⛶';
  fullscreenButton.setAttribute('aria-label', copy.transport.enterFullscreen);

  const toggleFullscreen = (): void => {
    if (document.fullscreenElement) {
      void document.exitFullscreen().catch(() => undefined);
      return;
    }
    const target = container.requestFullscreen?.();
    if (target && typeof target.catch === 'function') target.catch(() => undefined);
  };
  fullscreenButton.addEventListener('click', toggleFullscreen);
  document.addEventListener('fullscreenchange', () => {
    const active = Boolean(document.fullscreenElement);
    fullscreenButton.setAttribute('aria-label', active ? copy.transport.exitFullscreen : copy.transport.enterFullscreen);
  });

  bar.append(playButton, timeLabel, scrubber, chapterList, replayButton, fullscreenButton);
  root.append(bar);
  container.append(root);

  const notice = document.createElement('p');
  notice.className = 'showcase-notice';
  notice.textContent = copy.transport.reducedMotionNotice;
  container.append(notice);

  playButton.addEventListener('click', () => transport.toggle());

  scrubber.addEventListener('input', () => {
    transport.seek(Number.parseFloat(scrubber.value));
    options.onSeek();
  });

  // --- Idle auto-hide -------------------------------------------------------
  let idleTimer = 0;
  const wake = (): void => {
    root.classList.remove('is-idle');
    window.clearTimeout(idleTimer);
    idleTimer = window.setTimeout(() => {
      // Controls stay up while paused, since that is when they are needed.
      if (transport.playing) root.classList.add('is-idle');
    }, 2600);
  };
  const events: (keyof WindowEventMap)[] = ['pointermove', 'pointerdown', 'keydown'];
  events.forEach((event) => window.addEventListener(event, wake, { passive: true }));
  wake();

  // --- Keyboard -------------------------------------------------------------
  const onKeyDown = (event: KeyboardEvent): void => {
    const target = event.target as HTMLElement | null;
    const inFormControl =
      target instanceof HTMLElement && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName);

    // A focused scrubber owns its own arrow keys: its native ±step behaviour is
    // finer-grained than the global ±5s seek, and hijacking it would break
    // keyboard-only trimming. Space still toggles playback from there.
    if (inFormControl && ![' ', 'Escape'].includes(event.key)) return;

    switch (event.key) {
      case ' ':
      case 'k':
      case 'K':
        event.preventDefault();
        transport.toggle();
        break;
      case 'ArrowRight':
        event.preventDefault();
        transport.seek(transport.time + 5);
        options.onSeek();
        break;
      case 'ArrowLeft':
        event.preventDefault();
        transport.seek(transport.time - 5);
        options.onSeek();
        break;
      case 'Home':
        event.preventDefault();
        transport.seek(0);
        options.onSeek();
        break;
      case 'End':
        event.preventDefault();
        transport.seek(totalDuration);
        options.onSeek();
        break;
      case 'f':
      case 'F':
        toggleFullscreen();
        break;
      default:
        if (/^[1-9]$/.test(event.key)) {
          const chapter = CHAPTER_ORDER[Number.parseInt(event.key, 10) - 1];
          if (chapter && transport.seekChapter(chapter)) {
            options.onSeek();
            event.preventDefault();
          }
        }
    }
  };
  window.addEventListener('keydown', onKeyDown);

  // --- Sync -----------------------------------------------------------------
  let lastShownSecond = -1;

  /**
   * Refreshes the timecode and the scrubber.
   *
   * This runs on its own animation frame rather than on `transport.onChange`,
   * because the transport only emits on discrete events (play, pause, seek) —
   * listening to it alone would freeze the progress bar for the whole time the
   * film is actually playing.
   */
  const sync = (): void => {
    const time = transport.time;
    // The second-resolution readout only needs redrawing when it changes.
    const second = Math.floor(time);
    if (second !== lastShownSecond) {
      lastShownSecond = second;
      timeLabel.textContent = copy.transport.timeTemplate
        .replace('{current}', formatTimecode(time))
        .replace('{total}', formatTimecode(totalDuration));
    }

    // Never fight the viewer while they are dragging the scrubber.
    if (document.activeElement !== scrubber) scrubber.value = String(time);
    scrubber.setAttribute('aria-valuetext', `${formatTimecode(time)} / ${formatTimecode(totalDuration)}`);

    const playing = transport.playing;
    playIcon.classList.toggle('is-playing', playing);
    playButton.setAttribute('aria-label', playing ? copy.transport.pause : copy.transport.play);
    root.classList.toggle('is-playing', playing);
    root.classList.toggle('is-ended', time >= totalDuration - 1e-3);
  };

  let uiFrame = 0;
  const tick = (): void => {
    sync();
    uiFrame = requestAnimationFrame(tick);
  };
  uiFrame = requestAnimationFrame(tick);

  const setChapter = (id: string): void => {
    const index = CHAPTER_ORDER.indexOf(id as ChapterOrderEntry);
    const chapter = chapters[index];
    if (!chapter) return;

    const text = copy.chapters[chapter.id];
    kicker.textContent = text.kicker;
    title.textContent = text.title;
    caption.textContent = text.caption;

    // Restart the CSS entrance animation on every chapter change.
    captionBlock.classList.remove('is-visible');
    void captionBlock.offsetWidth;
    captionBlock.classList.add('is-visible');

    chapterButtons.forEach((button, position) => {
      button.classList.toggle('is-active', position === index);
      button.setAttribute('aria-current', position === index ? 'true' : 'false');
    });
  };

  sync();
  setChapter(CHAPTER_ORDER[0]);

  return {
    element: root,
    sync,
    setChapter,
    destroy: () => {
      cancelAnimationFrame(uiFrame);
      window.clearTimeout(idleTimer);
      events.forEach((event) => window.removeEventListener(event, wake));
      window.removeEventListener('keydown', onKeyDown);
      root.remove();
      notice.remove();
    },
  };
};