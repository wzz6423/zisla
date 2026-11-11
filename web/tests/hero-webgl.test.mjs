import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';
import * as THREE from 'three';
import * as locales from '../src/locales.ts';

// Match Vite's catalog resolution while executing the actual page and scene functions.
const sourceRoot = new URL('../src/', import.meta.url);
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('.') && context.parentURL?.startsWith(sourceRoot.href)
      && !/\.[a-z]+$/i.test(specifier)) {
      for (const suffix of ['.ts', '/index.ts']) {
        const candidate = new URL(specifier + suffix, context.parentURL);
        if (existsSync(candidate)) return nextResolve(candidate.href, context);
      }
    }
    return nextResolve(specifier, context);
  },
});
const site = await import('../src/content.ts');
for (const locale of locales.siteLocales) await site.loadSiteContent(locale);
const source = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');
const iconNames = source.match(/const siteIcons = \{([\s\S]*?)\};/)[1].match(/\w+/g);
const pageSource = stripTypeScriptTypes(source.slice(source.indexOf('const app = ')))
  .replace('void showLocale(currentLocale);', '');

function createPage(t, { available = true, reducedMotion = true, hidden = false, setupError } = {}) {
  class Events extends EventTarget {
    listeners = new Map();
    addEventListener(type, callback, options) {
      const callbacks = this.listeners.get(type) ?? new Set();
      callbacks.add(callback);
      this.listeners.set(type, callbacks);
      super.addEventListener(type, callback, options);
    }
    removeEventListener(type, callback, options) {
      this.listeners.get(type)?.delete(callback);
      super.removeEventListener(type, callback, options);
    }
    count(type) { return this.listeners.get(type)?.size ?? 0; }
  }
  const node = () => Object.assign(new Events(), {
    style: {}, dataset: {}, children: [],
    classList: { add() {}, remove() {}, toggle() {} },
    setAttribute(name, value) { this[name] = value; },
    append(child) { this.children.push(child); child.parentNode = this; },
    prepend(child) { this.children.unshift(child); child.parentNode = this; },
    remove() {
      if (this.parentNode) this.parentNode.children = this.parentNode.children.filter((child) => child !== this);
      this.parentNode = null;
    },
  });
  const app = Object.assign(node(), { innerHTML: '' });
  const hero = node();
  const header = { getBoundingClientRect: () => ({ height: 82 }) };
  const media = Object.assign(new Events(), { matches: reducedMotion });
  const frames = new Map();
  let nextFrame = 0;
  let now = 0;
  const window = Object.assign(new Events(), {
    innerWidth: 1280, innerHeight: 800, devicePixelRatio: 1, scrollY: 0,
    localStorage: { getItem: () => null },
    matchMedia: (query) => query.includes('reduced-motion') ? media : Object.assign(new Events(), { matches: false }),
    requestAnimationFrame(callback) { frames.set(++nextFrame, callback); return nextFrame; },
    cancelAnimationFrame: (id) => frames.delete(id),
    scrollTo: ({ top }) => { window.scrollY = top; },
  });
  const images = [];
  const document = Object.assign(new Events(), {
    hidden,
    documentElement: Object.assign(node(), { scrollHeight: 12000 }),
    body: node(),
    head: Object.assign(node(), { querySelector: () => null }),
    querySelector(selector) {
      if (selector === '#app') return app;
      if (selector === '.hero') return app.innerHTML.includes('class="hero"') ? hero : null;
      if (selector === '.site-header') return header;
      return null;
    },
    querySelectorAll: () => [],
    createElement(tag) {
      const element = node();
      if (tag === 'canvas') {
        element.getContext = () => ({
          createRadialGradient: () => ({ addColorStop() {} }),
          beginPath() {}, arc() {}, fill() {}, drawImage() {},
          getImageData: () => ({ data: new Uint8ClampedArray(1024 * 1024 * 4) }),
        });
      }
      if (tag === 'img') images.push(element);
      return element;
    },
    getElementById: () => null,
  });
  const resources = new Map();
  const tracked = (Base) => class extends Base {
    constructor(...args) {
      super(...args);
      resources.set(this, 0);
      this.addEventListener('dispose', () => resources.set(this, resources.get(this) + 1));
    }
  };
  const renderers = [];
  const denied = new Error('Error creating WebGL context.');
  let attempts = 0;
  const warnings = [];
  const capability = { available };
  const context = vm.createContext({
    ...site, ...locales,
    ...Object.fromEntries(iconNames.map((name) => [name, {}])),
    createIcons() {},
    THREE: {
      ...THREE,
      Clock: class {
        start() { this.last = now; this.running = true; }
        stop() { this.running = false; }
        getDelta() {
          if (!this.running) { this.start(); return 0; }
          const delta = (now - this.last) / 1000;
          this.last = now;
          return delta;
        }
      },
      BufferGeometry: tracked(THREE.BufferGeometry),
      PointsMaterial: tracked(THREE.PointsMaterial),
      CanvasTexture: tracked(THREE.CanvasTexture),
      WebGLRenderer: class {
        renders = [];
        disposals = 0;
        contextLosses = 0;
        constructor({ canvas }) {
          attempts++;
          if (!capability.available) throw denied;
          this.canvas = canvas;
          renderers.push(this);
        }
        setClearColor() {}
        setSize(width, height) {
          if (setupError) throw setupError;
          this.size = [width, height];
        }
        setPixelRatio(ratio) { this.pixelRatio = ratio; }
        render(scene, camera) {
          assert.equal(this.disposals, 0, 'a disposed renderer must never draw');
          this.renders.push({ scene, camera });
        }
        dispose() { this.disposals++; }
        forceContextLoss() { this.contextLosses++; }
      },
    },
    document, window, navigator: { languages: [] }, Event,
    Math: Object.assign(Object.create(Math), { random: () => 0.5 }),
    requestAnimationFrame: window.requestAnimationFrame,
    cancelAnimationFrame: window.cancelAnimationFrame,
    IntersectionObserver: class { observe() {} unobserve() {} disconnect() {} },
    getComputedStyle: () => ({ getPropertyValue: (name) => name === '--particle-color' ? '#fafafa' : '0.5' }),
    console: { error: (...args) => warnings.push(args), warn() {} },
  });
  vm.runInContext(pageSource, context);
  const dispose = () => vm.runInContext('introScene?.dispose()', context);
  t.after(dispose);
  return {
    app, document, window, media, renderers, resources, images, frames, warnings, capability,
    attempts: () => attempts,
    show(locale, preserveScroll = false) {
      return vm.runInContext(`showLocale(${JSON.stringify(locale)}, ${preserveScroll})`, context);
    },
    dispose,
    flushFrame() {
      now += 16;
      const pending = [...frames];
      frames.clear();
      for (const [, callback] of pending) callback(now);
    },
    setHidden(value) { document.hidden = value; document.dispatchEvent(new Event('visibilitychange')); },
    setReducedMotion(value) { media.matches = value; media.dispatchEvent(new Event('change')); },
  };
}

const heroCanvases = (page) => page.document.body.children.filter((node) => node.className === 'hero-canvas');
const liveResources = (page) => [...page.resources.values()].filter((disposals) => disposals === 0).length;
const assertStaticPage = (page, locale) => {
  assert.equal(page.document.documentElement.lang, locale);
  assert.equal(page.document.documentElement.dir, locales.localeDirection(locale));
  assert.equal(page.document.title, site.getSiteContent(locale).meta.documentTitle);
  assert.ok(page.app.innerHTML.includes(site.getSiteContent(locale).header.languageLabel));
  assert.ok(page.app.innerHTML.includes(`href="${site.latestRelease.dmg}" download`), 'the main download remains available');
};

test('unavailable WebGL preserves localized content and downloads without attaching a canvas', async (t) => {
  const page = createPage(t, { available: false });
  await assert.doesNotReject(page.show('ar'));
  assertStaticPage(page, 'ar');
  assert.equal(heroCanvases(page).length, 0);
  assert.equal(liveResources(page), 0);
  assert.equal(page.images.length, 0);
  assert.equal(page.frames.size, 0);
  assert.equal(page.document.count('visibilitychange'), 0);
  assert.equal(page.window.count('resize'), 1);
  assert.equal(page.media.count('change'), 1);
});

test('repeated denied language switches do not accumulate surfaces, listeners, or animation work', async (t) => {
  const page = createPage(t, { available: false });
  for (const locale of [...locales.siteLocales, ...locales.siteLocales].reverse()) {
    await page.show(locale);
    assertStaticPage(page, locale);
    assert.equal(heroCanvases(page).length, 0, locale);
    assert.equal(liveResources(page), 0, locale);
    assert.equal(page.frames.size, 0, locale);
    assert.equal(page.document.count('visibilitychange'), 0, locale);
    assert.equal(page.window.count('site-theme-change'), 0, locale);
  }
  assert.equal(page.attempts(), 34);
});

test('a later available context recovers one scene and its disposal releases every resource once', async (t) => {
  const page = createPage(t, { available: false, reducedMotion: false });
  await page.show('zh-Hans');
  await page.show('ar');
  page.capability.available = true;
  await page.show('en');
  page.flushFrame();
  assertStaticPage(page, 'en');
  assert.equal(page.renderers.length, 1);
  assert.equal(heroCanvases(page).length, 1);
  assert.equal(liveResources(page), 5);
  assert.equal(page.frames.size, 1);
  const renderer = page.renderers[0];
  assert.ok(renderer.renders.length > 0);
  assert.ok(renderer.renders.at(-1).scene.children.some((child) => child.isPoints));
  const image = page.images[0];
  image.onload();
  page.dispose();
  page.flushFrame();
  assert.equal(heroCanvases(page).length, 0);
  assert.equal(page.frames.size, 0);
  assert.equal(renderer.disposals, 1);
  assert.equal(renderer.contextLosses, 1);
  assert.equal(renderer.renders.at(-1).scene.children.length, 0);
  assert.equal(image.onload, null);
  assert.equal(image.onerror, null);
  assert.ok([...page.resources.values()].every((count) => count === 1));
  assert.equal(page.document.count('visibilitychange'), 0);
  assert.equal(page.window.count('resize'), 1);
  assert.equal(page.window.count('site-theme-change'), 0);
  assert.equal(page.media.count('change'), 1);
});

test('denial after an active locale removes the old scene and permits a fresh recovery', async (t) => {
  const page = createPage(t);
  await page.show('en');
  const first = page.renderers[0];
  page.capability.available = false;
  await page.show('ar');
  assertStaticPage(page, 'ar');
  assert.equal(first.disposals, 1);
  assert.equal(heroCanvases(page).length, 0);
  assert.equal(liveResources(page), 0);
  page.capability.available = true;
  await page.show('zh-Hans');
  assert.equal(page.renderers.length, 2);
  assert.equal(heroCanvases(page).length, 1);
  assert.equal(liveResources(page), 5);
  assert.equal(page.document.count('visibilitychange'), 1);
  assert.equal(page.media.count('change'), 2);
});

test('errors after successful context creation remain observable instead of being treated as unavailability', async (t) => {
  const setupError = new Error('renderer size setup failed');
  const page = createPage(t, { setupError });
  await assert.rejects(page.show('en'), (error) => error === setupError);
  assert.equal(page.warnings.length, 0);
  assert.equal(page.renderers.length, 1);
});

test('normal scenes keep a single animation task across hidden and reduced-motion transitions', async (t) => {
  const page = createPage(t, { reducedMotion: false });
  await page.show('en');
  page.flushFrame();
  assert.equal(page.frames.size, 1);
  const renderer = page.renderers[0];
  page.setHidden(true);
  const hiddenRenders = renderer.renders.length;
  page.setHidden(true);
  page.setReducedMotion(true);
  page.window.dispatchEvent(new Event('site-theme-change'));
  page.window.innerWidth = 640;
  page.window.dispatchEvent(new Event('resize'));
  page.images[0].onload();
  page.flushFrame();
  assert.equal(renderer.renders.length, hiddenRenders);
  assert.equal(page.frames.size, 0);
  assert.deepEqual(renderer.size, [640, 800]);
  page.setHidden(false);
  assert.equal(renderer.renders.length, hiddenRenders + 1);
  assert.equal(page.frames.size, 0);
  page.setReducedMotion(false);
  page.flushFrame();
  assert.equal(page.frames.size, 1);
  assert.equal(liveResources(page), 5);
});

test('seeded capability failures and browser event churn keep scene resources and tasks bounded', async (t) => {
  const page = createPage(t, { reducedMotion: false });
  let seed = 0x1a1c9211;
  const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; };
  for (let step = 0; step < 256; step++) {
    page.capability.available = random() % 4 !== 0;
    page.setHidden(random() % 3 === 0);
    page.setReducedMotion(random() % 3 === 0);
    const locale = locales.siteLocales[random() % locales.siteLocales.length];
    await page.show(locale, true);
    page.window.innerWidth = 320 + random() % 1600;
    page.window.dispatchEvent(new Event('resize'));
    page.window.dispatchEvent(new Event('site-theme-change'));
    page.flushFrame();
    const active = page.capability.available ? 1 : 0;
    const label = `seed 0x1a1c9211, step ${step}`;
    assertStaticPage(page, locale);
    assert.equal(heroCanvases(page).length, active, label);
    assert.equal(liveResources(page), active * 5, label);
    assert.equal(page.renderers.filter((renderer) => renderer.disposals === 0).length, active, label);
    assert.equal(page.window.count('resize'), 1 + active, label);
    assert.equal(page.document.count('visibilitychange'), active, label);
    assert.equal(page.media.count('change'), 1 + active, label);
    assert.equal(page.frames.size, active && !page.document.hidden && !page.media.matches ? 1 : 0, label);
    assert.ok([...page.resources.values()].every((count) => count <= 1), label);
  }
});
