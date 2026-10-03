/**
 * Captures the same chapter across several viewport shapes, to check the
 * responsive layout (including the portrait fov boost path).
 * Run: node scripts/capture-responsive.mjs [outputDir]
 */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const ROOT = new URL('../dist/', import.meta.url).pathname;
const OUT = process.argv[2] ?? new URL('../showcase-responsive/', import.meta.url).pathname;
const PORT = 4192;
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png' };

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
const page = await browser.newPage();
await page.emulateMedia({ reducedMotion: 'reduce' });

const shapes = [
  ['desktop-1920x1080', 1920, 1080],
  ['laptop-1280x800', 1280, 800],
  ['short-1200x560', 1200, 560],
  ['portrait-900x1200', 900, 1200],
  ['phone-420x780', 420, 780],
];

for (const [name, width, height] of shapes) {
  await page.setViewportSize({ width, height });
  await page.goto(`http://localhost:${PORT}/showcase.html`, { waitUntil: 'load' });
  await page.evaluate(() => {
    const scrubber = document.querySelector('.showcase-scrubber');
    scrubber.value = '21';
    scrubber.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  await page.waitForTimeout(450);
  await page.screenshot({ path: join(OUT, `${name}.png`) });
  const info = await page.evaluate(() => {
    const canvas = document.querySelector('.showcase-canvas');
    const state = window.__zislaShowcase?.debugState();
    const bar = document.querySelector('.showcase-bar');
    return {
      canvas: `${canvas.width}x${canvas.height}`,
      fov: state?.cameraFov,
      barWidth: Math.round(bar.getBoundingClientRect().width),
      viewport: window.innerWidth,
    };
  });
  console.log(`${name}: canvas ${info.canvas}, fov ${info.fov}, bar ${info.barWidth}/${info.viewport}`);
}

await browser.close();
server.close();