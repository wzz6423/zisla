/**
 * Captures one PNG per chapter so the composition can be reviewed by eye.
 * Run: node scripts/capture-showcase.mjs [outputDir]
 */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const ROOT = new URL('../dist/', import.meta.url).pathname;
const OUT = process.argv[2] ?? new URL('../showcase-frames/', import.meta.url).pathname;
const PORT = 4189;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
};

const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', 'http://localhost');
  const relative = url.pathname === '/' ? '/showcase.html' : url.pathname;
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
await mkdir(OUT, { recursive: true });

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
// Hold the clock so each capture is the exact requested frame.
await page.emulateMedia({ reducedMotion: 'reduce' });
await page.goto(`http://localhost:${PORT}/showcase.html`, { waitUntil: 'load' });

const marks = [
  ['01-opening', 5],
  ['02-context', 11],
  ['03-features', 21],
  ['04-highlights', 33],
  ['05-outro', 49],
];

for (const [name, time] of marks) {
  await page.evaluate((value) => {
    const scrubber = document.querySelector('.showcase-scrubber');
    scrubber.value = String(value);
    scrubber.dispatchEvent(new Event('input', { bubbles: true }));
  }, time);
  await page.evaluate(
    () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
  );
  // Let the 200ms CSS transitions on the titles and chapter tabs settle, so the
  // capture shows the resting state rather than a frame mid-fade.
  await page.waitForTimeout(450);
  await page.screenshot({ path: join(OUT, `${name}.png`) });
  console.log(`captured ${name}.png at ${time}s`);
}

await browser.close();
server.close();