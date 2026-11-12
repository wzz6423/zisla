import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));

const load = (entryPoint) => {
  const clock = {frame: 0};
  const bundle = buildSync({absWorkingDir: root, entryPoints: [entryPoint], bundle: true, packages: 'external', platform: 'node', format: 'cjs', jsx: 'automatic', write: false, loader: {'.svg': 'dataurl', '.png': 'dataurl'}});
  const module = {exports: {}};
  const isolatedRequire = (name) => name === 'remotion' ? {
    ...Remotion,
    useCurrentFrame: () => clock.frame,
    useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 1200}),
    Img: (props) => React.createElement('img', props),
  } : require(name);
  new Function('require', 'module', 'exports', bundle.outputFiles[0].text)(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props, frame) => {
    clock.frame = frame;
    return renderToStaticMarkup(React.createElement(Component, props));
  }};
};

const stateModule = load('src/scenes/layoutsState.ts').exports;
const {layoutStateAt, placementFrame, placementNearest, CUSTOM_PLACEMENTS, LAYOUT_ACTIONS, LAYOUTS_DURATION, layoutPets, petMotionAt} = stateModule;

test('a chosen style changes the visible notch into a camera pill', () => {
  const before = layoutStateAt(LAYOUT_ACTIONS.pill - 1);
  const after = layoutStateAt(LAYOUT_ACTIONS.pill + 18);
  assert.equal(before.style, 'notch');
  assert.equal(before.rect.height, 36);
  assert.equal(after.style, 'pill');
  assert.equal(after.placement.mode, 'camera');
  assert.equal(after.rect.x + after.rect.width / 2, 640);
  assert.equal(after.rect.height, 32);
  assert.notDeepEqual(before.rect, after.rect);
  const ui = load('src/scenes/SceneLayouts.tsx');
  assert.match(ui.render(ui.exports.SceneLayouts, {}, 80), /data-layout-style="notch"/);
  const camera = ui.render(ui.exports.SceneLayouts, {}, 170);
  assert.match(camera, /Dynamic Island mode · Camera position/);
  assert.match(camera, /data-feature="island.camera"/);
});

test('dragging reaches all four edges, rotates the layout and keeps confirmed positions', () => {
  const ui = load('src/scenes/SceneLayouts.tsx');
  const expectedFrames = [[264, 56, 240, 32], [712, 672, 240, 32], [24, 254.4, 32, 240], [1192, 240, 32, 240]];
  for (const [index, step] of CUSTOM_PLACEMENTS.entries()) {
    const drag = layoutStateAt(step.at + 8);
    const confirmed = layoutStateAt(step.at + 38);
    const later = layoutStateAt(step.at + 65);
    assert.equal(drag.dragging, true);
    assert.equal(drag.pressed, true);
    assert.equal(confirmed.editing, false);
    assert.equal(confirmed.placement.mode, 'custom');
    assert.equal(confirmed.placement.edge, step.placement.edge);
    for (const [field, expected] of Object.entries({x: expectedFrames[index][0], y: expectedFrames[index][1], width: expectedFrames[index][2], height: expectedFrames[index][3]})) {
      assert.ok(Math.abs(confirmed.rect[field] - expected) < 1e-9, `Wrong ${field} on ${step.placement.edge} edge`);
    }
    assert.deepEqual(later.rect, confirmed.rect, 'Confirmed placement must remain in position');
    const vertical = step.placement.edge === 'left' || step.placement.edge === 'right';
    assert.equal(confirmed.rect.height > confirmed.rect.width, vertical);
    const html = ui.render(ui.exports.SceneLayouts, {}, step.at + 38);
    assert.match(html, new RegExp(`data-feature="island.custom.${step.placement.edge}"`));
    assert.doesNotMatch(html, /Press Return to finish/);
  }
  for (let frame = LAYOUT_ACTIONS.chooseCustom; frame < LAYOUT_ACTIONS.camera; frame += 3) {
    const {rect} = layoutStateAt(frame);
    assert.ok(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= 1280 && rect.y + rect.height <= 720, `Pill leaves the screen at frame ${frame}`);
  }
});

test('custom offsets retain bottom-up vertical positions and cap the inward distance', () => {
  const low = placementFrame({mode: 'custom', edge: 'left', offset: 0.2, inwardDistance: 24});
  const high = placementFrame({mode: 'custom', edge: 'left', offset: 0.8, inwardDistance: 24});
  assert.ok(high.y < low.y);
  assert.equal(low.x, 24);
  const inset = placementFrame({mode: 'custom', edge: 'right', offset: 0.5, inwardDistance: 1000});
  assert.equal(1280 - inset.x - inset.width, 96);
  const boundary = placementFrame({mode: 'custom', edge: 'top', offset: -1, inwardDistance: 0});
  assert.equal(boundary.x, 8);
  assert.equal(boundary.y, 8);
  assert.equal(placementNearest(64, 64, 'left').edge, 'left');
  assert.equal(placementNearest(64, 64, 'top').edge, 'top');
});

test('the cursor reaches selected options and the displayed confirmation and import buttons', () => {
  for (const [at, expectedX, expectedY] of [[LAYOUT_ACTIONS.pill, 777, 400], [LAYOUT_ACTIONS.chooseCustom, 777, 439], [LAYOUT_ACTIONS.camera, 777, 405], [LAYOUT_ACTIONS.chick, 777, 400], [LAYOUT_ACTIONS.petRight, 777, 482], [LAYOUT_ACTIONS.chooseFile, 777, 363], [LAYOUT_ACTIONS.importSheet, 780, 432], [LAYOUT_ACTIONS.name, 565, 419], [LAYOUT_ACTIONS.import, 772, 514]]) {
    const state = layoutStateAt(at);
    assert.ok(Math.abs(state.cursor.x - expectedX) < 1 && Math.abs(state.cursor.y - expectedY) < 1, `Cursor misses the selected control at frame ${at}`);
    assert.equal(state.pressed, true);
  }
  for (const step of CUSTOM_PLACEMENTS) {
    const confirmation = layoutStateAt(step.at + 31);
    assert.ok(confirmation.cursor.x >= 648 && confirmation.cursor.x <= 720);
    assert.ok(confirmation.cursor.y >= 438 && confirmation.cursor.y <= 470);
    assert.equal(confirmation.pressed, true);
  }
});

test('pet selection and side change alter the companion, and import applies the chosen name', () => {
  const ui = load('src/scenes/SceneLayouts.tsx');
  const left = ui.render(ui.exports.SceneLayouts, {}, 842);
  assert.match(left, /data-pet-id="bear"/);
  assert.match(left, /data-pet-side="left"/);
  const leftX = Number(left.match(/data-feature="pet.left"[^>]*style="left:([^p]+)px/)?.[1]);
  assert.ok(leftX < 520, 'The left pet must be drawn before the camera pill');
  const right = ui.render(ui.exports.SceneLayouts, {}, 971);
  assert.match(right, /data-pet-id="chick"/);
  assert.match(right, /data-pet-side="right"/);
  const rightX = Number(right.match(/data-feature="pet.right"[^>]*style="left:([^p]+)px/)?.[1]);
  assert.equal(rightX, 764, 'The right pet must be drawn after the camera pill');
  assert.match(ui.render(ui.exports.SceneLayouts, {}, 1010), /Pocket Chick.png/);
  const named = ui.render(ui.exports.SceneLayouts, {}, LAYOUT_ACTIONS.import - 1);
  assert.match(named, /Pixel Chick/);
  assert.doesNotMatch(named, /Pixel Chick \(Imported\)/);
  assert.match(ui.render(ui.exports.SceneLayouts, {}, LAYOUT_ACTIONS.import + 4), /Importing…/);
  const imported = ui.render(ui.exports.SceneLayouts, {}, LAYOUT_ACTIONS.imported + 18);
  assert.match(imported, /Pixel Chick \(Imported\)/);
  assert.doesNotMatch(imported, /Pocket Chick.png/);
  assert.match(imported, /data-pet-side="right"/);
});

test('pets use the exact bundled CC0 images and the native single-frame animation period', () => {
  for (const [id, pet] of Object.entries(layoutPets)) {
    const manifest = JSON.parse(readFileSync(new URL(`../../mac/Resources/Pets/${id}/pet.json`, import.meta.url), 'utf8'));
    const png = readFileSync(new URL(`../../mac/Resources/Pets/${id}/${manifest.spritePath}`, import.meta.url));
    assert.equal(manifest.frames ?? 1, 1);
    assert.equal(pet.width, png.readUInt32BE(16));
    assert.equal(pet.height, png.readUInt32BE(20));
    assert.equal(pet.src, `data:image/png;base64,${png.toString('base64')}`);
    assert.match(manifest.description, /CC0/);
  }
  const first = petMotionAt(0, 60);
  const next = petMotionAt(42, 60);
  const cycle = petMotionAt(84, 60);
  assert.ok(Math.abs(first.scale - cycle.scale) < 1e-9);
  assert.notDeepEqual(first, next);
  const ui = load('src/scenes/SceneLayouts.tsx');
  const initialImage = ui.render(ui.exports.LayoutPet, {pet: layoutPets.bear, frame: 0, fps: 60, size: 56});
  const movedImage = ui.render(ui.exports.LayoutPet, {pet: layoutPets.bear, frame: 42, fps: 60, size: 56});
  assert.notEqual(initialImage, movedImage, 'The pet image must use the frame-driven animation');
  assert.match(initialImage, /data-pet-frame="0"/);
  for (let frame = 0; frame <= 1200; frame += 3) {
    const motion = petMotionAt(frame, 60);
    assert.ok(motion.scale >= 0.97 && motion.scale <= 1.03);
    assert.ok(Math.abs(motion.lift) <= 0.04);
  }
});

test('duration scaling preserves the ending and the confirmed import during crossfade lead', () => {
  const normal = layoutStateAt(600);
  const longer = layoutStateAt(608, 1216);
  assert.deepEqual(normal, longer);
  const last = layoutStateAt(1215, 1216);
  assert.equal(last.importStage, 'imported');
  assert.equal(last.petSide, 'right');
  assert.equal(last.style, 'pill');
  assert.equal(last.placement.mode, 'camera');
  assert.ok(last.local < LAYOUTS_DURATION);
  const ui = load('src/scenes/SceneLayouts.tsx');
  const html = ui.render(ui.exports.SceneLayouts, {duration: 1216}, 1215);
  assert.match(html, /Pixel Chick \(Imported\)/);
  assert.match(html, /data-feature="island.camera"/);
});
