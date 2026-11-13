import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import {parseFragment} from 'parse5';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';
import {SCENES, TOTAL_FRAMES, CROSSFADE} from '../src/timeline.ts';

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
const text = (node) => node?.nodeName === '#text' ? node.value : (node?.childNodes ?? []).map(text).join('');
const style = (node) => Object.fromEntries((attr(node, 'style') ?? '').split(';').filter(Boolean).map((item) => {const split = item.indexOf(':'); return [item.slice(0, split), item.slice(split + 1)];}));
const lid = load('src/modules/tour/LidCloseDesktopPreview.tsx');
const settings = load('src/scenes/SceneSettings.tsx');
const outro = load('src/scenes/Scene5Outro.tsx');
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

test('the same Zshell desktop folds once, holds, opens once and stays restored', () => {
  const timing = lid.exports.LID_PREVIEW_TIMING;
  const render = (frame) => lid.render(lid.exports.LidCloseDesktopPreview, {frame});
  const desktopText = text(find(render(timing.start), 'data-zshell-desktop'));
  assert.ok(timing.closed - timing.start >= 30);
  assert.ok(timing.opening - timing.closed >= 8);
  assert.ok(timing.restored - timing.opening >= 30);
  let previous = lid.exports.lidPreviewAt(timing.start).angle;
  for (let frame = timing.start; frame <= 209; frame++) {
    const state = lid.exports.lidPreviewAt(frame);
    const tree = render(frame);
    const sheet = find(tree, 'data-lid-depth-sheet');
    assert.equal(style(sheet).width, '1280px');
    assert.equal(style(sheet).height, '720px');
    assert.equal(text(find(sheet, 'data-zshell-desktop')), desktopText, `The desktop changes at ${frame}`);
    assert.equal(all(tree).filter((node) => attr(node, 'data-zshell-desktop') !== undefined).length, 1);
    assert.equal(find(tree, 'data-recommended-section'), undefined, 'Settings must not reappear behind the fold');
    assert.equal(find(tree, 'data-lid-preview-action'), undefined);
    assert.doesNotMatch(text(tree), /Settings → Features|Preview animation|Preview ended/);
    assert.equal(all(tree).filter((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26').length, 0);
    assert.ok(state.angle >= 50 && state.angle <= 125, `The lid reaches an extreme angle at ${frame}`);
    const topLeft = project(state.matrix, 0, 0);
    const topRight = project(state.matrix, 1280, 0);
    assert.ok(topLeft.y >= -0.000001 && topLeft.y < 720, `The far edge leaves the frame at ${frame}`);
    near(topLeft.x + topRight.x, 1280);
    if (frame <= timing.closed) assert.ok(state.angle <= previous);
    else if (frame < timing.opening) near(state.angle, previous);
    else assert.ok(state.angle >= previous);
    previous = state.angle;
  }
  near(lid.exports.lidPreviewAt(timing.start - 0.01).angle, 125);
  near(lid.exports.lidPreviewAt(timing.closed).angle, 55);
  near(lid.exports.lidPreviewAt(timing.opening - 0.01).angle, 55);
  near(lid.exports.lidPreviewAt(timing.restored).angle, 125);
  assert.equal(lid.exports.lidPreviewAt(timing.restored - 0.01).restored, false);
  assert.equal(lid.exports.lidPreviewAt(timing.restored).restored, true);
  assert.deepEqual(lid.exports.lidPreviewAt(209), lid.exports.lidPreviewAt(1000));
  const linearQuarter = 125 - 70 / 4;
  assert.ok(Math.abs(lid.exports.lidPreviewAt(timing.start + 8).angle - linearQuarter) > 1, 'Closing uses eased motion instead of constant velocity');
  assert.ok(Math.abs(lid.exports.lidPreviewAt(timing.opening + 8).angle - (55 + 70 / 4)) > 1, 'Opening uses eased motion instead of constant velocity');
});

test('the actual ending keeps the opened desktop until a single static brand card', () => {
  assert.equal(TOTAL_FRAMES, 9600);
  assert.equal(SCENES.settings.duration, 1140);
  assert.equal(SCENES.outro.duration, 160);
  assert.equal(SCENES.outro.from, SCENES.settings.from + SCENES.settings.duration);
  const duration = SCENES.settings.duration + CROSSFADE;
  let opened = 0;
  let restored = 0;
  let desktopText;
  for (let frame = 0; frame < duration; frame++) {
    const state = settings.exports.settingsTourAt(frame, duration);
    if (state.step.id !== 'recommended' || state.frame < 34) continue;
    const tree = settings.render(settings.exports.SceneSettings, {duration}, frame);
    const desktop = find(tree, 'data-zshell-desktop');
    assert.ok(desktop, `The Zshell desktop disappears at ${frame}`);
    desktopText ??= text(desktop);
    assert.equal(text(desktop), desktopText);
    assert.equal(find(tree, 'data-recommended-section'), undefined, `Settings reappears after opening Zshell at ${frame}`);
    assert.equal(all(tree).filter((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26').length, 0);
    assert.doesNotMatch(text(tree), /Paper Lanterns|Preview animation|Preview ended/);
    if (state.frame < lid.exports.LID_PREVIEW_TIMING.start) opened++;
    else {
      assert.ok(find(tree, 'data-lid-depth-sheet'), 'The desktop fold must take over without another Settings step');
      const lidState = lid.exports.lidPreviewAt(state.frame);
      if (state.frame >= lid.exports.LID_PREVIEW_TIMING.opening && lidState.angle >= 90) restored++;
    }
  }
  assert.ok(opened >= 72, `The opened Zshell window lasts only ${opened} frames`);
  assert.ok(restored >= 42, `The unchanged reopened desktop lasts only ${restored} frames`);
  const endingDuration = SCENES.outro.duration + CROSSFADE;
  const brandText = text(find(outro.render(outro.exports.Scene5Outro, {duration: endingDuration}, 26), 'data-outro-brand'));
  let readable = 0;
  for (let frame = 0; frame < endingDuration; frame++) {
    const tree = outro.render(outro.exports.Scene5Outro, {duration: endingDuration}, frame);
    const card = find(tree, 'data-outro');
    const brand = find(tree, 'data-outro-brand');
    const command = find(tree, 'data-outro-install-command');
    assert.equal(style(card).background, '#000');
    assert.equal(text(brand), brandText);
    assert.equal(text(command), '➜ ~ brew install --cask wzz6423/tap/zisla');
    assert.ok(find(tree, 'data-outro-repository'));
    assert.match(text(find(tree, 'data-outro-music-credit')), /Funkorama.*Kevin MacLeod.*CC BY 4.0/);
    assert.equal(find(tree, 'data-zshell-desktop'), undefined);
    assert.equal(all(tree).filter((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26').length, 0);
    assert.doesNotMatch(text(tree), /Paper Lanterns|Installing Cask|successfully installed|Preview ended/);
    if (Number(style(brand).opacity) === 1 && Number(style(command.parentNode).opacity) === 1 && frame < endingDuration - 30) readable++;
    if (frame >= endingDuration - 7) {
      const blackout = all(tree).find((node) => attr(node, 'class')?.includes('pointer-events-none absolute inset-0 bg-black'));
      near(Number(style(blackout).opacity), 1);
    }
  }
  assert.ok(readable >= 90, `The complete brand card is readable for only ${readable} frames`);
});

test('actual film lock-screen playback stops advancing after Pause under duration scaling', () => {
  const frames = [];
  for (let frame = 0; frame < 1156; frame++) {
    const state = settings.exports.settingsTourAt(frame, 1156);
    if (state.step.id !== 'lockScreen' || state.frame < 38) continue;
    const tree = settings.render(settings.exports.SceneSettings, {duration: 1156, globalFrom: SCENES.settings.from - CROSSFADE}, frame);
    frames.push(Number(attr(find(tree, 'data-lock-playback-progress'), 'data-elapsed')));
  }
  assert.ok(frames.length >= 42);
  assert.equal(new Set(frames).size, 1, 'Paused playback still moves because scene time and module time differ');
});

test('isolated ending ablations expose broken hinge, clipping, fast opening, Settings flashes and moving CTA', () => {
  const replace = (before, after) => (source) => {assert.ok(source.includes(before), `Ablation target missing: ${before}`); return source.replace(before, after);};
  const cases = [
    ['bottom hinge', 'src/modules/tour/LidCloseDesktopPreview.tsx', '1 - top / (height * scale)', '1 - top / (height * scale) - projection', (ui) => near(project(ui.exports.lidDepthAt(55).matrix, 0, 720).y, 720)],
    ['extreme angle', 'src/modules/tour/LidCloseDesktopPreview.tsx', '[125, 55]', '[125, 21]', (ui) => assert.ok(project(ui.exports.lidPreviewAt(139).matrix, 0, 0).y >= 0)],
    ['fast opening', 'src/modules/tour/LidCloseDesktopPreview.tsx', 'restored: 182', 'restored: 162', (ui) => assert.ok(ui.exports.LID_PREVIEW_TIMING.restored - ui.exports.LID_PREVIEW_TIMING.opening >= 30)],
    ['captured desktop', 'src/modules/tour/LidCloseDesktopPreview.tsx', '(ZshellTourDesktop, {})', '(ZshellTourDesktop, {}) && null', (ui) => assert.ok(find(ui.render(ui.exports.LidCloseDesktopPreview, {frame: 140}), 'data-zshell-desktop'))],
    ['Settings flash', 'src/modules/tour/LidCloseDesktopPreview.tsx', '"data-feature": "lidClose"', '"data-feature": "lidClose", "data-recommended-section": "features"', (ui) => assert.equal(find(ui.render(ui.exports.LidCloseDesktopPreview, {frame: 140}), 'data-recommended-section'), undefined)],
    ['early fold', 'src/scenes/SceneSettings.tsx', 'state.frame < LID_PREVIEW_TIMING.start', 'state.frame < 78', (ui) => assert.equal(find(ui.render(ui.exports.SceneSettings, {duration: 1140}, 1030), 'data-lid-depth-sheet'), undefined)],
    ['incomplete CTA', 'src/scenes/Scene5Outro.tsx', 'children: copy.outro', 'children: copy.outro.slice(0, frame)', (ui) => assert.equal(text(find(ui.render(ui.exports.Scene5Outro, {duration: 176}, 10), 'data-outro-install-command')), '➜ ~ brew install --cask wzz6423/tap/zisla')],
    ['final black hold', 'src/scenes/Scene5Outro.tsx', 'duration - 7', 'duration - 1', (ui) => {const tree = ui.render(ui.exports.Scene5Outro, {duration: 176}, 170); const blackout = all(tree).find((node) => attr(node, 'class')?.includes('pointer-events-none absolute inset-0 bg-black')); near(Number(style(blackout).opacity), 1);}],
  ];
  for (const [name, entry, before, after, verify] of cases) {
    const original = load(entry);
    verify(original);
    const mutated = load(entry, replace(before, after));
    assert.throws(() => verify(mutated), undefined, `Removing ${name} did not break the visible contract`);
  }
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
