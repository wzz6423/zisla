/**
 * Entry point for `/showcase`.
 *
 * Resolves the locale the same way the marketing site does, so the animation
 * speaks the visitor's language without a second preference mechanism.
 */
import { resolvePreferredLocale } from '../locales';
import { showcaseCopy } from './script';
import { createPlayer, type Player } from './player';
import { createOverlay } from './overlay';
import { createTransport } from './transport';
import './showcase.css';

const container = document.getElementById('showcase');
if (!container) {
  throw new Error('Showcase root element is missing from the page.');
}

const locale = resolvePreferredLocale([...navigator.languages]);
const copy = showcaseCopy(locale);

document.title = copy.documentTitle;
document.documentElement.lang = locale;

const prefersReducedMotion =
  typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// One clock shared by the player and the overlay, so the UI can never disagree
// with the scene about where the film is. The overlay and the player each hold
// the other through a small forward reference, since scrubbing needs the camera
// to drop its smoothing.
const transport = createTransport();

let player: Player;

const overlay = createOverlay(container, transport, copy, {
  onSeek: () => player.resetCamera(),
  onReplay: () => transport.restart(),
});

player = createPlayer(container, copy, transport, {
  onChapterChange: (id) => overlay.setChapter(id),
  onTransportChange: () => overlay.sync(),
});

if (!prefersReducedMotion) {
  // Start after one frame so the first visible composition is the poster pose,
  // not a half-laid-out canvas.
  window.requestAnimationFrame(() => transport.play());
}

// Verification hook: `__zislaShowcase.debugState()` reports what is actually on
// screen, so the smoke test can assert scene contents instead of guessing from
// pixels. Read-only, and harmless in production.
declare global {
  interface Window {
    __zislaShowcase?: { debugState: () => unknown };
  }
}
window.__zislaShowcase = { debugState: player.debugState };

window.addEventListener('pagehide', () => {
  player.destroy();
  overlay.destroy();
  transport.dispose();
});