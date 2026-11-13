import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {buildSync} from 'esbuild';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';
import {FPS, CROSSFADE, SCENES, TOTAL_FRAMES} from '../src/timeline.ts';

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

test('model totals and quota warnings preserve their native units', () => {
  const ui = load('src/modules/AIAnalyticsModule.tsx');
  const {AIAnalyticsModule, aiModelUsage, aiModelTokenTotal, aiBalancesAt} = ui.exports;
  assert.equal(aiModelTokenTotal, 601_000);
  assert.equal(aiModelTokenTotal, aiModelUsage.reduce((total, item) => total + item.inputTokens + item.outputTokens, 0));
  const normal = ui.render(AIAnalyticsModule, {balances: aiBalancesAt(false)});
  const low = ui.render(AIAnalyticsModule, {balances: aiBalancesAt(true)});
  assert.ok(normal.includes('72%') && low.includes('8%'));
  for (const html of [normal, low]) {
    assert.ok(html.includes('5h') && html.includes('7d'));
    assert.ok(html.includes('$68.5'), 'Cursor budget is retained as USD');
  }
});

test('mail sends once, then marks the inbox read without replaying the composer', () => {
  const ui = load('src/scenes/SceneMail.tsx');
  const {SceneMail, MAIL_TIMING: timing} = ui.exports;
  assert.doesNotMatch(ui.render(SceneMail, {}, timing.read), /New Message/);
  assert.match(ui.render(SceneMail, {}, timing.compose + 16), /New Message/);
  assert.match(ui.render(SceneMail, {}, timing.subject), /mira\.solen@example\.com/);
  assert.match(ui.render(SceneMail, {}, timing.send - 1), /See you at 10:30\./);
  assert.match(ui.render(SceneMail, {}, timing.send + 5), /lucide-loader-circle/);
  const sent = ui.render(SceneMail, {}, timing.sent + 18);
  assert.match(sent, /Message sent/);
  assert.doesNotMatch(sent, /New Message/);
  for (const frame of [timing.allRead, 539, 580]) {
    const done = ui.render(SceneMail, {}, frame);
    assert.match(done, /All messages marked as read/);
    assert.doesNotMatch(done, /New Message/);
  }
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

test('each version credits only its own music and continuous excerpt', () => {
  const ui = load('src/scenes/Scene5Outro.tsx');
  for (const [music, title, artist, site] of [['funk', 'Funkorama', 'Kevin MacLeod', 'incompetech.com'], ['cinematic', 'The Miracle of Flight', 'Scott Buckley', 'scottbuckley.com.au']]) {
    const html = ui.render(ui.exports.Scene5Outro, {music}, 210);
    assert.ok(html.includes(`Music: ${title} by ${artist}`));
    assert.ok(html.includes(site));
    assert.match(html, /CC BY 4\.0/);
    assert.ok(html.includes(`${TOTAL_FRAMES / FPS}s continuous edit`));
    assert.ok(!html.includes('Origami'));
  }
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
    const end = ui.exports.creativeToolSteps[kind].at(-1);
    const frames = Array.from({length: Math.ceil((end.from + end.duration) / 10)}, (_, i) => i * 10);
    const shown = frames.map((frame) => ui.render(ui.exports.CreativeToolsModule, {kind, frame})).join('');
    for (const [id, label] of list) {
      assert.ok(shown.includes(`data-operation="${id}"`), `${kind}: ${id} never appears in the video`);
      assert.ok(shown.includes(label), `${kind}: ${label} has no visible label`);
    }
  }
});

test('creative tool output is withheld until the selected operation completes', () => {
  const ui = load('src/modules/CreativeToolsModule.tsx');
  for (const kind of ['image', 'audio', 'pdf']) {
    for (const step of ui.exports.creativeToolSteps[kind]) {
      const pending = ui.render(ui.exports.CreativeToolsModule, {kind, frame: step.from + step.actionAt});
      assert.match(pending, /Processing…/);
      assert.ok(!pending.includes(`data-creative-output`));
      const done = ui.render(ui.exports.CreativeToolsModule, {kind, frame: step.from + step.completeAt});
      assert.ok(done.includes(step.output));
      assert.doesNotMatch(done, /Processing…/);
    }
  }
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
    dailyBriefing: ['everyday', 'Saved: Daily briefing'], userCare: ['settings', 'resets the reminder timer'],
    contextNotes: ['everyday', 'Saved · Shown when you return'], windowPreviews: ['settings', 'Notes window activated'],
    capture: ['creative', 'Pinned · Existing pins retained'], recording: ['creative', 'Exported · 12 seconds'],
    voice: ['everyday', 'Cleaned transcript inserted'], media: ['flow', 'Paper Lanterns'],
    browserDownloads: ['flow', 'Open Folder'], copyAssistant: ['settings', '€18.40 copied'],
    aiManagement: ['settings', 'Skills synced to enabled CLIs'], pdf: ['creative', 'Launch brief-protected.pdf'],
    permissions: ['settings', 'Microphone permission granted'], lockScreen: ['settings', 'Playback paused'],
    recommendedTools: ['settings', 'Quiet.md opened as a separate app'],
    imageTools: ['creative', 'Subject.png'], audioTools: ['creative', 'Interview-normalize.wav'],
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
  for (const outcome of ['Subject.png', 'Interview-normalize.wav', 'Test-tone.wav']) assert.ok(rendered.get('creative').includes(outcome));
  for (const outcome of ['Keyboard input resumed', 'Camera stopped', 'Review item kept', 'Low power mode applied', 'macOS background sounds', 'Charge to 100% requested']) assert.ok(rendered.get('desktop').includes(outcome));
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

test('the creative tour keeps its final result when compressed and through the crossfade', () => {
  const ui = load('src/scenes/SceneCreativeTools.tsx');
  const nominal = ui.exports.CREATIVE_TOUR_DURATION;
  assert.deepEqual(ui.exports.creativeTourAt(-1), ui.exports.creativeTourAt(0));
  for (const duration of [nominal, SCENES.creative.duration + CROSSFADE]) {
    const last = ui.exports.creativeTourAt(duration - 1, duration);
    assert.equal(last.group.id, 'pdf');
    assert.ok(last.frame >= 298 && last.frame <= 299);
    assert.equal(ui.exports.creativeTourAt(duration + 20, duration).group.id, last.group.id);
    const html = ui.render(ui.exports.SceneCreativeTools, {duration}, duration - 1);
    assert.match(html, /Launch brief-protected.pdf/);
  }
});
