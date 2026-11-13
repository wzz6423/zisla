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
const everyday = load('src/modules/tour/EverydayTourModule.tsx');

test('the compact meeting countdown is visible before joining and never lives inside a clipped module', () => {
  const {MeetingTourModule, meetingTourAt} = everyday.exports;
  const before = everyday.render(MeetingTourModule, {frame: 20});
  const countdown = feature(before, 'meetingCountdown');
  assert.ok(countdown);
  assert.equal(textOf(countdown), '00:02');
  assert.ok(all(before).every((node) => !(attr(node, 'style') ?? '').includes('top:-108')));
  assert.equal(meetingTourAt(71).joined, false);
  assert.equal(meetingTourAt(72).joined, true);
  assert.match(textOf(everyday.render(MeetingTourModule, {frame: 75})), /Meeting link opened/);
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
  assert.equal(meetingTourAt(289).noteLinked, false);
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
  assert.equal(briefingTourAt(111).exporting, false);
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
  assert.deepEqual(shelfSelectionAt(21).selection, []);
  assert.deepEqual(shelfSelectionAt(53).selection, [0]);
  assert.deepEqual(shelfSelectionAt(75).selection, [0, 1]);
  assert.match(textOf(ui.render(ShelfSelectionTour, {frame: 108})), /2 items selected.*Images to PDF/);
  assert.doesNotMatch(textOf(ui.render(ShelfSelectionTour, {frame: 150})), /Review images.pdf saved/);
  const final = textOf(ui.render(ShelfSelectionTour, {frame: 239}));
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
