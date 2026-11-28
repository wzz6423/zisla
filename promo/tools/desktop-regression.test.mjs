import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
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
const load = (entryPoint, mutate) => {
  const clock = {frame: 0};
  const bundle = buildSync({absWorkingDir: root, entryPoints: [entryPoint], bundle: true, packages: 'external', platform: 'node', format: 'cjs', jsx: 'automatic', write: false, loader: {'.svg': 'dataurl', '.png': 'dataurl'}});
  const module = {exports: {}};
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 7200}), Img: (props) => React.createElement('img', props)} : require(name);
  const source = bundle.outputFiles[0].text;
  new Function('require', 'module', 'exports', mutate ? mutate(source) : source)(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props = {}, frame = 0) => {clock.frame = frame; return renderToStaticMarkup(React.createElement(Component, props));}};
};
const walk = (node) => [node, ...(node.childNodes ?? []).flatMap(walk)];
const attr = (node, name) => node?.attrs?.find((item) => item.name === name)?.value;
const nodes = (html) => walk(parseFragment(html));
const find = (html, name, value) => nodes(html).find((node) => attr(node, name) !== undefined && (value === undefined || attr(node, name) === value));
const content = (node) => walk(node).filter((item) => item.nodeName === '#text').map((item) => item.value).join('');
const textOf = (html) => content(parseFragment(html));
const style = (node) => Object.fromEntries((attr(node, 'style') ?? '').split(';').filter(Boolean).map((item) => {const colon = item.indexOf(':'); return [item.slice(0, colon), item.slice(colon + 1)];}));
const number = (node, name) => Number.parseFloat(style(node)[name] ?? '0');

const modules = load('src/modules/tour/DesktopTourModule.tsx');
const scenes = load('src/scenes/SceneDesktopTools.tsx');

const visibleCursors = (html) => nodes(html).filter((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26' && walk(node).some((child) => attr(child, 'd') === 'M2 2 L2 20.4 L6.5 16.3 L9.5 23.5 L12.6 22.2 L9.7 15.2 L15.9 15.2 Z')).filter((node) => {
  let opacity = 1;
  for (let current = node; current; current = current.parentNode) opacity *= Number(style(current).opacity ?? 1);
  return opacity > 0;
});

test('keyboard sound selection is a Settings page followed by a separate scrolling Island dashboard with voice stats', () => {
  const ui = modules;
  const before = ui.render(ui.exports.KeyboardTourModule, {frame: 0});
  assert.ok(find(before, 'data-keyboard-settings'), 'Keyboard sound controls must live in Settings');
  assert.equal(find(before, 'data-keyboard-dashboard'), undefined);
  assert.match(textOf(before), /Holy Panda/);
  assert.doesNotMatch(textOf(before), /12,846|Heatmap|App timeline/);
  const choices = ui.render(ui.exports.KeyboardTourModule, {frame: 14});
  const menu = find(choices, 'data-keyboard-profile-menu');
  assert.ok(menu, 'The native sound picker never opens');
  const native = readFileSync(new URL('../../mac/Sources/KeyboardKit/SwitchProfile.swift', import.meta.url), 'utf8');
  const expected = [...native.matchAll(/case \.\w+: "([^"]+)"/g)].slice(0, 20).map((match) => match[1]);
  assert.equal(expected.length, 20);
  for (const voice of expected) assert.ok(content(menu).includes(voice), voice);
  assert.match(content(menu), /BCP \(Suit80\)/);
  assert.doesNotMatch(textOf(choices), /Import|Add pack/);
  assert.match(textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 38})), /BCP \(Suit80\)/);
  for (const frame of [54, 72, 108, 134]) {
    const html = ui.render(ui.exports.KeyboardTourModule, {frame});
    assert.ok(find(html, 'data-keyboard-dashboard'));
    assert.equal(find(html, 'data-keyboard-settings'), undefined);
    assert.doesNotMatch(textOf(html), /Global sounds|Release sounds|Pitch variation|Preview/);
  }
  const stats = ui.render(ui.exports.KeyboardTourModule, {frame: 54});
  for (const label of ['Characters Today', 'Top app', 'Peak Today', 'Active time', 'Typing trend', 'History', 'Keyboard', 'Voice dictation', 'App timeline']) assert.ok(textOf(stats).includes(label), label);
  const cards = nodes(stats).filter((node) => attr(node, 'data-typing-metric') !== undefined);
  assert.equal(cards.length, 4);
  for (const card of cards) assert.equal(number(card, 'height'), 76);
  const viewport = find(stats, 'data-keyboard-scroll');
  assert.equal(style(viewport).overflow, 'hidden');
  const final = ui.render(ui.exports.KeyboardTourModule, {frame: 134});
  const scroll = find(final, 'data-keyboard-scroll-content');
  assert.ok(style(scroll).transform.includes('translateY(-'));
  const timeline = find(final, 'data-keyboard-timeline');
  const scrollY = Number(style(scroll).transform.match(/translateY\((-?[\d.]+)px\)/)?.[1]);
  assert.ok(Number(attr(timeline, 'data-content-y')) + scrollY + number(timeline, 'height') <= number(viewport, 'height'));
  const scene = scenes.render(scenes.exports.SceneDesktopTools, {}, 110 + 70);
  assert.ok(find(scene, 'data-keyboard-dashboard'));
  const island = nodes(scene).find((node) => number(node, 'width') === 776 && number(node, 'top') === 0 && style(node).overflow === 'hidden');
  assert.ok(island, 'The keyboard dashboard is still an external tour card');
});

test('typing increments only from the demonstrated key presses and keeps all 14 characters', () => {
  const at = modules.exports.keyboardTourAt;
  let previous = 12846;
  for (let frame = 0; frame < 135; frame++) {
    const state = at(frame);
    assert.ok(state.characters >= previous && state.characters <= 12860);
    assert.ok(state.characters - previous <= 1);
    if (frame < 62) assert.equal(state.characters, 12846);
    if (frame >= 88) assert.equal(state.characters, 12860);
    previous = state.characters;
  }
  assert.deepEqual(at(-10), at(0));
  assert.deepEqual(at(300), at(134));
  assert.match(textOf(modules.render(modules.exports.KeyboardTourModule, {frame: 54})), /12,846/);
  assert.match(textOf(modules.render(modules.exports.KeyboardTourModule, {frame: 100})), /12,860/);
  const done = scenes.render(scenes.exports.SceneDesktopTools, {}, 110 + 120);
  assert.match(textOf(done), /14 characters added/);
});

test('focus includes independent named countdown timers, 4-button bottom row with Clean Junk, and rest transition', () => {
  const at = modules.exports.focusTourAt;
  assert.deepEqual(at(-5), at(0));
  assert.equal(at(0).phase, 'idle');
  assert.equal(at(24).phase, 'running');
  const frozen = at(66).remaining;
  assert.ok(frozen > 1 && frozen < 2);
  for (let frame = 66; frame < 90; frame++) {
    assert.equal(at(frame).phase, 'paused');
    assert.equal(at(frame).remaining, frozen);
  }
  assert.equal(at(90).remaining, frozen);
  for (let frame = 91; frame < 128; frame++) assert.ok(at(frame).remaining < at(frame - 1).remaining);
  for (let frame = 128; frame < 170; frame++) {
    assert.equal(at(frame).phase, 'idle');
    assert.equal(at(frame).mode, 'rest');
    assert.equal(at(frame).remaining, 300);
  }
  assert.equal(at(128).completed, true);
  assert.equal(at(159).completed, false);
  assert.deepEqual(at(600), at(169));
  const rendered = modules.render(modules.exports.FocusTourModule, {frame: 140});
  assert.match(textOf(rendered), /Rest5:00⌄StartReset/);
  assert.ok(find(rendered, 'data-toolbox-named-timer', 'Tea'), 'Independent named countdown timer is present');
  assert.ok(find(rendered, 'data-toolbox-add-timer'), 'Inset Add timer button is present');
  assert.ok(find(rendered, 'data-toolbox-actions', '2/2/4'), 'Bottom row has 4 shortcuts');
  const shortcuts = nodes(rendered).filter((node) => attr(node, 'data-toolbox-shortcut')).map((node) => attr(node, 'data-toolbox-shortcut'));
  assert.deepEqual(shortcuts.slice(-4), ['Teleprompter', 'Mirror', 'Clean Junk', 'Trash']);
  let starts = 0;
  for (let frame = 1; frame < 170; frame++) if (at(frame).phase === 'running' && at(frame - 1).phase === 'idle') starts++;
  assert.equal(starts, 1);
});

test('focus compact pause continue and reset controls stay visible with smooth spring collapse and status outside clipping', () => {
  const ui = scenes;
  for (const [local, label] of [[60, 'Pause'], [75, 'Continue'], [105, 'Pause']]) {
    const html = ui.render(ui.exports.SceneDesktopTools, {}, 245 + local);
    const controls = find(html, 'data-compact-focus-controls');
    assert.ok(controls);
    const toggle = walk(controls).find((node) => attr(node, 'data-control') === 'pomodoro.toggleStartPause');
    const reset = walk(controls).find((node) => attr(node, 'data-control') === 'pomodoro.reset');
    assert.equal(attr(toggle, 'aria-label'), label);
    assert.equal(attr(reset, 'aria-label'), 'Reset');
    assert.equal(number(controls, 'height'), 24);
    assert.ok(number(toggle, 'height') <= 24 && number(reset, 'height') <= 24);
    assert.equal(find(html, 'data-feature', 'toolbox'), undefined, 'The compact controls cannot coexist with expanded toolbox content');
    const status = find(html, 'data-focus-status');
    let current = status?.parentNode;
    while (current) {assert.notEqual(style(current).overflow, 'hidden', 'Focus status is trapped in a clipped ancestor'); current = current.parentNode;}
    assert.ok(number(status, 'top') > 34 && number(status, 'top') < 600);
  }
  const done = ui.render(ui.exports.SceneDesktopTools, {}, 245 + 140);
  assert.match(textOf(done), /Focus completed|5:00/);
  assert.equal(find(done, 'data-compact-focus-controls'), undefined, 'The completed idle timer must reopen the toolbox');
  const reset = ui.render(ui.exports.SceneDesktopTools, {}, 245 + 169);
  assert.match(textOf(reset), /Rest5:00⌄StartReset/);
  for (const local of [66, 90]) {
    const tree = nodes(ui.render(ui.exports.SceneDesktopTools, {}, 245 + local));
    const cursor = tree.find((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26' && number(node, 'opacity') > 0);
    assert.ok(cursor);
    assert.ok(number(cursor, 'left') >= 749 && number(cursor, 'left') <= 773);
    assert.ok(number(cursor, 'top') >= 3 && number(cursor, 'top') <= 27);
  }
});

test('system history transitions from readable live metrics to the 720 by 560 window and scrolls six categories', () => {
  const ui = modules;
  const at = ui.exports.systemHistoryTourAt;
  const live = ui.render(ui.exports.SystemHistoryTourModule, {frame: 18, globalFrame: 8000});
  assert.equal(find(live, 'data-system-history-window'), undefined);
  assert.match(textOf(live), /Real-time performance/);
  const html = ui.render(ui.exports.SystemHistoryTourModule, {frame: 54, globalFrame: 8054});
  const window = find(html, 'data-system-history-window');
  assert.ok(window);
  assert.equal(number(window, 'width'), 720);
  assert.equal(number(window, 'height'), 560);
  assert.doesNotMatch(textOf(html), /Real-time performance/);
  for (const label of ['System history', 'Clear', 'Export', '24 hours', '7 days', '30 days', 'All']) assert.ok(textOf(html).includes(label), label);
  const viewport = find(html, 'data-system-history-scroll');
  const list = find(html, 'data-system-history-scroll-content');
  assert.equal(style(viewport).overflow, 'hidden');
  assert.ok((attr(list, 'class') ?? '').includes('flex-col'));
  const rows = walk(list).filter((node) => attr(node, 'data-history-category'));
  assert.deepEqual(rows.map((node) => attr(node, 'data-history-category')), ['CPU', 'GPU', 'Memory', 'Disk', 'Fan', 'Network']);
  for (const row of rows) {
    assert.equal(number(row, 'height'), 178);
    const header = row.childNodes.find((node) => node.tagName === 'div');
    const chart = row.childNodes.find((node) => node.tagName === 'svg');
    assert.ok(24 + number(header, 'height') + number(header, 'margin-bottom') + Number(attr(chart, 'height')) + 2 <= number(row, 'height'));
  }
  const footer = find(html, 'data-system-history-footer');
  assert.ok(footer && !walk(viewport).includes(footer), 'The history footer scrolls away with the charts');
  const seen = new Set();
  for (let frame = 36; frame < 96; frame++) {
    const state = at(frame);
    for (let index = 0; index < rows.length; index++) {
      const y = index * 190 - state.scroll;
      if (y >= 0 && y + 178 <= 404) seen.add(attr(rows[index], 'data-history-category'));
    }
    if (frame > 36) assert.ok(state.scroll >= at(frame - 1).scroll);
  }
  assert.equal(seen.size, 6, 'Some history categories never become fully visible');
  assert.equal(at(50).scroll, 0);
  assert.equal(at(70).scroll, 380);
  assert.equal(at(90).scroll, 724);
  assert.doesNotMatch(textOf(ui.render(ui.exports.SystemHistoryTourModule, {frame: 80, globalFrame: 8080})), /Saved:/);
  assert.ok(find(ui.render(ui.exports.SystemHistoryTourModule, {frame: 100, globalFrame: 8100}), 'data-system-history-save'));
  const final = ui.render(ui.exports.SystemHistoryTourModule, {frame: 149, globalFrame: 8149});
  assert.equal(find(final, 'data-system-history-save'), undefined);
  assert.match(textOf(final), /Saved: System history.xlsx/);
  assert.ok(number(find(final, 'data-system-history-footer'), 'height') === 16);
});

test('battery smoothly eases power-flow height and preserves power balance across adapter and battery states', () => {
  const ui = modules;
  const at = ui.exports.batteryTourAt;
  for (const frame of [0, 18, 28, 42, 57]) {
    const state = at(frame);
    assert.equal(state.level, 0.76, 'The charge request must not fill the battery instantly');
    assert.equal(state.inputWatts, state.chargingWatts + state.systemWatts);
    const html = ui.render(ui.exports.BatteryTourModule, {frame});
    assert.match(textOf(html), /76%/);
    assert.doesNotMatch(textOf(html), /Fully charged/);
  }
  // Verify smooth eased transition instead of a 1-frame 80px jump.
  assert.equal(at(23).flowHeight, 96);
  assert.ok(at(29).flowHeight > 96 && at(29).flowHeight < 176, 'Battery flow height must ease smoothly');
  assert.equal(at(34).flowHeight, 176);
  assert.ok(at(63).flowHeight > 96 && at(63).flowHeight < 176, 'Battery flow collapse must ease smoothly');
  assert.equal(at(68).flowHeight, 96);

  assert.equal(at(17).chargingWatts, 0);
  assert.equal(at(24).charging, true);
  assert.equal(at(24).chargingWatts, 36);
  assert.equal(find(ui.render(ui.exports.BatteryTourModule, {frame: 24}), 'data-feature', 'chargeToFull'), undefined);
  const charging = ui.render(ui.exports.BatteryTourModule, {frame: 40});
  const charged = ui.render(ui.exports.BatteryTourModule, {frame: 70});
  const unplugged = ui.render(ui.exports.BatteryTourModule, {frame: 98});
  for (const html of [charging, charged, unplugged]) {
    const rootNode = find(html, 'data-battery-detail');
    const order = rootNode.childNodes.filter((node) => node.tagName).map((node) => attr(node, 'data-battery-section')).filter(Boolean);
    assert.deepEqual(order, ['header', 'flow', 'readings', 'devices']);
    assert.equal(number(find(html, 'data-battery-metrics'), 'width'), 250);
    for (const route of nodes(html).filter((node) => attr(node, 'data-power-route'))) {
      assert.notEqual(attr(route, 'fill'), 'none', 'Native power routes are filled gradient panels, not Sankey strokes');
    }
  }
  assert.equal(at(70).level, 1);
  assert.equal(at(70).chargingWatts, 0);
  assert.equal(at(70).inputWatts, 12.7);
  assert.equal(at(70).systemWatts, 12.7);
  assert.equal(at(77).lowPower, false);
  assert.equal(at(78).lowPower, true);
  assert.equal(at(98).onBattery, true);
  assert.equal(at(98).inputWatts, 0);
  assert.match(textOf(unplugged), /On battery|Battery supply/);
  const batteryFrom = scenes.exports.DESKTOP_TOUR_STEPS.find((step) => step.id === 'battery').from;
  assert.match(textOf(scenes.render(scenes.exports.SceneDesktopTools, {}, batteryFrom + 35)), /Charge to 100% requested/);
  assert.match(textOf(scenes.render(scenes.exports.SceneDesktopTools, {}, batteryFrom + 65)), /Fully charged snapshot/);
  assert.match(textOf(scenes.render(scenes.exports.SceneDesktopTools, {}, batteryFrom + 100)), /Low power mode applied/);
});

test('mixer native rows mute one app and presenter uses in-stage hover controls with released camera', () => {
  const ui = modules;
  const mixer = ui.render(ui.exports.MixerTourModule, {frame: 90});
  const rows = nodes(mixer).filter((node) => attr(node, 'data-mixer-app'));
  assert.equal(rows.length, 2);
  for (const row of rows) {
    assert.equal(number(walk(row).find((node) => attr(node, 'data-mixer-name') !== undefined), 'width'), 220);
    assert.equal(number(walk(row).find((node) => attr(node, 'data-mixer-percent') !== undefined), 'width'), 48);
  }
  assert.equal(attr(rows[0], 'data-muted'), 'false');
  assert.equal(attr(rows[1], 'data-muted'), 'true');
  assert.match(textOf(mixer), /Safari30%|Music80%/);
  const presenter = ui.render(ui.exports.PresenterTourModule, {frame: 22});
  const stage = find(presenter, 'data-teleprompter-stage');
  const controls = walk(stage).find((node) => attr(node, 'data-teleprompter-controls') !== undefined);
  assert.ok(walk(stage).includes(controls), 'Teleprompter controls are outside its black stage');
  assert.equal(style(controls).position, 'absolute');
  assert.ok(number(controls, 'bottom') >= 8);
  assert.match(textOf(presenter), /45 pt\/s/);
  const playing = ui.render(ui.exports.PresenterTourModule, {frame: 44});
  assert.equal(find(playing, 'data-teleprompter-controls'), undefined);
  assert.equal(find(playing, 'data-camera-close'), undefined);
  assert.ok(find(ui.render(ui.exports.PresenterTourModule, {frame: 70}), 'data-camera-close'));
  const closed = ui.render(ui.exports.PresenterTourModule, {frame: 90});
  assert.equal(find(closed, 'data-camera-preview'), undefined);
  assert.match(textOf(closed), /Camera stopped|Script paused at your place/);
});

test('screen cleaning covers the desktop smoothly and keyboard cleaning keeps its end control visible', () => {
  const ui = scenes;
  const cleaningFrom = ui.exports.DESKTOP_TOUR_STEPS.find((step) => step.id === 'cleaning').from;
  const screen = ui.render(ui.exports.SceneDesktopTools, {}, cleaningFrom + 35);
  assert.ok(find(screen, 'data-screen-cleaning-cover'));
  const exit = find(screen, 'data-screen-cleaning-exit');
  assert.equal(number(exit, 'width'), 184);
  assert.equal(number(exit, 'height'), 52);
  assert.doesNotMatch(textOf(screen), /Finder|F1–F12|Keep display awake/);
  const keys = ui.render(ui.exports.SceneDesktopTools, {}, cleaningFrom + 100);
  assert.equal(find(keys, 'data-screen-cleaning-cover'), undefined);
  const notice = find(keys, 'data-keyboard-cleaning-notice');
  assert.match(content(notice), /Keyboard input blockedEnd cleaning/);
  assert.ok(number(notice, 'top') + number(notice, 'height') <= 136);
  const ended = ui.render(ui.exports.SceneDesktopTools, {}, cleaningFrom + 160);
  assert.equal(find(ended, 'data-keyboard-cleaning-notice'), undefined);
  assert.match(textOf(ended), /Keyboard input resumed/);
});

test('cleaning pauses on blocked input before the end cursor arrives and preserves a readable recovery', () => {
  const duration = 1156;
  const states = [];
  for (let frame = 0; frame < duration; frame++) {
    const state = scenes.exports.desktopTourAt(frame, duration);
    if (state.step.id !== 'cleaning') continue;
    const html = scenes.render(scenes.exports.SceneDesktopTools, {duration}, frame);
    const notice = find(html, 'data-keyboard-cleaning-notice');
    const cursors = visibleCursors(html);
    states.push({frame, local: state.frame, blocked: !!notice, recovered: !notice && textOf(html).includes('Keyboard input resumed'), cursors});
  }
  const blocked = states.filter((state) => state.blocked);
  assert.ok(blocked.length >= 60, `Keyboard cleaning only blocks input for ${blocked.length} actual frames`);
  const firstCursor = blocked.find((state) => state.cursors.length > 0);
  assert.ok(firstCursor, 'The End cleaning action never gets a visible cursor');
  assert.ok(firstCursor.frame - blocked[0].frame >= 24, 'The End cleaning cursor arrives before the blocked state can be read');
  const recovered = states.filter((state) => state.recovered);
  assert.ok(recovered.length >= 42, `Keyboard recovery disappears after only ${recovered.length} actual frames`);
  assert.ok(recovered.every((state) => state.cursors.length === 0), 'The recovery should stay clear after the end action');
  assert.equal(states.at(-1).recovered, true);
});

test('cleanup covers caches, duplicate apps and orphan AI workspaces while keeping the review item', () => {
  const ui = modules;
  const before = ui.render(ui.exports.CleanupTourModule, {frame: 8});
  const window = find(before, 'data-cleanup-window');
  assert.ok(window);
  assert.equal(number(window, 'width'), 560);
  assert.equal(number(window, 'height'), 430);
  assert.ok(find(before, 'data-cleanup-list'));
  assert.ok(find(before, 'data-cleanup-candidate', 'Duplicate apps & update leftovers'));
  assert.ok(find(before, 'data-cleanup-candidate', 'Orphan AI workspaces'));
  assert.equal(find(before, 'data-cleanup-confirmation'), undefined);
  const confirmation = ui.render(ui.exports.CleanupTourModule, {frame: 38});
  assert.ok(find(confirmation, 'data-cleanup-confirmation'));
  assert.match(textOf(confirmation), /Move 3 items to Trash|548 MB/);
  const done = ui.render(ui.exports.CleanupTourModule, {frame: 70});
  assert.equal(find(done, 'data-cleanup-confirmation'), undefined);
  const result = find(done, 'data-cleanup-result');
  assert.match(content(result), /3 items moved to Trash · 548 MB · Review item kept/);
  assert.ok(find(done, 'data-cleanup-candidate', 'Old preferences'));
  assert.equal(find(done, 'data-cleanup-candidate', 'Application caches'), undefined);
  const footer = find(done, 'data-cleanup-footer');
  assert.ok(number(footer, 'top') + number(footer, 'height') <= 430);
});

test('desktop timeline keeps the 1140-frame 1:1 budget and all final results under actual film duration', () => {
  const ui = scenes;
  assert.equal(ui.exports.DESKTOP_TOUR_DURATION, 1140);
  assert.equal(ui.exports.DESKTOP_TOUR_STEPS.reduce((sum, item) => sum + item.duration, 0), 1140);
  for (const duration of [1140, 1156]) {
    const at = ui.exports.desktopTourAt(duration - 1, duration);
    assert.equal(at.step.id, 'cleanup');
    assert.equal(at.frame, 94);
    assert.match(textOf(ui.render(ui.exports.SceneDesktopTools, {duration}, duration - 1)), /548 MB/);
    assert.equal(ui.exports.desktopTourAt(duration + 100, duration).frame, 94);
  }
});

test('headline caption and history controls fit the 1280 by 720 film stage', () => {
  for (const frame of [165, 220, 270, 315, 390, 800, 860, 910, 960, 1020, 1080, 1120]) {
    const html = scenes.render(scenes.exports.SceneDesktopTools, {}, frame);
    const tree = nodes(html);
    const headline = tree.find((node) => (attr(node, 'class') ?? '').includes('absolute inset-x-0 flex flex-col') && node.childNodes?.some((child) => (attr(child, 'class') ?? '').includes('font-semibold')) && number(node, 'top') > 0);
    const caption = tree.find((node) => (attr(node, 'class') ?? '').includes('absolute inset-x-0 flex justify-center') && number(node, 'bottom') > 0);
    if (!headline || !caption) continue;
    const line = headline.childNodes.find((node) => node.tagName);
    const pill = caption.childNodes.find((node) => node.tagName);
    const titleBottom = number(headline, 'top') + number(line, 'line-height');
    const captionTop = 720 - number(caption, 'bottom') - number(pill, 'line-height') - 18;
    assert.ok(titleBottom + 8 <= captionTop, `Headline and caption overlap at Desktop frame ${frame}`);
    const island = tree.find((node) => style(node).overflow === 'hidden' && number(node, 'width') === 776 && style(node).position === 'absolute');
    if (island) assert.ok(number(island, 'height') + 8 <= number(headline, 'top'), `Headline overlaps the Island at ${frame}`);
    const window = tree.find((node) => style(node)['transform-origin'] === 'top left');
    if (window) {
      const scale = Number(style(window).transform.match(/scale\(([\d.]+)\)/)?.[1]);
      assert.ok(number(window, 'top') + number(window, 'height') * scale + 8 <= captionTop, `Window overlaps the caption at ${frame}`);
    }
  }
});

test('every Desktop frame has at most one nontransparent cursor and dialogs replace the underlying cursor', () => {
  const violations = [];
  for (const duration of [1140, 1156]) for (let frame = 0; frame < duration; frame++) {
    const html = scenes.render(scenes.exports.SceneDesktopTools, {duration}, frame);
    const cursors = visibleCursors(html);
    if (cursors.length > 1) violations.push({duration, frame, cursors: cursors.length});
    const confirmation = find(html, 'data-cleanup-confirmation');
    if (confirmation && cursors.some((cursor) => !(() => {for (let node = cursor; node; node = node.parentNode) if (attr(node, 'data-cleanup-confirmation') !== undefined) return true; return false;})())) violations.push({duration, frame, underlyingConfirmationCursor: true});
  }
  assert.deepEqual(violations.slice(0, 12), [], `${violations.length} Desktop frames have conflicting cursors`);
});

const pressedFrames = (component, start, end, props = {}) => {
  const frames = [];
  for (let frame = start; frame < end; frame++) {
    const html = modules.render(component, {...props, frame});
    if (visibleCursors(html).some((cursor) => style(cursor).transform !== 'scale(1)')) frames.push({frame, html});
  }
  assert.ok(frames.length > 0, 'The action has no visible press frames');
  return frames;
};

test('every Desktop press keeps its target present throughout the six-frame click', () => {
  const ui = modules.exports;
  for (const {html} of pressedFrames(ui.KeyboardTourModule, 22, 28)) assert.match(content(find(html, 'data-keyboard-profile-menu')), /BCP \(Suit80\)/);
  for (const {html} of pressedFrames(ui.KeyboardTourModule, 34, 40)) assert.ok(find(html, 'aria-label', 'Preview'));
  for (const frame of [44, 45, 46, 47, 48, 49]) {
    const html = scenes.render(scenes.exports.SceneDesktopTools, {}, 245 + frame);
    assert.ok(find(html, 'data-feature', 'toolbox'));
    assert.match(textOf(html), /Prevent idle sleep/);
  }
  for (const {html} of pressedFrames(ui.BackgroundSoundsTourModule, 22, 28)) assert.ok(find(html, 'data-feature', 'backgroundSounds'));
  for (const {html} of pressedFrames(ui.BackgroundSoundsTourModule, 42, 48)) assert.match(textOf(html), /Ocean/);
  for (const {html} of pressedFrames(ui.SystemHistoryTourModule, 90, 96, {globalFrame: 9000})) {
    assert.equal(find(html, 'data-system-history-save'), undefined);
    assert.ok(find(html, 'data-system-history-header'));
  }
  for (const {html} of pressedFrames(ui.SystemHistoryTourModule, 102, 108, {globalFrame: 9000})) assert.ok(find(html, 'data-system-history-save'));
  for (const {html} of pressedFrames(ui.BatteryTourModule, 18, 24)) assert.ok(find(html, 'data-feature', 'chargeToFull'));
  for (const {html} of pressedFrames(ui.BatteryTourModule, 72, 78)) assert.match(content(find(html, 'data-battery-section', 'header')), /Low power/);
  for (const {html} of pressedFrames(ui.PresenterTourModule, 72, 78)) assert.ok(find(html, 'data-camera-close'));
  for (const {html} of pressedFrames(ui.CleanupTourModule, 26, 32)) {
    assert.equal(find(html, 'data-cleanup-confirmation'), undefined);
    assert.ok(find(html, 'data-cleanup-footer'));
  }
  for (const {html} of pressedFrames(ui.CleanupTourModule, 44, 50)) assert.ok(find(html, 'data-cleanup-confirmation'));
  const cleaningFrom = scenes.exports.DESKTOP_TOUR_STEPS.find((step) => step.id === 'cleaning').from;
  for (const [start, end, selector, x, y] of [[18, 24, 'data-feature', 370, 68], [48, 54, 'data-screen-cleaning-exit', 640, 360], [68, 74, 'data-feature', 626, 68], [130, 136, 'data-keyboard-cleaning-notice', 218, 20]]) {
    for (let local = start; local < end; local++) {
      const html = scenes.render(scenes.exports.SceneDesktopTools, {}, cleaningFrom + local + 0.25);
      const pressed = visibleCursors(html).filter((cursor) => style(cursor).transform !== 'scale(1)');
      assert.equal(pressed.length, 1);
      assert.equal(number(pressed[0], 'left') + 2, x, `Cleaning cursor moves horizontally during press ${local}`);
      assert.equal(number(pressed[0], 'top') + 2, y, `Cleaning cursor moves vertically during press ${local}`);
      assert.ok(find(html, selector), `Cleaning target ${selector} disappears during press ${local}`);
    }
  }
});
