import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));

// Only the clock, composition context and image loading are isolated; scene JSX stays intact.
const load = (entryPoint) => {
  const clock = {frame: 0};
  const bundle = buildSync({
    absWorkingDir: root,
    entryPoints: [entryPoint],
    bundle: true,
    packages: 'external',
    platform: 'node',
    format: 'cjs',
    jsx: 'automatic',
    write: false,
    loader: {'.svg': 'dataurl', '.png': 'dataurl'},
  });
  const module = {exports: {}};
  const isolatedRequire = (name) => name === 'remotion' ? {
    ...Remotion,
    useCurrentFrame: () => clock.frame,
    useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 3600}),
    Img: (props) => React.createElement('img', props),
  } : require(name);
  new Function('require', 'module', 'exports', bundle.outputFiles[0].text)(isolatedRequire, module, module.exports);
  return {
    exports: module.exports,
    render: (Component, props = {}, frame = 0) => {
      clock.frame = frame;
      return renderToStaticMarkup(React.createElement(Component, props));
    },
  };
};

test('model totals and account warnings match the visible fictional data', () => {
  const ui = load('src/modules/AIAnalyticsModule.tsx');
  const {AIAnalyticsModule, aiModelUsage, aiModelTokenTotal, aiGatewayBalances} = ui.exports;
  assert.equal(aiModelTokenTotal, 601_000);
  assert.equal(aiModelTokenTotal, aiModelUsage.reduce((total, item) => total + item.inputTokens + item.outputTokens, 0));
  const original = aiGatewayBalances[0].available;
  try {
    for (const [available, warnings] of [[original, 1], [aiGatewayBalances[0].minimumBalance, 1], [aiGatewayBalances[0].minimumBalance - 0.01, 2], [0, 2]]) {
      aiGatewayBalances[0].available = available;
      const html = ui.render(AIAnalyticsModule);
      assert.equal((html.match(/Low balance · min/g) ?? []).length, warnings);
      assert.equal((html.match(/Checked 09:41/g) ?? []).length, 3);
      assert.equal((html.match(/Input /g) ?? []).length, 3);
      assert.equal((html.match(/Output /g) ?? []).length, 3);
    }
  } finally {
    aiGatewayBalances[0].available = original;
  }
});

test('reading mail, completing a draft and sending follow the displayed state sequence', () => {
  const ui = load('src/scenes/SceneMail.tsx');
  const {SceneMail} = ui.exports;
  assert.doesNotMatch(ui.render(SceneMail, {}, 60), /New Message/);
  assert.match(ui.render(SceneMail, {}, 100), /10:30 review/);
  assert.match(ui.render(SceneMail, {}, 225), /New Message/);
  assert.match(ui.render(SceneMail, {}, 285), /mira\.solen@example\.com/);
  assert.match(ui.render(SceneMail, {}, 458), /See you at 10:30\./);
  assert.doesNotMatch(ui.render(SceneMail, {}, 458), /Message sent/);
  assert.match(ui.render(SceneMail, {}, 480), /lucide-loader-circle/);
  const sent = ui.render(SceneMail, {}, 530);
  assert.match(sent, /Message sent/);
  assert.doesNotMatch(sent, /New Message/);
});

test('image, audio and PDF previews show completed output only at the end', () => {
  const ui = load('src/modules/ToolsModule.tsx');
  for (const [Component, pending, completed] of [
    [ui.exports.ImagesModule, 'Processing image', 'Resized and converted'],
    [ui.exports.AudioModule, 'Processing audio', 'Audio processed'],
    [ui.exports.PDFModule, 'Merging documents', 'Merged · 8 pages'],
  ]) {
    assert.match(ui.render(Component, {frame: 2900, progress: 0}), new RegExp(pending));
    assert.match(ui.render(Component, {frame: 2900, progress: 1}), new RegExp(completed));
  }
});

test('system previews stay deterministic and within their displayed units', () => {
  const {systemReadingsAt} = load('src/modules/SystemModule.tsx').exports;
  for (let frame = 0; frame <= 3600; frame += 120) {
    const reading = systemReadingsAt(frame);
    assert.deepEqual(reading, systemReadingsAt(frame));
    assert.ok(reading.cpu >= 0 && reading.cpu <= 1);
    assert.ok(reading.gpu >= 0 && reading.gpu <= 1);
    assert.ok(reading.memoryUsedGB > 0 && reading.memoryUsedGB <= reading.memoryTotalGB);
    assert.ok(reading.downloadMB > 0 && reading.uploadKB > 0);
  }
});

test('the outro credits the music author, license and excerpt', () => {
  const ui = load('src/scenes/Scene5Outro.tsx');
  const html = ui.render(ui.exports.Scene5Outro, {}, 300);
  assert.match(html, /Music: Origami by Scott Buckley/);
  assert.match(html, /CC BY 4\.0/);
  assert.match(html, /scottbuckley\.com\.au/);
  assert.match(html, /60s edit/);
});
