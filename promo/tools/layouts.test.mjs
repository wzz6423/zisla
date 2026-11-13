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
    useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 1020}),
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
  assert.equal(before.rect.height, 34);
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

test('one continuous preview reaches all four edges and commits only the final position', () => {
  const ui = load('src/scenes/SceneLayouts.tsx');
  const expectedFrames = [[372, 56, 24, 24], [820, 680, 24, 24], [24, 362.4, 24, 24], [1200, 348, 24, 24]];
  for (const [index, step] of CUSTOM_PLACEMENTS.entries()) {
    const drag = layoutStateAt(step.at + 8);
    const preview = layoutStateAt(step.at + 46);
    assert.equal(drag.dragging, true);
    assert.equal(drag.pressed, true);
    assert.equal(preview.editing, true);
    assert.equal(preview.committedPlacement.mode, 'camera', 'Dragging must not commit before Done');
    assert.equal(preview.placement.mode, 'custom');
    assert.equal(preview.placement.edge, step.placement.edge);
    for (const [field, expected] of Object.entries({x: expectedFrames[index][0], y: expectedFrames[index][1], width: expectedFrames[index][2], height: expectedFrames[index][3]})) {
      assert.ok(Math.abs(preview.rect[field] - expected) < 1e-9, `Wrong ${field} on ${step.placement.edge} preview`);
    }
    const html = ui.render(ui.exports.SceneLayouts, {}, step.at + 46);
    assert.match(html, new RegExp(`data-feature="island.custom.${step.placement.edge}"`));
    assert.match(html, /data-placement-stage="preview"/);
    assert.match(html, /Press Return to finish/);
  }
  for (let frame = LAYOUT_ACTIONS.chooseCustom; frame < LAYOUT_ACTIONS.confirmed; frame += 3) {
    const {rect} = layoutStateAt(frame);
    assert.ok(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= 1280 && rect.y + rect.height <= 720, `Pill leaves the screen at frame ${frame}`);
  }
  const confirmed = layoutStateAt(LAYOUT_ACTIONS.confirmed);
  assert.equal(confirmed.editing, false);
  assert.equal(confirmed.placement.edge, 'right');
  assert.deepEqual(confirmed.rect, {x: 1192, y: 326, width: 32, height: 68});
  assert.deepEqual(layoutStateAt(LAYOUTS_DURATION - 1).rect, confirmed.rect);
  const html = ui.render(ui.exports.SceneLayouts, {}, LAYOUT_ACTIONS.confirmed + 12);
  assert.match(html, /data-feature="island.custom.confirmed"/);
  assert.match(html, /data-active-tasks="3"/);
  assert.doesNotMatch(html, /Press Return to finish|>Build<|>74%</);
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
  assert.equal(placementNearest(640, 360, 'top').inwardDistance, 72, 'Dragging toward the center keeps the native three-thickness inset cap');
  const preview = placementFrame({mode: 'custom', edge: 'right', offset: 0.5, inwardDistance: 1000}, true);
  assert.equal(1280 - preview.x - preview.width, 72, 'Preview distance is capped by its real 24-point thickness');
  const notch = placementFrame({mode: 'custom', edge: 'top', offset: 0.5, inwardDistance: 0}, true);
  assert.equal(notch.y, 40, 'Preview must clear the physical notch');
});

test('the cursor reaches selected options and the displayed confirmation and import buttons', () => {
  for (const [at, expectedX, expectedY] of [[LAYOUT_ACTIONS.pill, 777, 400], [LAYOUT_ACTIONS.chooseCustom, 777, 439], [LAYOUT_ACTIONS.chick, 777, 400], [LAYOUT_ACTIONS.petRight, 777, 482], [LAYOUT_ACTIONS.chooseFile, 777, 363], [LAYOUT_ACTIONS.importSheet, 780, 432], [LAYOUT_ACTIONS.name, 565, 419], [LAYOUT_ACTIONS.import, 772, 514]]) {
    const state = layoutStateAt(at);
    assert.ok(Math.abs(state.cursor.x - expectedX) < 1 && Math.abs(state.cursor.y - expectedY) < 1, `Cursor misses the selected control at frame ${at}`);
    assert.equal(state.pressed, true);
  }
  const confirmation = layoutStateAt(LAYOUT_ACTIONS.confirm + 1);
  assert.equal(confirmation.cursor.x, 696);
  assert.equal(confirmation.cursor.y, 454);
  assert.equal(confirmation.pressed, true);
  for (const step of CUSTOM_PLACEMENTS.slice(0, -1)) assert.equal(layoutStateAt(step.at + 62).confirmation, 0, 'Only the final choice gets a confirmation');
});

test('pet selection and side change alter the companion, and import applies the chosen name', () => {
  const ui = load('src/scenes/SceneLayouts.tsx');
  const leftFrame = LAYOUT_ACTIONS.pets + 12;
  const left = ui.render(ui.exports.SceneLayouts, {}, leftFrame);
  assert.match(left, /data-pet-id="bear"/);
  assert.match(left, /data-pet-side="left"/);
  const leftState = layoutStateAt(leftFrame);
  assert.equal(leftState.petRect.y + leftState.petRect.height + 4, leftState.rect.y, 'Left pet is above a vertical pill');
  const rightFrame = LAYOUT_ACTIONS.petRight + 12;
  const right = ui.render(ui.exports.SceneLayouts, {}, rightFrame);
  assert.match(right, /data-pet-id="chick"/);
  assert.match(right, /data-pet-side="right"/);
  const rightState = layoutStateAt(rightFrame);
  assert.equal(rightState.petRect.y, rightState.rect.y + rightState.rect.height + 4, 'Right pet is below a vertical pill');
  assert.match(ui.render(ui.exports.SceneLayouts, {}, LAYOUT_ACTIONS.chooseFile + 12), /Pocket Chick.png/);
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
  for (let frame = 0; frame <= LAYOUTS_DURATION; frame += 3) {
    const motion = petMotionAt(frame, 60);
    assert.ok(motion.scale >= 0.97 && motion.scale <= 1.03);
    assert.ok(Math.abs(motion.lift) <= 0.04);
  }
});

test('duration scaling preserves the ending and the confirmed import during crossfade lead', () => {
  const normal = layoutStateAt(510);
  const longer = layoutStateAt(518, 1036);
  assert.deepEqual(normal, longer);
  const last = layoutStateAt(1035, 1036);
  assert.equal(last.importStage, 'imported');
  assert.equal(last.petSide, 'right');
  assert.equal(last.style, 'pill');
  assert.equal(last.placement.mode, 'custom');
  assert.equal(last.placement.edge, 'right');
  assert.ok(last.local < LAYOUTS_DURATION);
  const ui = load('src/scenes/SceneLayouts.tsx');
  const html = ui.render(ui.exports.SceneLayouts, {duration: 1036}, 1035);
  assert.match(html, /Pixel Chick \(Imported\)/);
  assert.match(html, /data-feature="island.custom.right"/);
  assert.match(html, /data-feature="pet.imported"/);
});
