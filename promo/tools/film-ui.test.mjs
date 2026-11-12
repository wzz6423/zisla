import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {buildSync} from 'esbuild';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';
import {CROSSFADE, SCENES, TOTAL_FRAMES} from '../src/timeline.ts';

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
    useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: TOTAL_FRAMES}),
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
  for (let frame = 0; frame <= TOTAL_FRAMES; frame += 120) {
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
  assert.ok(html.includes('scottbuckley.com.au'));
  assert.match(html, /186s edit/);
});

test('the image, audio and PDF tour exposes every current native operation', () => {
  const ui = load('src/modules/CreativeToolsModule.tsx');
  for (const [kind, list, file, name] of [
    ['image', ui.exports.imageOperations, '../../mac/Sources/ZislaKit/ImageProcessingOptions.swift', 'ImageToolOperation'],
    ['audio', ui.exports.audioOperations, '../../mac/Sources/ZislaKit/AudioProcessingModels.swift', 'AudioToolOperation'],
    ['pdf', ui.exports.pdfOperations, '../../mac/Sources/Zisla/PDFToolsModuleView.swift', 'PDFToolOperation'],
  ]) {
    const source = readFileSync(new URL(file, import.meta.url), 'utf8');
    const declaration = source.slice(source.indexOf(`enum ${name}`)).split('var id:')[0];
    const expected = [...declaration.matchAll(/^\s*case (.+)$/gm)].flatMap((match) => match[1].split(',').map((id) => id.trim()));
    assert.deepEqual(list.map(([id]) => id), expected, `${kind}: a native operation is missing or invented`);
    const frames = kind === 'pdf' ? [120, 400] : [120, 300, 480];
    const shown = frames.map((frame) => ui.render(ui.exports.CreativeToolsModule, {kind, frame})).join('');
    for (const [id, label] of list) {
      assert.ok(shown.includes(`data-operation="${id}"`), `${kind}: ${id} never appears in the video`);
      assert.ok(shown.includes(label), `${kind}: ${label} has no visible label`);
    }
  }
});

test('creative tool output is withheld until the current operation completes', () => {
  const ui = load('src/modules/CreativeToolsModule.tsx');
  for (const [kind, completed] of [
    ['image', 'Cover.webp'], ['audio', 'Interview-trimmed.wav'], ['pdf', 'Launch brief.pdf'],
  ]) {
    const pending = ui.render(ui.exports.CreativeToolsModule, {kind, frame: 0});
    assert.match(pending, /Processing…/);
    assert.ok(!pending.includes(completed), `${kind}: output appeared before processing`);
    const done = ui.render(ui.exports.CreativeToolsModule, {kind, frame: 120});
    assert.ok(done.includes(completed), `${kind}: completed output is absent`);
    assert.doesNotMatch(done, /Processing…/);
  }
  const next = ui.render(ui.exports.CreativeToolsModule, {kind: 'audio', frame: 181});
  assert.match(next, /Normalize loudness/);
  assert.match(next, /Processing…/);
  assert.doesNotMatch(next, /Interview-trimmed.wav/);
});

test('the actual film entries render every native module and advertised feature', () => {
  const ui = load('src/LaunchFilm.tsx');
  const entries = ui.exports.ENTRIES;
  assert.deepEqual(entries.map((entry) => entry.id), Object.keys(SCENES), 'A timeline scene is absent from the film');
  const rendered = new Map(entries.map((entry) => {
    const lead = entry.from === 0 ? 0 : CROSSFADE;
    const props = {duration: entry.duration + lead, globalFrom: entry.from - lead};
    const samples = Array.from({length: Math.ceil(entry.duration / 30)}, (_, index) => ui.render(entry.Scene, props, lead + index * 30));
    samples.push(ui.render(entry.Scene, props, entry.duration + lead - 1));
    return [entry.id, samples.join('')];
  }));
  const moduleCoverage = {
    dashboard: ['awakening', 'Paper Lanterns'], shelf: ['flow', 'Show in Finder'],
    clipboard: ['everyday', 'Copied to clipboard'], download: ['flow', 'Interview.m4a saved'],
    agenda: ['everyday', 'Reminder completed'], toolbox: ['desktop', 'Focus completed'],
    quickNotes: ['everyday', 'Saved to Apple Notes'], aiMonitor: ['aiCenter', 'Input '],
    keyboardSound: ['desktop', '14 characters added'], mail: ['mail', 'Message sent'],
    system: ['desktop', 'Saved: System history.xlsx'], volumeMixer: ['desktop', 'Music muted'],
  };
  const native = readFileSync(new URL('../../mac/Sources/ZislaCore/FeatureSettings.swift', import.meta.url), 'utf8');
  const nativeOrder = native.slice(native.indexOf('enum IslandModuleOrder')).match(/defaultOrder: \[Self\] = \[([\s\S]*?)\]/)[1];
  assert.deepEqual(Object.keys(moduleCoverage).sort(), [...nativeOrder.matchAll(/\.(\w+)/g)].map((match) => match[1]).sort());
  const featureCoverage = {
    floatingIsland: ['layouts', 'island.camera'], pet: ['layouts', 'Pixel Chick (Imported)'],
    dailyBriefing: ['everyday', 'Saved: Daily briefing'], userCare: ['everyday', 'resets the reminder timer'],
    contextNotes: ['everyday', 'Saved · Shown when you return'], windowPreviews: ['settings', 'Notes window activated'],
    capture: ['creative', 'Long capture pinned'], recording: ['creative', 'Product walkthrough.mp4 exported'],
    voice: ['everyday', 'Cleaned transcript inserted'], media: ['flow', 'Paper Lanterns'],
    browserDownloads: ['flow', 'Open Folder'], copyAssistant: ['settings', '€18.40 copied'],
    aiManagement: ['settings', 'Skills synced to enabled CLIs'], pdf: ['creative', 'Launch brief-protected.pdf'],
    permissions: ['settings', 'Microphone permission granted'], lockScreen: ['settings', 'Playback paused'],
    recommendedTools: ['settings', 'Quiet.md opened as a separate app'],
  };
  const website = readFileSync(new URL('../../web/src/content.ts', import.meta.url), 'utf8');
  const advertised = website.match(/crossModuleFeatureIds = \[([\s\S]*?)\]/)[1];
  assert.deepEqual(Object.keys(featureCoverage).sort(), [...advertised.matchAll(/'([^']+)'/g)].map((match) => match[1]).sort());
  for (const [feature, [scene, outcome]] of Object.entries({...moduleCoverage, ...featureCoverage})) {
    assert.ok(rendered.get(scene).includes(outcome), `${feature}: its advertised outcome never appears in the actual film`);
  }
  for (const feature of ['island.notch', 'island.custom.top', 'island.custom.bottom', 'island.custom.left', 'island.custom.right', 'pet.left', 'pet.right']) {
    assert.ok(rendered.get('layouts').includes(feature), `${feature}: missing from the actual film`);
  }
  for (const outcome of ['Subject.png', 'Interview-normalized.wav', 'Test-tone.wav']) assert.ok(rendered.get('creative').includes(outcome));
  for (const outcome of ['Keyboard input resumed', 'Camera stopped', 'Review item kept', 'Low power mode applied', 'macOS background sounds']) assert.ok(rendered.get('desktop').includes(outcome));
});

test('native link downloading chooses source format and reaches a saved audio file', () => {
  const ui = load('src/modules/DownloadTourModule.tsx');
  const {DownloadTourModule, downloadPlatforms, nativeDownloadAt} = ui.exports;
  assert.equal(nativeDownloadAt(0).phase, 'ready');
  assert.equal(nativeDownloadAt(55).mode, 'video');
  assert.equal(nativeDownloadAt(75).mode, 'audio');
  assert.equal(nativeDownloadAt(120).phase, 'downloading');
  const pending = ui.render(DownloadTourModule, {frame: 120});
  assert.match(pending, /Downloading audio/);
  assert.doesNotMatch(pending, /Interview.m4a saved/);
  const completed = ui.render(DownloadTourModule, {frame: 165});
  assert.match(completed, /Interview.m4a saved/);
  assert.match(completed, /Open in Finder/);
  assert.match(completed, /Chrome · Default cookies/);
  const native = readFileSync(new URL('../../mac/Sources/ZislaKit/VideoDownloadPlatform.swift', import.meta.url), 'utf8').split('public var displayName')[0];
  assert.deepEqual(downloadPlatforms.map(([id]) => id), [...native.matchAll(/^\s*case (\w+)$/gm)].map((match) => match[1]));
  for (const [id, label] of downloadPlatforms) assert.ok(completed.includes(`data-platform="${id}">${label}`));
});

test('the creative tour keeps its last operation result through the crossfade lead', () => {
  const ui = load('src/scenes/SceneCreativeTools.tsx');
  assert.deepEqual(ui.exports.creativeTourAt(-1), ui.exports.creativeTourAt(0));
  assert.deepEqual(ui.exports.creativeTourAt(1800), ui.exports.creativeTourAt(1800 * 2716 / 2700, 2716));
  assert.equal(ui.exports.creativeTourAt(3000).frame, 539);
  const last = ui.exports.creativeTourAt(2715, 2716);
  assert.equal(last.group.id, 'pdf');
  const html = ui.render(ui.exports.SceneCreativeTools, {duration: 2716}, 2715);
  assert.match(html, /Launch brief-protected.pdf/);
  assert.match(html, /data-feature="pdf" style="opacity:1"/);
});
