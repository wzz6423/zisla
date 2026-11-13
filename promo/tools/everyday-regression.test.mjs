import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
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
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 9600}), Img: (props) => React.createElement('img', props)} : require(name);
  new Function('require', 'module', 'exports', bundle.outputFiles[0].text)(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props = {}, frame = 0) => {clock.frame = frame; return parseFragment(renderToStaticMarkup(React.createElement(Component, props)));}};
};
const all = (node) => [node, ...(node.childNodes ?? []).flatMap(all)];
const attr = (node, name) => node.attrs?.find((entry) => entry.name === name)?.value;
const textOf = (node) => node.nodeName === '#text' ? node.value : (node.childNodes ?? []).map(textOf).join('');
const feature = (node, id) => all(node).find((entry) => attr(entry, 'data-feature') === id);
const find = (tree, name, value) => all(tree).find((node) => attr(node, name) !== undefined && (value === undefined || attr(node, name) === value));
const style = (node) => Object.fromEntries((attr(node, 'style') ?? '').split(';').filter(Boolean).map((entry) => {const colon = entry.indexOf(':'); return [entry.slice(0, colon), entry.slice(colon + 1)];}));
const cursors = (tree) => all(tree).filter((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26');
const number = (node, property) => Number.parseFloat(style(node)[property] ?? '0');
const tipOf = (node) => ({x: number(node, 'left') + 2, y: number(node, 'top') + 2});
const assertInside = (point, rect, label) => assert.ok(point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height, `${label}: cursor (${point.x}, ${point.y}) misses target ${JSON.stringify(rect)}`);
const everyday = load('src/modules/tour/EverydayTourModule.tsx');
const shelfTour = load('src/modules/tour/ShelfSelectionTour.tsx');

test('the compact meeting countdown is visible before joining and never lives inside a clipped module', () => {
  const {MeetingTourModule, meetingTourAt} = everyday.exports;
  const before = everyday.render(MeetingTourModule, {frame: 20});
  const countdown = feature(before, 'meetingCountdown');
  assert.ok(countdown);
  assert.equal(textOf(countdown), '00:02');
  assert.ok(all(before).every((node) => !(attr(node, 'style') ?? '').includes('top:-108')));
  assert.equal(meetingTourAt(77).joined, false);
  assert.equal(meetingTourAt(78).joined, true);
  assert.match(textOf(everyday.render(MeetingTourModule, {frame: 79})), /Meeting link opened/);
  assert.equal(feature(everyday.render(MeetingTourModule, {frame: 100}), 'meetingCountdown'), undefined);
});

test('new meeting notes save once, return to Agenda and link an existing note from the event menu', () => {
  const {MeetingTourModule, meetingTourAt} = everyday.exports;
  const drafting = everyday.render(MeetingTourModule, {frame: 178});
  assert.ok(feature(drafting, 'contextNote.detail'));
  assert.match(textOf(drafting), /1\. Review the island layout\.\n2\. Confirm the launch date\./);
  assert.doesNotMatch(textOf(drafting), /Meeting note saved/);
  const saved = everyday.render(MeetingTourModule, {frame: 207});
  assert.equal(feature(saved, 'contextNote.detail'), undefined, 'Saving closes the native detail editor');
  assert.match(textOf(saved), /Meeting note saved.*Linked to Design review/);
  const menu = everyday.render(MeetingTourModule, {frame: 262});
  assert.match(textOf(menu), /Calendar and reminders.*Link existing note.*Review checklist/);
  assert.equal(feature(menu, 'meetingNotes'), undefined, 'The linking menu belongs to Agenda');
  assert.equal(meetingTourAt(295).noteLinked, false);
  assert.match(textOf(everyday.render(MeetingTourModule, {frame: 359})), /Existing note linked.*Open from Calendar/);
});

test('location-note text, screenshot and recurring reminder retain the same saved object', () => {
  const {ContextNotesTourModule, everydayDemo} = everyday.exports;
  const before = everyday.render(ContextNotesTourModule, {frame: 10});
  assert.ok(feature(before, 'contextNote.detail'));
  assert.doesNotMatch(textOf(before), /Saved.*Shown when you return/);
  const saved = everyday.render(ContextNotesTourModule, {frame: 190});
  for (const text of [everydayDemo.context.text, everydayDemo.context.location, 'Every 3 hours', 'Window screenshot', 'Copy screenshot', 'Saved · Shown when you return']) assert.ok(textOf(saved).includes(text), text);
  assert.equal(attr(feature(saved, 'contextNote.screenshot'), 'aria-label'), 'View screenshot');
  const scrollingBody = (tree) => all(tree).find((node) => attr(node, 'data-note-scroll') !== undefined);
  const offset = (tree) => attr(scrollingBody(tree).childNodes.find((node) => node.tagName === 'div'), 'style');
  assert.equal(offset(everyday.render(ContextNotesTourModule, {frame: 110})), 'transform:translateY(0px)');
  assert.equal(offset(saved), 'transform:translateY(-132px)', 'The screenshot must enter the detail viewport after saving');
  assert.ok(!all(scrollingBody(saved)).some((node) => attr(node, 'data-note-save') !== undefined), 'Save stays outside the scrolling body');
});

test('briefing previews in a separate window and holds the exported PNG for readable film time', () => {
  const {BriefingTourModule, briefingTourAt} = everyday.exports;
  const settings = everyday.render(BriefingTourModule, {frame: 50});
  assert.ok(feature(settings, 'briefing.settings'));
  for (const template of everyday.exports.briefingTemplates) assert.ok(textOf(settings).includes(template.title));
  assert.doesNotMatch(textOf(settings), /Daily briefing · Coastal|Saved:/);
  const preview = everyday.render(BriefingTourModule, {frame: 90});
  assert.match(textOf(preview), /Daily briefing · Coastal/);
  assert.equal(briefingTourAt(117).exporting, false);
  assert.match(textOf(everyday.render(BriefingTourModule, {frame: 128})), /Exporting PNG/);
  assert.match(textOf(everyday.render(BriefingTourModule, {frame: 190})), /Saved: Daily briefing/);
  const scene = load('src/scenes/SceneEveryday.tsx');
  const duration = 1456;
  let visible = 0;
  for (let frame = 0; frame < duration; frame++) {
    const state = scene.exports.everydayTourAt(frame, duration);
    if (state.step.id === 'briefing' && briefingTourAt(state.frame).saved) visible++;
  }
  assert.ok(visible >= 75, `PNG result is unreadable: ${visible} frames`);
});

test('dashboard summaries count tasks per app and retain a single task progress only for one task', () => {
  const home = load('src/modules/HomeModule.tsx');
  const tasks = load('src/content.ts').exports.aiTasks;
  const tree = home.render(home.exports.HomeModule, {cards: ['ai'], tasks, aiProgress: .74});
  const summaries = all(tree).filter((node) => attr(node, 'data-feature') === 'ai.applicationSummary');
  assert.equal(summaries.length, 3);
  assert.deepEqual(summaries.map((node) => attr(node, 'data-provider')), ['claude', 'codex', 'gemini']);
  for (const row of summaries) assert.equal(attr(row, 'data-task-count'), '1');
  assert.doesNotMatch(textOf(tree), /3 running/);
  const grouped = home.render(home.exports.HomeModule, {cards: ['ai'], tasks: [tasks[0], {...tasks[0], id: 'another'}], aiProgress: .74});
  assert.match(textOf(grouped), /CLAUDE2 running/);
  assert.doesNotMatch(textOf(grouped), /74%/);
  assert.equal(all(home.render(home.exports.HomeModule, {cards: ['ai'], tasks: []})).filter((node) => attr(node, 'data-feature') === 'ai.applicationSummary').length, 0);
});

test('shelf counts derive from the displayed set, including notes and empty categories', () => {
  const shelf = load('src/modules/ShelfModule.tsx');
  const files = [{name: 'Cover.png', kind: 'image', tint: '#aaa'}, {name: 'Table.png', kind: 'image', tint: '#aaa'}, {name: 'Walkthrough.mp4', kind: 'video', tint: '#aaa'}];
  assert.deepEqual(shelf.exports.shelfCategoryCounts(files), [3, 0, 0, 0, 2, 0, 1, 0, 0, 0, 0, 0, 0]);
  assert.deepEqual(shelf.exports.shelfCategoryCounts([]), Array(13).fill(0));
  assert.equal(shelf.exports.shelfCategoryCounts([{name: 'Review note', kind: 'note', tint: '#aaa'}])[1], 1);
  const tree = shelf.render(shelf.exports.ShelfModule, {items: files, enter: 3});
  assert.match(textOf(tree), /Shelf3/);
  assert.doesNotMatch(textOf(tree), /All8|Notes1|Folder1/);
});

test('shelf multi-selection executes one image conversion and keeps the original files and final output', () => {
  const ui = load('src/modules/tour/ShelfSelectionTour.tsx');
  const {ShelfSelectionTour, shelfSelectionAt} = ui.exports;
  assert.equal(shelfSelectionAt(0).selection, undefined);
  assert.deepEqual(shelfSelectionAt(26).selection, []);
  assert.deepEqual(shelfSelectionAt(58).selection, [0]);
  assert.deepEqual(shelfSelectionAt(80).selection, [0, 1]);
  assert.match(textOf(ui.render(ShelfSelectionTour, {frame: 108})), /2 items selected.*Images to PDF/);
  assert.doesNotMatch(textOf(ui.render(ShelfSelectionTour, {frame: 150})), /Review images.pdf saved/);
  const done = ui.render(ShelfSelectionTour, {frame: 239});
  const final = textOf(done);
  const result = find(done, 'data-shelf-conversion-result');
  assert.ok(result, 'The conversion result must belong to a visible outcome surface');
  assert.match(textOf(result), /Review images.pdf saved.*Original files retained/);
  assert.match(final, /Review images.pdf saved/);
  assert.match(final, /Cover.png.*Review table.png.*Original files retained/);
  assert.equal(shelfSelectionAt(239).processing, false);
});

test('voice records in the compact surface and inserts the cleaned text only after release and cleanup', () => {
  const {VoiceTourModule, voiceTourAt, everydayDemo} = everyday.exports;
  const settings = everyday.render(VoiceTourModule, {frame: 30, globalFrame: 0});
  assert.ok(feature(settings, 'voice.settings'));
  assert.equal(feature(settings, 'voice.insertion'), undefined);
  const recording = everyday.render(VoiceTourModule, {frame: 120, globalFrame: 90});
  assert.equal(feature(recording, 'voice.settings'), undefined);
  assert.ok(feature(recording, 'voice.recording'));
  assert.ok(textOf(feature(recording, 'voice.transcript')).length > 10);
  assert.doesNotMatch(textOf(feature(recording, 'voice.insertion')), /1\. Update/);
  assert.equal(voiceTourAt(153).recording, true);
  assert.equal(voiceTourAt(154).cleaning, true);
  assert.equal(voiceTourAt(204).done, false);
  const done = everyday.render(VoiceTourModule, {frame: 260, globalFrame: 230});
  assert.equal(feature(done, 'voice.recording'), undefined);
  assert.equal(textOf(feature(done, 'voice.insertion')), everydayDemo.voice.cleaned);
  assert.match(textOf(done), /Cleaned transcript inserted/);
});

test('each Everyday and Shelf demonstration has one cursor throughout the scene and at fractional boundaries', () => {
  for (const [ui, name, duration] of [
    [everyday, 'NotesTourModule', 180], [everyday, 'ClipboardTourModule', 180], [everyday, 'AgendaTourModule', 180],
    [everyday, 'MeetingTourModule', 360], [everyday, 'ContextNotesTourModule', 240], [everyday, 'BriefingTourModule', 240],
    [shelfTour, 'ShelfSelectionTour', 240],
  ]) {
    for (let frame = 0; frame < duration; frame++) {
      const tree = ui.render(ui.exports[name], {frame});
      assert.equal(cursors(tree).length, 1, `${name} frame ${frame} duplicates or drops the scene cursor`);
    }
  }
  for (const frame of [71.5, 77.5, 79.5, 85.5, 91.5, 123.5, 129.5, 198.5, 204.5, 224.5, 246.5, 252.5, 289.5, 295.5]) {
    assert.equal(cursors(everyday.render(everyday.exports.MeetingTourModule, {frame})).length, 1, `Meeting handoff frame ${frame}`);
  }
});

test('six pressed frames land on the measured visible target instead of only staying inside the canvas', () => {
  // Target rectangles were measured from the browser's rendered 1280 × 720 stage.
  const actions = [
    {ui: everyday, name: 'NotesTourModule', at: 65, marker: 'data-note-check', value: 'Privacy copy reviewed by the docs pass', origin: [264, 141], rect: {x: 454, y: 368.609, width: 13, height: 13}},
    {ui: everyday, name: 'ClipboardTourModule', at: 36, marker: 'data-clipboard-kind', value: 'Code', origin: [264, 141], rect: {x: 545.77, y: 204, width: 65.22, height: 20}},
    {ui: everyday, name: 'ClipboardTourModule', at: 85, marker: 'data-clipboard-search', origin: [264, 141], rect: {x: 265, y: 228, width: 750, height: 28}},
    {ui: everyday, name: 'ClipboardTourModule', at: 124, marker: 'data-clipboard-row', value: 'brew install --cask wzz6423/tap/zisla', origin: [264, 141], rect: {x: 273, y: 264, width: 734, height: 38}},
    {ui: everyday, name: 'AgendaTourModule', at: 54, marker: 'data-reminder-toggle', value: 'Ship the launch film', origin: [264, 141], rect: {x: 988, y: 272.5, width: 11, height: 11}},
    {ui: everyday, name: 'MeetingTourModule', at: 72, marker: 'data-feature', value: 'meetingCountdown', origin: [0, 0], rect: {x: 735, y: 0, width: 112, height: 34}},
    {ui: everyday, name: 'MeetingTourModule', at: 86, marker: 'data-meeting-note-action', origin: [0, 0], rect: {x: 988, y: 204.5, width: 11, height: 11}},
    {ui: everyday, name: 'MeetingTourModule', at: 124, marker: 'data-meeting-note-option', value: 'new', origin: [0, 0], rect: {x: 758, y: 223, width: 230, height: 24}},
    {ui: everyday, name: 'MeetingTourModule', at: 199, marker: 'data-note-save', origin: [0, 0], rect: {x: 961.898, y: 243.5, width: 23.1, height: 15}},
    {ui: everyday, name: 'MeetingTourModule', at: 247, marker: 'data-meeting-note-action', origin: [0, 0], rect: {x: 988, y: 204.5, width: 11, height: 11}},
    {ui: everyday, name: 'MeetingTourModule', at: 290, marker: 'data-meeting-note-option', value: 'link', origin: [0, 0], rect: {x: 758, y: 247, width: 230, height: 24}},
    {ui: everyday, name: 'ContextNotesTourModule', at: 109, marker: 'data-note-save', origin: [264, 141], rect: {x: 961.898, y: 243.5, width: 23.1, height: 15}},
    {ui: everyday, name: 'BriefingTourModule', at: 38, marker: 'data-template', value: 'coastal', origin: [0, 0], rect: {x: 148, y: 476, width: 162.5, height: 67}},
    {ui: everyday, name: 'BriefingTourModule', at: 75, marker: 'data-briefing-action', value: 'preview', origin: [0, 0], rect: {x: 148, y: 556, width: 76.09, height: 34}},
    {ui: everyday, name: 'BriefingTourModule', at: 112, marker: 'data-briefing-action', value: 'export', origin: [0, 0], rect: {x: 669.703, y: 556, width: 152.3, height: 34}},
    {ui: shelfTour, name: 'ShelfSelectionTour', at: 20, marker: 'data-shelf-select', origin: [264, 141], rect: {x: 684.24, y: 146.5, width: 56.07, height: 21}},
    {ui: shelfTour, name: 'ShelfSelectionTour', at: 52, marker: 'data-shelf-item', value: 'Cover.png', origin: [264, 141], rect: {x: 359, y: 267, width: 66, height: 84}},
    {ui: shelfTour, name: 'ShelfSelectionTour', at: 74, marker: 'data-shelf-item', value: 'Review table.png', origin: [264, 141], rect: {x: 433, y: 267, width: 66, height: 84}},
    {ui: shelfTour, name: 'ShelfSelectionTour', at: 92, marker: 'data-shelf-actions', origin: [264, 141], rect: {x: 960, y: 239, width: 45, height: 15}},
    {ui: shelfTour, name: 'ShelfSelectionTour', at: 128, marker: 'data-shelf-media-action', value: 'imagesToPDF', origin: [264, 141], rect: {x: 775, y: 290, width: 216, height: 27}},
  ];
  for (const action of actions) {
    const label = `${action.name} at ${action.at}`;
    const preceding = actions.filter((item) => item.name === action.name && item.at < action.at).at(-1);
    if (preceding) assert.ok(action.at - preceding.at >= 7, `${label}: actions overlap their pressed frames`);
    for (const delta of [-0.5, 0, 0.5, 1, 2, 3, 4, 5, 5.5, 6]) {
      const tree = action.ui.render(action.ui.exports[action.name], {frame: action.at + delta});
      const pointer = cursors(tree);
      assert.equal(pointer.length, 1, label);
      assert.equal(style(pointer[0]).transform, delta >= 0 && delta < 6 ? 'scale(0.9)' : 'scale(1)', `${label}, delta ${delta}: pressed duration changed`);
      if (delta < 0 || delta >= 6) continue;
      const target = find(tree, action.marker, action.value);
      assert.ok(target, `${label}, delta ${delta}: target vanished before release`);
      assert.ok(number(pointer[0], 'opacity') > 0, `${label}: pressed cursor is invisible`);
      const point = tipOf(pointer[0]);
      assertInside({x: point.x + action.origin[0], y: point.y + action.origin[1]}, action.rect, `${label}, delta ${delta}`);
      let parent = target;
      while (parent) {assert.notEqual(style(parent).display, 'none', `${label}: hidden target`); assert.notEqual(style(parent).opacity, '0', `${label}: transparent target`); parent = parent.parentNode;}
    }
  }
});

test('one Notes click completes only its targeted checkbox after release and keeps the other rows unchanged', () => {
  const keys = ['Island reveal measured at 60 fps on macOS 14', 'Zero frame loop while the island is hidden', 'Privacy copy reviewed by the docs pass', 'Homebrew cask updated to the new build'];
  const checked = (tree) => keys.map((key) => style(find(tree, 'data-note-check', key)).background === '#0A84FF');
  for (const frame of [0, 40, 64, 65, 70.5]) assert.deepEqual(checked(everyday.render(everyday.exports.NotesTourModule, {frame})), [true, true, false, false]);
  for (const frame of [71, 100, 179]) assert.deepEqual(checked(everyday.render(everyday.exports.NotesTourModule, {frame})), [true, true, true, false]);
});

test('Clipboard filtering and search change after release and copy retains the exact selected row', () => {
  const rowNames = (tree) => all(tree).filter((node) => attr(node, 'data-clipboard-row')).map((node) => attr(node, 'data-clipboard-row'));
  const before = rowNames(everyday.render(everyday.exports.ClipboardTourModule, {frame: 41.5}));
  const code = rowNames(everyday.render(everyday.exports.ClipboardTourModule, {frame: 42}));
  assert.equal(before.length, 12);
  assert.equal(code.length, 6);
  assert.ok(textOf(find(everyday.render(everyday.exports.ClipboardTourModule, {frame: 90.5}), 'data-clipboard-search')).includes('Search'));
  for (const frame of [91, 124, 129.5, 179]) assert.deepEqual(rowNames(everyday.render(everyday.exports.ClipboardTourModule, {frame})), ['brew install --cask wzz6423/tap/zisla']);
  assert.doesNotMatch(textOf(everyday.render(everyday.exports.ClipboardTourModule, {frame: 129.5})), /Copied to clipboard/);
  assert.match(textOf(everyday.render(everyday.exports.ClipboardTourModule, {frame: 130})), /Copied to clipboard/);
});

test('Agenda changes the clicked reminder after release and retains the completion control', () => {
  for (const frame of [54, 55, 56, 57, 58, 59.5]) {
    const tree = everyday.render(everyday.exports.AgendaTourModule, {frame});
    const row = find(tree, 'data-agenda-row', 'Ship the launch film');
    const body = row.childNodes.find((node) => attr(node, 'class')?.includes('min-w-0'));
    assert.equal(style(body).opacity, '1', `Reminder starts completing before release at ${frame}`);
    assert.equal(attr(find(row, 'data-reminder-toggle'), 'class').includes('lucide-circle-check'), false);
  }
  const done = everyday.render(everyday.exports.AgendaTourModule, {frame: 88});
  assert.ok(attr(find(done, 'data-reminder-toggle', 'Ship the launch film'), 'class').includes('lucide-circle-check'));
  assert.match(textOf(done), /Reminder completed/);
});

test('meeting and Shelf menus and Save stay mounted through release with one result transition', () => {
  const meeting = everyday.exports.meetingTourAt;
  for (const frame of [86, 91.5, 247, 252.5]) assert.equal(meeting(frame).menu, false);
  assert.equal(meeting(92).menu, true);
  for (const frame of [124, 129.5]) {assert.equal(meeting(frame).menu, true); assert.equal(meeting(frame).noteOpen, false);}
  assert.equal(meeting(130).noteOpen, true);
  for (const frame of [199, 204.5]) {
    const tree = everyday.render(everyday.exports.MeetingTourModule, {frame});
    assert.ok(find(tree, 'data-note-save'));
    assert.doesNotMatch(textOf(tree), /Meeting note saved/);
  }
  assert.equal(find(everyday.render(everyday.exports.MeetingTourModule, {frame: 205}), 'data-note-save'), undefined);
  for (const frame of [290, 295.5]) {assert.equal(meeting(frame).menu, true); assert.equal(meeting(frame).noteLinked, false);}
  assert.equal(meeting(296).noteLinked, true);
  const selection = shelfTour.exports.shelfSelectionAt;
  for (const frame of [20, 25.5]) assert.equal(selection(frame).selection, undefined);
  for (const frame of [52, 57.5]) assert.deepEqual(selection(frame).selection, []);
  for (const frame of [74, 79.5]) assert.deepEqual(selection(frame).selection, [0]);
  for (const frame of [92, 97.5]) assert.equal(selection(frame).menu, false);
  assert.equal(selection(98).menu, true);
  assert.equal(attr(find(shelfTour.render(shelfTour.exports.ShelfSelectionTour, {frame: 108}), 'data-shelf-selection-menu'), 'role'), 'menu');
  assert.equal(attr(find(shelfTour.render(shelfTour.exports.ShelfSelectionTour, {frame: 128}), 'data-shelf-media-action'), 'role'), 'menuitem');
  for (const frame of [128, 133.5]) {assert.equal(selection(frame).menu, true); assert.equal(selection(frame).processing, false);}
  assert.equal(selection(134).processing, true);
  assert.equal(selection(169.5).completed, false);
  assert.equal(selection(170).completed, true);
  let completions = 0;
  for (let frame = 1; frame < 240; frame++) if (!selection(frame - 1).completed && selection(frame).completed) completions++;
  assert.equal(completions, 1);
});

test('Briefing keeps the selected template, preview and export causal through the six-frame click', () => {
  const at = everyday.exports.briefingTourAt;
  assert.equal(at(43.5).selected, 0);
  assert.equal(at(44).selected, 4);
  assert.equal(at(80.5).preview, false);
  assert.equal(at(81).preview, true);
  assert.equal(at(117.5).exporting, false);
  assert.equal(at(118).exporting, true);
  assert.equal(at(143.5).saved, false);
  assert.equal(at(144).saved, true);
  for (const frame of [81, 112, 117.5, 190]) assert.equal(at(frame).selected, 4);
  const drafting = everyday.render(everyday.exports.ContextNotesTourModule, {frame: 114.5});
  const saved = everyday.render(everyday.exports.ContextNotesTourModule, {frame: 115});
  assert.doesNotMatch(textOf(drafting), /Saved · Shown when you return/);
  assert.match(textOf(feature(drafting, 'contextNote.detail')), /│/);
  assert.match(textOf(saved), /Saved · Shown when you return/);
  assert.doesNotMatch(textOf(feature(saved, 'contextNote.detail')), /│/);
});

test('meeting and file outcomes retain at least 42 actual frames in the existing 1440-frame Everyday budget', () => {
  const scenes = load('src/scenes/SceneEveryday.tsx');
  const counts = {notes: 0, clipboard: 0, reminder: 0, joined: 0, saved: 0, linked: 0, context: 0, briefing: 0, voice: 0};
  for (let frame = 0; frame < 1456; frame++) {
    const state = scenes.exports.everydayTourAt(frame, 1456);
    const local = state.frame;
    if (state.step.id === 'notes' && local >= 118) counts.notes++;
    if (state.step.id === 'clipboard' && local >= 130) counts.clipboard++;
    if (state.step.id === 'agenda' && local >= 88) counts.reminder++;
    if (state.step.id === 'meeting') {
      const meeting = everyday.exports.meetingTourAt(local);
      if (meeting.joined && local < 130 && textOf(everyday.render(everyday.exports.MeetingTourModule, {frame: local})).includes('Meeting link opened')) counts.joined++;
      if (meeting.noteSaved && !meeting.menu && !meeting.noteLinked) counts.saved++;
      if (meeting.noteLinked) counts.linked++;
    }
    if (state.step.id === 'context' && local >= 115) counts.context++;
    if (state.step.id === 'briefing' && everyday.exports.briefingTourAt(local).saved) counts.briefing++;
    if (state.step.id === 'voice' && everyday.exports.voiceTourAt(local).done) counts.voice++;
  }
  for (const [name, frames] of Object.entries(counts)) assert.ok(frames >= 42, `${name} result lasts only ${frames} actual frames`);
  assert.ok(Array.from({length: 240}, (_, frame) => shelfTour.exports.shelfSelectionAt(frame)).filter((state) => state.completed).length >= 42);
});
