import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {buildSync} from 'esbuild';
import {parseFragment} from 'parse5';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));
const load = (entryPoint) => {
  const clock = {frame: 0};
  const bundle = buildSync({absWorkingDir: root, entryPoints: [entryPoint], bundle: true, packages: 'external', platform: 'node', format: 'cjs', jsx: 'automatic', write: false, loader: {'.svg': 'dataurl', '.png': 'dataurl'}});
  const module = {exports: {}};
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 10000}), Img: (props) => React.createElement('img', props)} : require(name);
  new Function('require', 'module', 'exports', bundle.outputFiles[0].text)(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props = {}, frame = 0) => {clock.frame = frame; return renderToStaticMarkup(React.createElement(Component, props));}};
};
const walk = (node) => [node, ...(node.childNodes ?? []).flatMap(walk)];
const attr = (node, name) => node.attrs?.find((item) => item.name === name)?.value;
const nodes = (html) => walk(parseFragment(html));
const textOf = (html) => html.replace(/<[^>]*>/g, '').replaceAll('&amp;', '&');
const styleOf = (node) => Object.fromEntries((attr(node, 'style') ?? '').split(';').filter(Boolean).map((declaration) => {
  const colon = declaration.indexOf(':');
  return [declaration.slice(0, colon), declaration.slice(colon + 1)];
}));
const heightOf = (node) => {
  if (node.nodeName === '#text') return node.value.trim() ? 18 : 0;
  const style = styleOf(node);
  const pixels = (value) => /^\d+(\.\d+)?px$/.test(value ?? '') ? Number.parseFloat(value) : 0;
  if (pixels(style.height)) return pixels(style.height);
  if (node.tagName === 'svg') return Number(attr(node, 'height')) || 20;
  const children = (node.childNodes ?? []).filter((child) => child.nodeName !== '#comment');
  if (!children.length) return pixels(style['line-height']) || (pixels(style['font-size']) ? Math.ceil(pixels(style['font-size']) * 1.5) : 0);
  const className = attr(node, 'class') ?? '';
  const column = className.includes('flex-col') || (!className.includes('flex') && style.display !== 'flex');
  const gap = className.match(/gap-\[(\d+)px\]/)?.[1];
  const margin = children.reduce((sum, child) => sum + pixels(styleOf(child)['margin-top']) + pixels(styleOf(child)['margin-bottom']), 0);
  const padding = (style.padding ?? '').split(' ');
  const top = padding.length ? pixels(padding[0]) : 0;
  const bottom = padding.length > 2 ? pixels(padding[2]) : top;
  let content;
  if (style.display === 'grid') content = Math.ceil(children.length / 2) * (pixels(style['line-height']) + 1);
  else if (column) content = children.reduce((sum, child) => sum + heightOf(child), 0) + Number(gap ?? 0) * (children.length - 1) + margin;
  else content = Math.max(...children.map(heightOf));
  return Math.max(pixels(style['min-height']), top + bottom + content);
};

test('screenshot content and annotation share one aspect-preserving SVG', () => {
  const ui = load('src/modules/ToolsModule.tsx');
  const html = ui.render(ui.exports.ScreenshotsModule, {annotation: 1});
  const svg = nodes(html).find((node) => node.tagName === 'svg' && attr(node, 'viewBox') !== '0 0 24 24' && attr(node, 'viewBox'));
  assert.ok(svg, 'The screenshot has no coordinate canvas');
  assert.equal(attr(svg, 'preserveAspectRatio'), 'xMidYMid meet');
  assert.ok(walk(svg).some((node) => node.nodeName === '#text' && node.value === 'Ready for review.'), 'The review row must scale with its annotations');
  assert.doesNotMatch(html, /preserveAspectRatio="none"/);
  const checkbox = walk(svg).find((node) => attr(node, 'data-review-checkbox') !== undefined);
  const box = walk(svg).find((node) => attr(node, 'data-review-box') !== undefined);
  const row = walk(svg).find((node) => attr(node, 'data-review-text') !== undefined);
  const arrow = walk(svg).find((node) => attr(node, 'data-review-arrow') !== undefined);
  assert.ok(checkbox && box && row && arrow, 'The annotation target must be identifiable inside the canvas');
  const number = (node, name) => Number(attr(node, name));
  const [x, y, width, height] = ['x', 'y', 'width', 'height'].map((name) => number(box, name));
  assert.ok(number(checkbox, 'x') > x && number(checkbox, 'x') + number(checkbox, 'width') < x + width);
  assert.ok(number(checkbox, 'y') > y && number(checkbox, 'y') + number(checkbox, 'height') < y + height);
  assert.ok(number(row, 'x') > number(checkbox, 'x') + number(checkbox, 'width') && number(row, 'x') < x + width - 200);
  assert.ok(number(row, 'y') > y + 20 && number(row, 'y') < y + height);
  const tip = attr(arrow, 'd').match(/L([\d.]+) ([\d.]+)/);
  assert.equal(Number(tip[1]), x + width, 'The arrow tip must land on the review border');
  assert.ok(Number(tip[2]) > y && Number(tip[2]) < y + height);
});

test('capture draws once, scrolls slowly once and preserves annotations for pin and OCR', () => {
  const ui = load('src/modules/ToolsModule.tsx');
  const at = ui.exports.screenshotTourState;
  assert.deepEqual(at(-1), at(0));
  assert.deepEqual(at(500), at(359));
  assert.equal(at(17).hdr, false);
  assert.equal(at(18).hdr, true);
  assert.equal(at(38).rectangle, 0);
  assert.equal(at(66).arrow, 0);
  assert.equal(at(106).obscure, 0);
  assert.equal(at(66).rectangle, 1);
  assert.equal(at(96).arrow, 1);
  assert.equal(at(124).obscure, 1);
  let previousScroll = 0;
  for (let frame = 0; frame < 360; frame++) {
    const state = at(frame);
    assert.ok(state.scroll >= previousScroll);
    assert.ok(state.scroll - previousScroll < 0.02, 'Long capture jumps instead of scrolling slowly');
    previousScroll = state.scroll;
    if (frame >= 124) assert.deepEqual([state.rectangle, state.arrow, state.obscure], [1, 1, 1]);
  }
  assert.match(ui.render(ui.exports.ScreenshotsModule, {frame: 210}), /data-long-capture-preview/);
  assert.doesNotMatch(ui.render(ui.exports.ScreenshotsModule, {frame: 270}), /data-long-capture-preview/);
  assert.match(ui.render(ui.exports.ScreenshotsModule, {frame: 235}), /data-capture-recognition-menu/);
  assert.match(ui.render(ui.exports.ScreenshotsModule, {frame: 250}), /data-capture-table-export/);
  assert.match(textOf(ui.render(ui.exports.ScreenshotsModule, {frame: 282})), /Recognizing table…/);
  assert.match(textOf(ui.render(ui.exports.ScreenshotsModule, {frame: 310})), /Review schedule.xlsx exported/);
  assert.match(ui.render(ui.exports.ScreenshotsModule, {frame: 350}), /data-pinned-capture/);
  assert.doesNotMatch(ui.render(ui.exports.ScreenshotsModule, {frame: 350}), /data-capture-table-export/);
  assert.match(textOf(ui.render(ui.exports.ScreenshotsModule, {frame: 350})), /Pinned · Existing pins retained/);
});

test('recording phase ordering, selected caption and proposal result stay causal', () => {
  const ui = load('src/modules/ToolsModule.tsx');
  const at = ui.exports.recordingTourState;
  const phases = ['capture', 'clip', 'effects', 'captions', 'ai', 'export'];
  assert.deepEqual(at(-10), at(0));
  assert.deepEqual(at(900), at(719));
  let phase = 0;
  let previous = 0;
  for (let frame = 0; frame < 720; frame++) {
    const state = at(frame);
    const next = phases.indexOf(state.phase);
    assert.ok(next >= phase && next <= phase + 1, `Phase restarts or skips at ${frame}`);
    assert.ok(state.playbackTime >= previous, `Timeline restarts at ${frame}`);
    previous = state.playbackTime;
    phase = next;
  }
  assert.equal(at(650).playbackTime, 12);
  assert.equal(at(10).captured, false);
  assert.equal(at(110).recording, true);
  assert.equal(at(140).paused, true);
  assert.equal(at(150).captured, true);
  assert.match(textOf(ui.render(ui.exports.RecordingStudioTour, {frame: 110})), /Recording/);
  assert.match(textOf(ui.render(ui.exports.RecordingStudioTour, {frame: 140})), /Paused/);
  assert.match(textOf(ui.render(ui.exports.RecordingStudioTour, {frame: 166})), /Recording saved/);
  assert.equal(at(480).proposal, false);
  assert.equal(at(510).proposal, true);
  assert.equal(at(535).applied, false);
  assert.equal(at(536).applied, true);
  const early = ui.render(ui.exports.RecordingStudioTour, {frame: 370});
  assert.doesNotMatch(early, /data-studio-caption/);
  const edited = nodes(ui.render(ui.exports.RecordingStudioTour, {frame: 435}));
  const preview = edited.find((node) => attr(node, 'data-studio-caption') !== undefined);
  const inspector = edited.find((node) => attr(node, 'data-caption-editor') !== undefined);
  const content = (node) => walk(node).filter((item) => item.nodeName === '#text').map((item) => item.value).join('');
  assert.equal(content(preview), content(inspector), 'Edited captions disagree with the selected inspector');
  assert.equal(content(preview), 'Your work, always within reach.');
  for (const frame of [250, 335, 435, 530, 680]) {
    const html = ui.render(ui.exports.RecordingStudioTour, {frame});
    for (const id of ['data-studio-library', 'data-studio-preview', 'data-studio-inspector', 'data-studio-timeline']) assert.ok(html.includes(id), `${id} is absent`);
  }
  assert.doesNotMatch(ui.render(ui.exports.RecordingStudioTour, {frame: 620}), /data-recording-output/);
  assert.match(ui.render(ui.exports.RecordingStudioTour, {frame: 670}), /data-recording-output/);
  assert.match(textOf(ui.render(ui.exports.RecordingStudioTour, {frame: 710})), /Product walkthrough.mp4Exported · 12 seconds/);
  assert.equal(at(35).portraitMenu, true);
  assert.equal(at(84).portraitMenu, false);
  assert.equal(at(60).portrait, 1);
  assert.match(textOf(ui.render(ui.exports.RecordingStudioTour, {frame: 64})), /Skin smoothing35%Brighten16%Slim face8%Slim body5%VoiceNatural/);
  assert.match(ui.render(ui.exports.RecordingStudioTour, {frame: 335}), /data-preview-camera/);
  assert.doesNotMatch(ui.render(ui.exports.RecordingStudioTour, {frame: 10}), /data-recording-portrait/);
  assert.equal(at(184).trim, 0);
  assert.equal(at(235).trim, 1);
  assert.equal(at(264).zoom, 1);
  assert.equal(at(335).zoom, 1.2);
  assert.equal(at(236).animation, 0);
  assert.equal(at(230).playbackDuration, 16);
  assert.equal(at(538).playbackDuration, 12);
  assert.match(textOf(ui.render(ui.exports.RecordingStudioTour, {frame: 260})), /Entrance animationFade · 0.5s/);
  assert.equal(at(260).animation, 1);
  const trail = nodes(ui.render(ui.exports.RecordingStudioTour, {frame: 335})).find((node) => attr(node, 'data-preview-cursor-trail') !== undefined);
  assert.ok(Number(styleOf(trail).opacity) > 0);
  assert.match(textOf(ui.render(ui.exports.RecordingStudioTour, {frame: 620})), /Exporting recording…/);
  assert.equal(at(654).exporting, false);
});

test('every tool output follows its selected operation and a readable completion hold', () => {
  const ui = load('src/modules/CreativeToolsModule.tsx');
  for (const kind of ['image', 'audio', 'pdf']) {
    const steps = ui.exports.creativeToolSteps[kind];
    let previous = 0;
    for (const step of steps) {
      assert.equal(step.from, previous);
      assert.ok(step.actionAt < step.completeAt);
      assert.ok(step.duration - step.completeAt >= 34, `${kind}/${step.operation} has no result hold`);
      for (const [frame, completed] of [[step.from, false], [step.from + step.actionAt + 1, false], [step.from + step.completeAt + 3, true]]) {
        const html = ui.render(ui.exports.CreativeToolsModule, {kind, frame});
        assert.ok(html.includes(`data-current-operation="${step.operation}"`));
        assert.equal(html.includes('data-creative-output'), completed);
        if (frame > step.from && !completed) {
          assert.equal(ui.exports.creativeToolState(kind, frame).busy, true);
          assert.match(textOf(html), /Processing…Cancel/);
        }
        if (completed) assert.ok(textOf(html).includes(step.output));
        else assert.ok(!textOf(html).includes(step.output), `${step.output} appears before completion`);
      }
      previous = step.from + step.duration;
    }
    assert.deepEqual(ui.exports.creativeToolState(kind, -1), ui.exports.creativeToolState(kind, 0));
    assert.deepEqual(ui.exports.creativeToolState(kind, previous + 100), ui.exports.creativeToolState(kind, previous - 1));
  }
  const normalize = textOf(ui.render(ui.exports.CreativeToolsModule, {kind: 'audio', frame: 165}));
  assert.match(normalize, /Interview-trim.wav/);
  assert.match(normalize, /Target loudness \(LUFS\)/);
  assert.doesNotMatch(normalize, /Start time|End time|Frequency/);
  const tone = textOf(ui.render(ui.exports.CreativeToolsModule, {kind: 'audio', frame: 320}));
  assert.doesNotMatch(tone, /Interview/);
  assert.match(tone, /Frequency \(Hz\)440/);
  const protect = textOf(ui.render(ui.exports.CreativeToolsModule, {kind: 'pdf', frame: 230}));
  assert.match(protect, /Launch brief.pdf8 pages/);
  assert.match(protect, /Open password/);
  const lasso = ui.render(ui.exports.CreativeToolsModule, {kind: 'image', frame: 350});
  assert.match(lasso, /data-image-editor/);
  assert.match(lasso, /Freehand selection/);
  assert.doesNotMatch(ui.render(ui.exports.CreativeToolsModule, {kind: 'image', frame: 415}), /data-image-editor/);
  assert.match(ui.render(ui.exports.CreativeToolsModule, {kind: 'image', frame: 415}), /Transparent PNG/);
  assert.ok(ui.render(ui.exports.CreativeToolsModule, {kind: 'image', frame: 415}).includes('repeating-conic-gradient'), 'Extraction output keeps its original background');
  const comparison = textOf(ui.render(ui.exports.CreativeToolsModule, {kind: 'image', frame: 120}));
  for (const format of ['PNG1.2 MB', 'JPEG246 KB', 'WebP118 KB', 'AVIF134 KB', 'JPEG XL157 KB']) assert.ok(comparison.includes(format), format);
});

test('native operation lists remain complete while the selected row is visible during scrolling', () => {
  const ui = load('src/modules/CreativeToolsModule.tsx');
  for (const [kind, file, name] of [
    ['image', '../../mac/Sources/ZislaKit/ImageProcessingOptions.swift', 'ImageToolOperation'],
    ['audio', '../../mac/Sources/ZislaKit/AudioProcessingModels.swift', 'AudioToolOperation'],
    ['pdf', '../../mac/Sources/Zisla/PDFToolsModuleView.swift', 'PDFToolOperation'],
  ]) {
    const source = readFileSync(new URL(file, import.meta.url), 'utf8');
    const declaration = source.slice(source.indexOf(`enum ${name}`)).split('var id:')[0];
    const expected = [...declaration.matchAll(/^\s*case (.+)$/gm)].flatMap((match) => match[1].split(',').map((id) => id.trim()));
    const list = ui.exports[`${kind}Operations`];
    assert.deepEqual(list.map(([id]) => id), expected);
    const end = ui.exports.creativeToolSteps[kind].at(-1);
    const shown = new Set();
    for (let frame = 0; frame < end.from + end.duration; frame += 4) {
      const current = ui.exports.creativeToolState(kind, frame);
      const viewport = ui.exports.operationWindow(kind, frame);
      const index = list.findIndex(([id]) => id === current.step.operation);
      const y = (index - viewport.first) * viewport.rowHeight + viewport.offset;
      assert.ok(y >= -0.001 && y + viewport.rowHeight <= viewport.height + 0.001, `${kind} selected ${current.step.operation} is clipped at ${frame}`);
      for (const node of nodes(ui.render(ui.exports.CreativeToolsModule, {kind, frame}))) {
        const id = attr(node, 'data-operation');
        if (id) shown.add(id);
      }
    }
    for (const id of expected) assert.ok(shown.has(id), `${kind}/${id} never appears`);
  }
});

test('the creative group budget scales across crossfade leads and retains the final output', () => {
  const ui = load('src/scenes/SceneCreativeTools.tsx');
  const duration = ui.exports.CREATIVE_TOUR_DURATION;
  assert.equal(duration, 2160);
  assert.equal(ui.exports.creativeGroups.reduce((sum, group) => sum + group.duration, 0), duration);
  assert.deepEqual(ui.exports.creativeTourAt(-1), ui.exports.creativeTourAt(0));
  for (const group of ui.exports.creativeGroups) {
    const midpoint = group.from + group.duration / 2;
    const base = ui.exports.creativeTourAt(midpoint);
    const expanded = ui.exports.creativeTourAt(midpoint * (duration + 16) / duration, duration + 16);
    assert.deepEqual(base, expanded);
  }
  for (const length of [1920, 1936, duration, duration + 16, duration * 2]) {
    const end = ui.exports.creativeTourAt(length - 1, length);
    assert.equal(end.group.id, 'pdf');
    assert.ok(end.frame >= 298.8);
    assert.equal(ui.exports.creativeTourAt(length + 100, length).frame, 299);
    assert.match(ui.render(ui.exports.SceneCreativeTools, {duration: length}, length - 1), /Launch brief-protected.pdf/);
  }
});

test('editor controls, export dialogs and completed result rows fit the visible film workspace', () => {
  const ui = load('src/modules/ToolsModule.tsx');
  for (const frame of [250, 335, 435, 530, 610, 685]) {
    const tree = nodes(ui.render(ui.exports.RecordingStudioTour, {frame}));
    const inspector = tree.find((node) => attr(node, 'data-studio-inspector') !== undefined);
    const header = tree.find((node) => styleOf(node).height === '48px' && (attr(node, 'class') ?? '').includes('items-center'));
    const budget = 466 - heightOf(header) - 26;
    const content = inspector.childNodes.reduce((sum, child) => sum + heightOf(child), 0) + 12 * (inspector.childNodes.length - 1);
    assert.ok(content <= budget, `Inspector overflows at ${frame}: ${content} > ${budget}`);
    const dialog = tree.find((node) => attr(node, 'data-recording-export-panel') !== undefined);
    if (dialog) assert.ok(Number.parseFloat(styleOf(dialog).top) + heightOf(dialog) <= 466, `Export dialog overflows at ${frame}`);
  }
  const tools = load('src/modules/CreativeToolsModule.tsx');
  for (const [kind, frame] of [['image', 120], ['image', 230], ['image', 350], ['image', 415], ['audio', 110], ['audio', 210], ['audio', 350], ['pdf', 140], ['pdf', 290]]) {
    const tree = nodes(tools.render(tools.exports.CreativeToolsModule, {kind, frame}));
    const viewport = tree.find((node) => attr(node, 'data-native-workspace-scroll') !== undefined);
    const container = viewport.childNodes[0];
    const children = container.childNodes.filter((node) => !(attr(node, 'class') ?? '').includes('absolute') && styleOf(node).position !== 'absolute');
    const main = tree.find((node) => attr(node, 'data-native-operation-main') !== undefined);
    const budget = 466 - 40 - heightOf(main.childNodes[0]) - 12;
    const translate = Number.parseFloat(styleOf(container).translate?.split(' ')[1] ?? '0');
    const content = children.reduce((sum, node) => sum + heightOf(node), 0) + 12 * (children.length - 1);
    assert.ok(Math.max(content, budget) + translate <= budget + 1, `${kind} content ends below viewport at ${frame}: ${content} + ${translate} > ${budget}`);
    const editor = tree.find((node) => attr(node, 'data-image-editor') !== undefined);
    if (editor) assert.ok(heightOf(editor) <= budget - 22, 'The image editor controls are clipped');
  }
});

test('recording playback advances once and holds the final frame', () => {
  const ui = load('src/modules/ToolsModule.tsx');
  const position = (frame) => {
    const html = ui.render(ui.exports.ScreenRecordingModule, {frame});
    const match = html.replace(/<[^>]+>/g, '').match(/(\d{1,2}):(\d{2}) \/ (\d{1,2}):(\d{2})/);
    assert.ok(match);
    return Number(match[1]) * 60 + Number(match[2]);
  };
  let previous = -1;
  for (let frame = 0; frame <= 20000; frame += 120) {
    const current = position(frame);
    assert.ok(current >= previous, `Playback restarted at frame ${frame}`);
    previous = current;
  }
  assert.equal(previous, ui.exports.toolDemo.recording.duration);
});

test('image and audio configuration stays in the native two-column workspace', () => {
  const ui = load('src/modules/CreativeToolsModule.tsx');
  for (const kind of ['image', 'audio', 'pdf']) {
    const html = ui.render(ui.exports.CreativeToolsModule, {kind, frame: 80});
    assert.doesNotMatch(html, /Output settings/, `${kind} invented a third settings column`);
    if (kind === 'pdf') assert.doesNotMatch(html, /Password|••••/, 'Merge PDFs has no password configuration');
    if (kind === 'audio') assert.doesNotMatch(html, /−16 LUFS|12 dB|Test tone/, 'Trim audio must not show unrelated controls');
  }
});
