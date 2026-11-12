import assert from 'node:assert/strict';
import test from 'node:test';
import {FPS, CROSSFADE, SCENES, TOTAL_FRAMES, filmFrame} from '../src/timeline.ts';
import {SHELF_LAYOUT, shelfItemLayout, shelfItemPoint, shelfMenuPlacement} from '../src/modules/shelfLayout.ts';
import {ConfigInternals} from '@remotion/cli/config';
import '../remotion.config.ts';

test('Studio asset URLs stay inside the server when icons live outside promo', async () => {
  const config = await ConfigInternals.getBundlerOverrideFn()({mode: 'development', output: {}, module: {rules: []}}, {bundler: 'webpack'});
  const template = config.output.assetModuleFilename;
  for (const source of ['../web/public/assets/zisla-icon.png', '../mac/Resources/BrandIcons/github-mark.svg']) {
    const path = source.slice(0, source.lastIndexOf('/') + 1);
    const filename = source.slice(source.lastIndexOf('/') + 1);
    const dot = filename.lastIndexOf('.');
    const emitted = template.replace('[path]', path).replace('[name]', filename.slice(0, dot)).replace('[hash]', '12345678').replace('[ext]', filename.slice(dot));
    const resolved = new URL(emitted, 'http://localhost:3000/');
    assert.equal(resolved.pathname.split('/').length, 2, `Imported icon escapes the asset root: ${source}`);
    assert.equal(emitted.includes('..'), false);
  }
});

test('the six demonstrations fill exactly sixty seconds without timeline gaps', () => {
  const scenes = Object.values(SCENES);
  assert.equal(scenes.length, 6);
  assert.equal(FPS, 60);
  assert.equal(TOTAL_FRAMES, 3600);
  assert.equal(scenes[0].from, 0);
  for (let index = 1; index < scenes.length; index++) {
    assert.equal(scenes[index].from, scenes[index - 1].from + scenes[index - 1].duration);
  }
  assert.equal(scenes.reduce((total, scene) => total + scene.duration, 0), TOTAL_FRAMES);
});

test('media and focus readouts preserve global time through every crossfade', () => {
  for (const [name, scene] of Object.entries(SCENES)) {
    const lead = scene.from === 0 ? 0 : CROSSFADE;
    assert.equal(filmFrame(name, lead), scene.from);
    assert.equal(filmFrame(name, scene.duration + lead - 1), scene.from + scene.duration - 1);
  }
});

test('a dropped file and its grid icon share the same target, including a new row', () => {
  for (const index of [0, 7, 8, 15]) {
    const item = shelfItemLayout(index);
    const point = shelfItemPoint(index);
    assert.equal(point.x, SHELF_LAYOUT.shareWidth + SHELF_LAYOUT.columnGap + 1 + item.left + item.width / 2);
    assert.equal(point.y, 1 + SHELF_LAYOUT.gridTop + item.top + 25);
    assert.ok(item.left >= 0 && item.top >= 0);
  }
  assert.equal(shelfItemLayout(8).left, shelfItemLayout(0).left);
  assert.equal(shelfItemLayout(8).top - shelfItemLayout(0).top, SHELF_LAYOUT.pitchY);
});

test('the file menu follows its anchor and flips at the screen edges', () => {
  const viewport = {width: 1280, height: 720};
  assert.deepEqual(shelfMenuPlacement({x: 700, y: 300}, viewport), {x: 700, y: 300, transformOrigin: 'top left'});
  const corner = shelfMenuPlacement({x: 1270, y: 710}, viewport);
  assert.equal(corner.x, 1270 - SHELF_LAYOUT.menuWidth);
  assert.equal(corner.y, 710 - SHELF_LAYOUT.menuHeight);
  assert.equal(corner.transformOrigin, 'bottom right');
  for (const x of [-50, 0, 8, 640, 1279, 1350]) {
    for (const y of [-50, 0, 8, 360, 719, 780]) {
      const menu = shelfMenuPlacement({x, y}, viewport);
      assert.ok(menu.x >= 8 && menu.x + SHELF_LAYOUT.menuWidth <= viewport.width - 8, `Menu clipped horizontally at ${x},${y}`);
      assert.ok(menu.y >= 8 && menu.y + SHELF_LAYOUT.menuHeight <= viewport.height - 8, `Menu clipped vertically at ${x},${y}`);
    }
  }
});
