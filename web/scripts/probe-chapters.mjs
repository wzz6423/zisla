/**
 * Dumps the chapter-button DOM state, to check label/highlight alignment.
 * Run: node scripts/probe-chapters.mjs <seconds>
 */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const ROOT = new URL('../dist/', import.meta.url).pathname;
const TIME = Number.parseFloat(process.argv[2] ?? '33');
const PORT = 4191;
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

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
await page.emulateMedia({ reducedMotion: 'reduce' });
await page.goto(`http://localhost:${PORT}/showcase.html`, { waitUntil: 'load' });
await page.evaluate((value) => {
  const scrubber = document.querySelector('.showcase-scrubber');
  scrubber.value = String(value);
  scrubber.dispatchEvent(new Event('input', { bubbles: true }));
}, TIME);
await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));

// The chapter buttons transition colour/background over 200ms, so read them
// after the transition has settled rather than two frames after the seek.
await page.waitForTimeout(400);

const dump = await page.evaluate(() => ({
  title: document.querySelector('.showcase-title')?.textContent?.trim(),
  buttons: [...document.querySelectorAll('.showcase-chapter')].map((node) => ({
    text: node.textContent?.trim(),
    active: node.classList.contains('is-active'),
    color: getComputedStyle(node).color,
    background: getComputedStyle(node).backgroundColor,
  })),
}));
console.log(`t=${TIME}s  title="${dump.title}"`);
dump.buttons.forEach((b, i) =>
  console.log(`  [${i}] "${b.text}" active=${b.active} color=${b.color} bg=${b.background}`),
);

await browser.close();
server.close();