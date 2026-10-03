/**
 * Headless smoke test for the showcase page.
 *
 * Boots the built page in Chrome, scrubs the whole timeline, exercises the
 * transport controls and a spread of viewport sizes, and fails on any console
 * error, page error, or failed request. It also prints the WebGL renderer
 * string, so a silent software-rasteriser fallback is visible rather than
 * mistaken for a passing render.
 *
 * Uses `channel: 'chrome'` (the installed Google Chrome) so the check needs no
 * Playwright browser download. Override with SHOWCASE_BROWSER_CHANNEL=chromium
 * to use a downloaded Chromium instead.
 *
 * Run: npm run verify:showcase
 */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const ROOT = new URL('../dist/', import.meta.url).pathname;
const PORT = 4188;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
};

const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', 'http://localhost');
  const relative = url.pathname === '/' ? '/showcase.html' : url.pathname;
  // normalize() collapses `..` so a request cannot escape dist/.
  const target = join(ROOT, normalize(relative).replace(/^(\.\.[/\\])+/, ''));
  try {
    const body = await readFile(target);
    response.writeHead(200, { 'content-type': MIME[extname(target)] ?? 'application/octet-stream' });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end('not found');
  }
});

await new Promise((resolve) => server.listen(PORT, resolve));

const browser = await chromium.launch({
  channel: process.env.SHOWCASE_BROWSER_CHANNEL ?? 'chrome',
  args: ['--use-gl=angle', '--enable-unsafe-swiftshader', '--disable-gpu-sandbox'],
});
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

const problems = [];
page.on('console', (message) => {
  if (message.type() === 'error' || message.type() === 'warning') {
    problems.push(`[console.${message.type()}] ${message.text()}`);
  }
});
page.on('pageerror', (error) => problems.push(`[pageerror] ${error.message}`));
page.on('requestfailed', (request) =>
  problems.push(`[requestfailed] ${request.url()} ${request.failure()?.errorText ?? ''}`),
);

// Autoplay is disabled by emulating reduced motion, so the film holds still and
// the test controls the clock explicitly.
await page.emulateMedia({ reducedMotion: 'reduce' });
await page.goto(`http://localhost:${PORT}/showcase.html`, { waitUntil: 'load' });

const renderer = await page.evaluate(() => {
  const canvas = document.createElement('canvas');
  const gl = canvas.getContext('webgl2') ?? canvas.getContext('webgl');
  if (!gl) return 'none';
  const info = gl.getExtension('WEBGL_debug_renderer_info');
  return info ? String(gl.getParameter(info.UNMASKED_RENDERER_WEBGL)) : 'unknown';
});

// Chapter starts and a few interior moments, so every scene is exercised.
const TOTAL = await page.evaluate(() => {
  const scrubber = document.querySelector('.showcase-scrubber');
  return Number.parseFloat(scrubber?.getAttribute('max') ?? '0');
});

const marks = [0, 3, 7.5, 12, 17, 22, 27, 31, 36, 41, 46, TOTAL];
for (const time of marks) {
  await page.evaluate((value) => {
    const scrubber = document.querySelector('.showcase-scrubber');
    if (!(scrubber instanceof HTMLInputElement)) throw new Error('scrubber missing');
    scrubber.value = String(value);
    scrubber.dispatchEvent(new Event('input', { bubbles: true }));
  }, time);
  // Two frames: one to apply the seek, one to render it.
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

// Transport controls. Rewind first: pressing play while parked on the last
// frame intentionally restarts from 0, which would mask real advancement.
await page.evaluate(() => {
  const scrubber = document.querySelector('.showcase-scrubber');
  scrubber.value = '10';
  scrubber.dispatchEvent(new Event('input', { bubbles: true }));
});
await page.click('.showcase-play');
await page.waitForTimeout(400);
const advancedTo = await page.evaluate(() =>
  Number.parseFloat(document.querySelector('.showcase-scrubber')?.value ?? '0'),
);
const advancedWhilePlaying = advancedTo > 10;

// Pause must actually stop the clock.
await page.click('.showcase-play');
const pausedAt = await page.evaluate(() =>
  Number.parseFloat(document.querySelector('.showcase-scrubber')?.value ?? '0'),
);
await page.waitForTimeout(300);
const stillAt = await page.evaluate(() =>
  Number.parseFloat(document.querySelector('.showcase-scrubber')?.value ?? '0'),
);
const pauseHolds = Math.abs(stillAt - pausedAt) < 0.01;

if (!advancedWhilePlaying) problems.push(`[transport] play did not advance past 10 (got ${advancedTo})`);
if (!pauseHolds) problems.push(`[transport] pause did not hold: ${pausedAt} -> ${stillAt}`);

// Restart-from-end is the documented behaviour of the play button.
await page.evaluate(() => {
  const scrubber = document.querySelector('.showcase-scrubber');
  scrubber.value = String(Number.parseFloat(scrubber.max));
  scrubber.dispatchEvent(new Event('input', { bubbles: true }));
});
await page.click('.showcase-play');
await page.waitForTimeout(200);
const restartedAt = await page.evaluate(() =>
  Number.parseFloat(document.querySelector('.showcase-scrubber')?.value ?? '0'),
);
if (restartedAt > 1) {
  problems.push(`[transport] play from the end did not restart (got ${restartedAt})`);
}

// Keyboard: space toggles, digits jump to a chapter. Chapter titles are applied
// by the render loop, so wait a frame before reading them back.
await page.keyboard.press('Digit3');
await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
const chapterAfterDigit = await page.evaluate(
  () => document.querySelector('.showcase-chapter.is-active')?.textContent?.trim() ?? '',
);

// Responsive sweep, including the portrait fov boost path.
for (const [width, height] of [[1920, 1080], [1280, 800], [900, 1200], [420, 780], [360, 640]]) {
  await page.setViewportSize({ width, height });
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const canvas = await page.evaluate(() => {
    const element = document.querySelector('.showcase-canvas');
    if (!(element instanceof HTMLCanvasElement)) throw new Error('canvas missing');
    return { width: element.width, height: element.height };
  });
  if (canvas.width < 1 || canvas.height < 1) {
    problems.push(`[resize] canvas collapsed at ${width}x${height}: ${canvas.width}x${canvas.height}`);
  }
}

// Every chapter must actually put geometry on screen, not just report itself
// active. This is what caught a scene whose objects were all at opacity 0.
const chapterChecks = [
  ['opening', 5],
  ['context', 11],
  ['features', 21],
  ['highlights', 33],
  ['outro', 49],
];
for (const [id, time] of chapterChecks) {
  await page.evaluate((value) => {
    const scrubber = document.querySelector('.showcase-scrubber');
    scrubber.value = String(value);
    scrubber.dispatchEvent(new Event('input', { bubbles: true }));
  }, time);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const state = await page.evaluate(() => window.__zislaShowcase?.debugState());
  const scene = state.scenes.find((entry) => entry.name === id);
  if (!scene?.visible) {
    problems.push(`[scene] ${id} is not visible at ${time}s`);
  } else if (scene.opaqueObjects === 0) {
    problems.push(`[scene] ${id} is visible but has no opaque objects at ${time}s`);
  }
  if (state.activeChapter !== id) {
    problems.push(`[scene] active chapter at ${time}s is "${state.activeChapter}", expected "${id}"`);
  }
  // A camera sitting at the origin would mean the director never ran.
  if (state.cameraPosition[2] <= 0) {
    problems.push(`[scene] camera is inside the subject at ${time}s (z=${state.cameraPosition[2]})`);
  }
}

const titles = await page.evaluate(() =>
  [...document.querySelectorAll('.showcase-chapter')].map((node) => node.textContent?.trim() ?? ''),
);

if (chapterAfterDigit !== titles[2]) {
  problems.push(`[keyboard] Digit3 activated "${chapterAfterDigit}", expected "${titles[2]}"`);
}

await page.setViewportSize({ width: 1440, height: 900 });
await page.screenshot({ path: new URL('../showcase-verify.png', import.meta.url).pathname });

await browser.close();
server.close();

console.log(`renderer: ${renderer}`);
console.log(`timeline: ${TOTAL.toFixed(1)}s, scrubbed ${marks.length} marks`);
console.log(`chapters: ${titles.join(' | ')}`);
console.log(`transport: play 10 -> ${advancedTo.toFixed(2)}, pause held at ${stillAt.toFixed(2)}, replay from end -> ${restartedAt.toFixed(2)}`);
console.log(`keyboard: Digit3 activated chapter "${chapterAfterDigit}"`);
console.log(`scenes: ${chapterChecks.map(([id, time]) => `${id}@${time}s`).join(', ')}`);

if (problems.length > 0) {
  console.error(`\n${problems.length} problem(s):`);
  problems.forEach((entry) => console.error(`  ${entry}`));
  process.exit(1);
}
console.log('\nno console errors, page errors, or failed requests');