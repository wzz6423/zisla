import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import {parseFragment} from 'parse5';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';
import {SCENES, TOTAL_FRAMES} from '../src/timeline.ts';

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));
const load = (entryPoint, mutate = (source) => source) => {
  const clock = {frame: 0};
  const bundle = buildSync({absWorkingDir: root, entryPoints: [entryPoint], bundle: true, packages: 'external', platform: 'node', format: 'cjs', jsx: 'automatic', write: false, loader: {'.svg': 'dataurl', '.png': 'dataurl'}});
  const module = {exports: {}};
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: TOTAL_FRAMES}), Img: (props) => React.createElement('img', props)} : require(name);
  new Function('require', 'module', 'exports', mutate(bundle.outputFiles[0].text))(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props, frame = 0) => {clock.frame = frame; return parseFragment(renderToStaticMarkup(React.createElement(Component, props)));}};
};
const all = (node) => [node, ...(node.childNodes ?? []).flatMap(all)];
const attr = (node, name) => node.attrs?.find((entry) => entry.name === name)?.value;
const find = (node, name) => all(node).find((entry) => attr(entry, name) !== undefined);
const text = (node) => node.nodeName === '#text' ? node.value : (node.childNodes ?? []).map(text).join('');
const style = (node) => Object.fromEntries((attr(node, 'style') ?? '').split(';').filter(Boolean).map((item) => {const split = item.indexOf(':'); return [item.slice(0, split), item.slice(split + 1)];}));
const lid = load('src/modules/tour/LidCloseDesktopPreview.tsx');
const settings = load('src/scenes/SceneSettings.tsx');
const project = (matrix, x, y) => {
  const m = matrix.slice('matrix3d('.length, -1).split(',').map(Number);
  const w = m[3] * x + m[7] * y + m[15];
  return {x: (m[0] * x + m[4] * y + m[12]) / w, y: (m[1] * x + m[5] * y + m[13]) / w};
};
const near = (value, expected) => assert.ok(Math.abs(value - expected) < 0.000001, `${value} does not match ${expected}`);

test('the full-screen fold fixes both bottom corners and projects the far edge symmetrically', () => {
  for (const angle of [125, 95, 90, 75, 55, 35, 21]) {
    const depth = lid.exports.lidDepthAt(angle);
    const topLeft = project(depth.matrix, 0, 0);
    const topRight = project(depth.matrix, 1280, 0);
    const bottomLeft = project(depth.matrix, 0, 720);
    const bottomRight = project(depth.matrix, 1280, 720);
    near(bottomLeft.x, 0); near(bottomLeft.y, 720);
    near(bottomRight.x, 1280); near(bottomRight.y, 720);
    near(topLeft.x + topRight.x, 1280);
    near(topLeft.y, topRight.y);
    near(topLeft.x, depth.inset); near(topLeft.y, depth.top);
    if (angle >= 90) {near(topLeft.x, 0); near(topLeft.y, 0); near(topRight.x, 1280);}
    else assert.ok(topLeft.x > 0 && topLeft.y < 720);
  }
});

test('one click shows the whole Zshell desktop, folds once, opens once and fades over ten frames', () => {
  const timing = lid.exports.LID_PREVIEW_TIMING;
  const render = (frame) => lid.render(lid.exports.LidCloseDesktopPreview, {frame});
  const before = render(timing.click);
  assert.ok(find(before, 'data-lid-preview-action'));
  assert.equal(find(before, 'data-lid-fullscreen-overlay'), undefined);
  for (let frame = timing.click; frame < timing.start; frame++) {
    const pointer = all(render(frame)).find((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26');
    assert.ok(pointer && style(pointer).transform === 'scale(0.9)', `Preview click lost its pointer at ${frame}`);
    assert.ok(find(render(frame), 'data-lid-preview-action'));
  }
  const folded = render(122);
  const sheet = find(folded, 'data-lid-depth-sheet');
  assert.equal(style(sheet).width, '1280px');
  assert.equal(style(sheet).height, '720px');
  assert.ok(find(sheet, 'data-zshell-desktop'));
  assert.equal(find(sheet, 'data-recommended-section'), undefined, 'The capture excludes the zisla Settings window');
  assert.ok(text(sheet).includes('Zshell') && text(sheet).includes('launch-project'));
  assert.ok(find(folded, 'data-lid-preview-action'), 'Settings stays behind the captured desktop so dismissal can fade back into it');
  let previous = lid.exports.lidPreviewAt(timing.start).angle;
  for (let frame = timing.start + 1; frame <= timing.closed; frame++) {const angle = lid.exports.lidPreviewAt(frame).angle; assert.ok(angle <= previous); previous = angle;}
  for (let frame = timing.opening; frame <= timing.release; frame++) {const angle = lid.exports.lidPreviewAt(frame).angle; assert.ok(angle >= previous); previous = angle;}
  assert.equal(timing.restored - timing.release, 10);
  near(lid.exports.lidPreviewAt(timing.release).opacity, 1);
  near(lid.exports.lidPreviewAt(timing.restored - 5).opacity, 0.5);
  assert.equal(find(render(timing.restored), 'data-lid-depth-sheet'), undefined);
  assert.ok(text(render(209)).includes('Preview ended · Desktop restored'));
});

test('Settings and the outro share the same 160-second budget and retain the completed preview', () => {
  assert.equal(TOTAL_FRAMES, 9600);
  assert.equal(SCENES.settings.duration, 1140);
  assert.equal(SCENES.outro.duration, 240);
  assert.equal(SCENES.outro.from, SCENES.settings.from + SCENES.settings.duration);
  let restored = 0;
  for (let frame = 0; frame < 1156; frame++) {
    const state = settings.exports.settingsTourAt(frame, 1156);
    if (state.step.id === 'recommended' && lid.exports.lidPreviewAt(state.frame).restored) restored++;
  }
  assert.ok(restored >= 42, `The restored desktop lasts only ${restored} frames`);
  const final = settings.render(settings.exports.SceneSettings, {duration: 1156}, 1155);
  assert.ok(text(final).includes('Preview ended · Desktop restored'));
});

test('actual film lock-screen playback stops advancing after Pause under duration scaling', () => {
  const frames = [];
  for (let frame = 0; frame < 1156; frame++) {
    const state = settings.exports.settingsTourAt(frame, 1156);
    if (state.step.id !== 'lockScreen' || state.frame < 38) continue;
    const tree = settings.render(settings.exports.SceneSettings, {duration: 1156, globalFrom: 8204}, frame);
    frames.push(Number(attr(find(tree, 'data-lock-playback-progress'), 'data-elapsed')));
  }
  assert.ok(frames.length >= 42);
  assert.equal(new Set(frames).size, 1, 'Paused playback still moves because scene time and module time differ');
});

test('removing the hinge projection or captured desktop breaks the visible fold contract', () => {
  const replace = (before, after) => (source) => {assert.ok(source.includes(before)); return source.replace(before, after);};
  const brokenHinge = load('src/modules/tour/LidCloseDesktopPreview.tsx', replace('1 - top / (height * scale)', '1 - top / (height * scale) - projection'));
  const bottom = project(brokenHinge.exports.lidDepthAt(35).matrix, 0, 720);
  assert.notEqual(Math.round(bottom.y), 720);
  const missingSheet = load('src/modules/tour/LidCloseDesktopPreview.tsx', replace('"data-lid-depth-sheet"', '"data-removed-sheet"'));
  assert.equal(find(missingSheet.render(missingSheet.exports.LidCloseDesktopPreview, {frame: 122}), 'data-lid-depth-sheet'), undefined);
  const earlyRestore = load('src/modules/tour/LidCloseDesktopPreview.tsx', replace('restored: 166', 'restored: 160'));
  assert.equal(find(earlyRestore.render(earlyRestore.exports.LidCloseDesktopPreview, {frame: 162}), 'data-lid-fullscreen-overlay'), undefined);
});

test('crossfades keep only the outgoing scene cursor until the incoming scene is fully visible', () => {
  const film = load('src/LaunchFilm.tsx');
  const visible = (tree) => all(tree).filter((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26' && Number(style(node).opacity ?? 1) > 0);
  for (let index = 1; index < film.exports.ENTRIES.length; index++) {
    const incoming = film.exports.ENTRIES[index];
    const outgoing = film.exports.ENTRIES[index - 1];
    for (let frame = 0; frame < 16; frame++) {
      const previous = film.render(film.exports.SceneLayer, {entry: outgoing, lead: outgoing.from === 0 ? 0 : 16, music: 'funk'}, outgoing.duration + (outgoing.from === 0 ? 0 : 16) - 16 + frame);
      const current = film.render(film.exports.SceneLayer, {entry: incoming, lead: 16, music: 'funk'}, frame);
      assert.ok(visible(previous).length + visible(current).length <= 1, `${incoming.id} crossfade frame ${frame} has two cursors`);
      assert.equal(visible(current).length, 0, `${incoming.id} exposes its pointer through the outgoing scene`);
    }
  }
  const withoutOwnership = load('src/LaunchFilm.tsx', (source) => {const result = source.replace('frame < lead ? 0 : 1', '1'); assert.notEqual(result, source); return result;});
  const entry = withoutOwnership.exports.ENTRIES.find((item) => item.id === 'aiCenter');
  assert.equal(visible(withoutOwnership.render(withoutOwnership.exports.SceneLayer, {entry, lead: 16, music: 'funk'}, 8)).length, 1);
});
