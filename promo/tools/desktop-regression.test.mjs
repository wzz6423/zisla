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
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 10000}), Img: (props) => React.createElement('img', props)} : require(name);
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

test('keyboard sound selection is a Settings page followed by a separate scrolling Island dashboard', () => {
  const ui = modules;
  const before = ui.render(ui.exports.KeyboardTourModule, {frame: 0});
  assert.ok(find(before, 'data-keyboard-settings'), 'Keyboard sound controls must live in Settings');
  assert.equal(find(before, 'data-keyboard-dashboard'), undefined);
  assert.match(textOf(before), /Holy Panda/);
  assert.doesNotMatch(textOf(before), /12,846|Heatmap|App timeline/);
  const choices = ui.render(ui.exports.KeyboardTourModule, {frame: 18});
  const menu = find(choices, 'data-keyboard-profile-menu');
  assert.ok(menu, 'The native sound picker never opens');
  const native = readFileSync(new URL('../../mac/Sources/KeyboardKit/SwitchProfile.swift', import.meta.url), 'utf8');
  const expected = [...native.matchAll(/case \.\w+: "([^"]+)"/g)].slice(0, 20).map((match) => match[1]);
  assert.equal(expected.length, 20);
  for (const voice of expected) assert.ok(content(menu).includes(voice), voice);
  assert.match(content(menu), /BCP \(Suit80\)/);
  assert.doesNotMatch(textOf(choices), /Import|Add pack/);
  assert.match(textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 60})), /BCP \(Suit80\)/);
  for (const frame of [78, 100, 138, 179]) {
    const html = ui.render(ui.exports.KeyboardTourModule, {frame});
    assert.ok(find(html, 'data-keyboard-dashboard'));
    assert.equal(find(html, 'data-keyboard-settings'), undefined);
    assert.doesNotMatch(textOf(html), /Global sounds|Release sounds|Pitch variation|Preview/);
  }
  const stats = ui.render(ui.exports.KeyboardTourModule, {frame: 78});
  for (const label of ['Characters Today', 'Top app', 'Peak Today', 'Active time', 'Typing trend', 'History', 'Keyboard', 'App timeline']) assert.ok(textOf(stats).includes(label), label);
  const cards = nodes(stats).filter((node) => attr(node, 'data-typing-metric') !== undefined);
  assert.equal(cards.length, 4);
  for (const card of cards) assert.equal(number(card, 'height'), 76);
  const viewport = find(stats, 'data-keyboard-scroll');
  assert.equal(style(viewport).overflow, 'hidden');
  const final = ui.render(ui.exports.KeyboardTourModule, {frame: 179});
  const scroll = find(final, 'data-keyboard-scroll-content');
  assert.ok(style(scroll).transform.includes('translateY(-'));
  const timeline = find(final, 'data-keyboard-timeline');
  const scrollY = Number(style(scroll).transform.match(/translateY\((-?[\d.]+)px\)/)?.[1]);
  assert.ok(Number(attr(timeline, 'data-content-y')) + scrollY + number(timeline, 'height') <= number(viewport, 'height'));
  const scene = scenes.render(scenes.exports.SceneDesktopTools, {}, 180 + 90);
  assert.ok(find(scene, 'data-keyboard-dashboard'));
  const island = nodes(scene).find((node) => number(node, 'width') === 776 && number(node, 'top') === 0 && style(node).overflow === 'hidden');
  assert.ok(island, 'The keyboard dashboard is still an external tour card');
});

test('typing increments only from the demonstrated key presses and keeps all 14 characters', () => {
  const at = modules.exports.keyboardTourAt;
  assert.ok(at, 'Typing needs a shared causal state');
  let previous = 12846;
  for (let frame = 0; frame < 180; frame++) {
    const state = at(frame);
    assert.ok(state.characters >= previous && state.characters <= 12860);
    assert.ok(state.characters - previous <= 1);
    if (frame < 92) assert.equal(state.characters, 12846);
    if (frame >= 126) assert.equal(state.characters, 12860);
    previous = state.characters;
  }
  assert.deepEqual(at(-10), at(0));
  assert.deepEqual(at(300), at(179));
  assert.match(textOf(modules.render(modules.exports.KeyboardTourModule, {frame: 78})), /12,846/);
  assert.match(textOf(modules.render(modules.exports.KeyboardTourModule, {frame: 138})), /12,860/);
  const done = scenes.render(scenes.exports.SceneDesktopTools, {}, 180 + 160);
  assert.match(textOf(done), /14 characters added/);
});

test('focus start pause continue completes once and transitions to idle five-minute rest', () => {
  const at = modules.exports.focusTourAt;
  assert.deepEqual(at(-5), at(0));
  assert.equal(at(0).phase, 'idle');
  assert.equal(at(38).phase, 'running');
  const frozen = at(80).remaining;
  assert.ok(frozen > 1 && frozen < 2);
  for (let frame = 80; frame < 112; frame++) {
    assert.equal(at(frame).phase, 'paused');
    assert.equal(at(frame).remaining, frozen);
  }
  assert.equal(at(112).remaining, frozen);
  for (let frame = 113; frame < 190; frame++) assert.ok(at(frame).remaining < at(frame - 1).remaining);
  for (let frame = 190; frame < 240; frame++) {
    assert.equal(at(frame).phase, 'idle');
    assert.equal(at(frame).mode, 'rest');
    assert.equal(at(frame).remaining, 300);
  }
  assert.equal(at(190).completed, true);
  assert.equal(at(225).completed, false);
  assert.deepEqual(at(600), at(239));
  assert.match(textOf(modules.render(modules.exports.FocusTourModule, {frame: 205})), /Rest5:00⌄StartReset/);
  let starts = 0;
  for (let frame = 1; frame < 240; frame++) if (at(frame).phase === 'running' && at(frame - 1).phase === 'idle') starts++;
  assert.equal(starts, 1);
});

test('focus compact pause continue and reset controls stay visible with status outside the clipped module', () => {
  const ui = scenes;
  for (const [local, label] of [[70, 'Pause'], [95, 'Continue'], [145, 'Pause']]) {
    const html = ui.render(ui.exports.SceneDesktopTools, {}, 360 + local);
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
  const done = ui.render(ui.exports.SceneDesktopTools, {}, 360 + 200);
  assert.match(textOf(done), /Focus completed|5:00/);
  assert.equal(find(done, 'data-compact-focus-controls'), undefined, 'The completed idle timer must reopen the toolbox');
  const reset = ui.render(ui.exports.SceneDesktopTools, {}, 360 + 239);
  assert.match(textOf(reset), /Rest5:00⌄StartReset/);
  for (const local of [80, 112]) {
    const tree = nodes(ui.render(ui.exports.SceneDesktopTools, {}, 360 + local));
    const cursor = tree.find((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26' && number(node, 'opacity') > 0);
    assert.ok(cursor);
    assert.ok(number(cursor, 'left') >= 749 && number(cursor, 'left') <= 773);
    assert.ok(number(cursor, 'top') >= 3 && number(cursor, 'top') <= 27);
  }
});

test('system history uses its native independent 720 by 560 window and scrolls six single-row categories', () => {
  const ui = modules;
  const at = ui.exports.systemHistoryTourAt;
  assert.ok(at);
  const live = ui.render(ui.exports.SystemHistoryTourModule, {frame: 0, globalFrame: 8000});
  assert.equal(find(live, 'data-system-history-window'), undefined);
  const settings = ui.render(ui.exports.SystemHistoryTourModule, {frame: 25, globalFrame: 8025});
  assert.ok(find(settings, 'data-system-history-settings'));
  assert.match(textOf(settings), /Record history|View history/);
  const html = ui.render(ui.exports.SystemHistoryTourModule, {frame: 70, globalFrame: 8070});
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
  for (let frame = 36; frame < 170; frame++) {
    const state = at(frame);
    for (let index = 0; index < rows.length; index++) {
      const y = index * 190 - state.scroll;
      if (y >= 0 && y + 178 <= 404) seen.add(attr(rows[index], 'data-history-category'));
    }
    if (frame > 36) assert.ok(state.scroll >= at(frame - 1).scroll);
  }
  assert.equal(seen.size, 6, 'Some history categories never become fully visible');
  assert.equal(at(70).scroll, 0);
  assert.equal(at(110).scroll, 380);
  assert.equal(at(125).scroll, 380);
  assert.equal(at(160).scroll, 724);
  assert.equal(at(180).scroll, 724);
  assert.doesNotMatch(textOf(ui.render(ui.exports.SystemHistoryTourModule, {frame: 124, globalFrame: 8124})), /Saved:/);
  assert.ok(find(ui.render(ui.exports.SystemHistoryTourModule, {frame: 195, globalFrame: 8195}), 'data-system-history-save'));
  const final = ui.render(ui.exports.SystemHistoryTourModule, {frame: 269, globalFrame: 8269});
  assert.equal(find(final, 'data-system-history-save'), undefined);
  assert.match(textOf(final), /Saved: System history.xlsx/);
  assert.ok(number(find(final, 'data-system-history-footer'), 'height') === 16);
  for (let frame = 206; frame <= 269; frame += 9) assert.match(textOf(ui.render(ui.exports.SystemHistoryTourModule, {frame, globalFrame: 8000 + frame})), /Saved: System history.xlsx/);
});

test('battery header flow trends and metric column match native order without completing the charge request', () => {
  const ui = modules;
  const at = ui.exports.batteryTourAt;
  assert.ok(at);
  for (const frame of [0, 45, 120, 190, 300]) {
    const state = at(frame);
    assert.equal(state.level, 0.76);
    if (!state.onBattery) assert.equal(state.inputWatts, state.chargingWatts + state.systemWatts);
    else assert.equal(state.chargingWatts, 0);
    const html = ui.render(ui.exports.BatteryTourModule, {frame});
    const rootNode = find(html, 'data-battery-detail');
    const order = rootNode.childNodes.filter((node) => node.tagName).map((node) => attr(node, 'data-battery-section')).filter(Boolean);
    assert.deepEqual(order, ['header', 'flow', 'readings', 'devices']);
    assert.equal(number(find(html, 'data-battery-section', 'flow'), 'height'), 176);
    assert.equal(number(find(html, 'data-battery-metrics'), 'width'), 250);
    assert.match(textOf(html), /76%/);
    assert.doesNotMatch(textOf(html), /Fully charged|100% charged/);
  }
  const charging = ui.render(ui.exports.BatteryTourModule, {frame: 65});
  assert.match(textOf(scenes.render(scenes.exports.SceneDesktopTools, {}, 1290 + 60)), /Charge to 100% requested/);
  const paths = nodes(charging).filter((node) => attr(node, 'data-power-route'));
  assert.deepEqual(paths.map((node) => attr(node, 'data-power-route')), ['battery', 'system']);
  assert.match(textOf(charging), /60 W|36 W|24 W/);
  const unplugged = ui.render(ui.exports.BatteryTourModule, {frame: 135});
  assert.equal(find(unplugged, 'data-power-route', 'battery'), undefined);
  assert.match(textOf(unplugged), /On battery|Automatic/);
  assert.match(textOf(scenes.render(scenes.exports.SceneDesktopTools, {}, 1290 + 160)), /Low power mode applied/);
});

test('mixer native rows mute one app and presenter uses in-stage hover controls with released camera', () => {
  const ui = modules;
  const mixer = ui.render(ui.exports.MixerTourModule, {frame: 150});
  const rows = nodes(mixer).filter((node) => attr(node, 'data-mixer-app'));
  assert.equal(rows.length, 2);
  for (const row of rows) {
    assert.equal(number(walk(row).find((node) => attr(node, 'data-mixer-name') !== undefined), 'width'), 220);
    assert.equal(number(walk(row).find((node) => attr(node, 'data-mixer-percent') !== undefined), 'width'), 48);
  }
  assert.equal(attr(rows[0], 'data-muted'), 'false');
  assert.equal(attr(rows[1], 'data-muted'), 'true');
  assert.match(textOf(mixer), /Safari30%|Music80%/);
  const presenter = ui.render(ui.exports.PresenterTourModule, {frame: 40});
  const stage = find(presenter, 'data-teleprompter-stage');
  const controls = walk(stage).find((node) => attr(node, 'data-teleprompter-controls') !== undefined);
  assert.ok(walk(stage).includes(controls), 'Teleprompter controls are outside its black stage');
  assert.equal(style(controls).position, 'absolute');
  assert.ok(number(controls, 'bottom') >= 8);
  assert.match(textOf(presenter), /45 pt\/s/);
  const playing = ui.render(ui.exports.PresenterTourModule, {frame: 85});
  assert.equal(find(playing, 'data-teleprompter-controls'), undefined);
  assert.equal(find(playing, 'data-camera-close'), undefined);
  assert.ok(find(ui.render(ui.exports.PresenterTourModule, {frame: 128}), 'data-camera-close'));
  const closed = ui.render(ui.exports.PresenterTourModule, {frame: 155});
  assert.equal(find(closed, 'data-camera-preview'), undefined);
  assert.match(textOf(closed), /Camera stopped|Script paused at your place/);
});

test('screen cleaning covers the desktop in black and keyboard cleaning keeps its end control visible', () => {
  const ui = scenes;
  const screen = ui.render(ui.exports.SceneDesktopTools, {}, 720 + 40);
  assert.ok(find(screen, 'data-screen-cleaning-cover'));
  const exit = find(screen, 'data-screen-cleaning-exit');
  assert.equal(number(exit, 'width'), 184);
  assert.equal(number(exit, 'height'), 52);
  assert.doesNotMatch(textOf(screen), /Finder|F1–F12|Keep display awake/);
  const keys = ui.render(ui.exports.SceneDesktopTools, {}, 720 + 100);
  assert.equal(find(keys, 'data-screen-cleaning-cover'), undefined);
  const notice = find(keys, 'data-keyboard-cleaning-notice');
  assert.match(content(notice), /Keyboard input blockedEnd cleaning/);
  assert.ok(number(notice, 'top') + number(notice, 'height') <= 136);
  const ended = ui.render(ui.exports.SceneDesktopTools, {}, 720 + 140);
  assert.equal(find(ended, 'data-keyboard-cleaning-notice'), undefined);
  assert.match(textOf(ended), /Keyboard input resumed/);
});

test('cleanup uses a 560 by 430 source-grouped list and keeps the review item after one confirmation', () => {
  const ui = modules;
  const before = ui.render(ui.exports.CleanupTourModule, {frame: 10});
  const window = find(before, 'data-cleanup-window');
  assert.ok(window);
  assert.equal(number(window, 'width'), 560);
  assert.equal(number(window, 'height'), 430);
  assert.ok(find(before, 'data-cleanup-list'));
  assert.equal(find(before, 'data-cleanup-confirmation'), undefined);
  assert.doesNotMatch(textOf(before), /Automatic cleanup/);
  const confirmation = ui.render(ui.exports.CleanupTourModule, {frame: 60});
  assert.ok(find(confirmation, 'data-cleanup-confirmation'));
  assert.match(textOf(confirmation), /Move 2 items to Trash|344 MB/);
  const done = ui.render(ui.exports.CleanupTourModule, {frame: 110});
  assert.equal(find(done, 'data-cleanup-confirmation'), undefined);
  const result = find(done, 'data-cleanup-result');
  assert.match(content(result), /2 items moved to Trash · 344 MB · Review item kept/);
  assert.ok(find(done, 'data-cleanup-candidate', 'Old preferences'));
  assert.equal(find(done, 'data-cleanup-candidate', 'Application caches'), undefined);
  const footer = find(done, 'data-cleanup-footer');
  assert.ok(number(footer, 'top') + number(footer, 'height') <= 430);
});

test('desktop timeline keeps the 1620-frame budget and all final results under actual film duration', () => {
  const ui = scenes;
  assert.equal(ui.exports.DESKTOP_TOUR_DURATION, 1620);
  assert.equal(ui.exports.DESKTOP_TOUR_STEPS.reduce((sum, item) => sum + item.duration, 0), 1620);
  for (const duration of [1380, 1396, 1620, 1636]) {
    const at = ui.exports.desktopTourAt(duration - 1, duration);
    assert.equal(at.step.id, 'cleanup');
    assert.equal(at.frame, 149);
    assert.match(textOf(ui.render(ui.exports.SceneDesktopTools, {duration}, duration - 1)), /344 MB/);
    assert.equal(ui.exports.desktopTourAt(duration + 100, duration).frame, 149);
  }
});

test('headline caption and history controls fit the 1280 by 720 film stage', () => {
  for (const frame of [270, 340, 398, 455, 560, 1045, 1070, 1215, 1250, 1350, 1450, 1530, 1580]) {
    const html = scenes.render(scenes.exports.SceneDesktopTools, {}, frame);
    const tree = nodes(html);
    const headline = tree.find((node) => (attr(node, 'class') ?? '').includes('absolute inset-x-0 flex flex-col') && number(node, 'top') > 0);
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

test('memory mutations are rejected by rendered layout and causal state checks', () => {
  const check = (name, entry, needle, replacement, verify) => {
    const ui = load(entry, (source) => {
      assert.ok(source.includes(needle), `Mutation ${name} no longer reaches the implementation`);
      return source.replaceAll(needle, replacement);
    });
    assert.throws(() => verify(ui), undefined, `Mutation ${name} escaped the regression checks`);
  };
  const sceneSource = 'src/scenes/SceneDesktopTools.tsx';
  const moduleSource = 'src/modules/tour/DesktopTourModule.tsx';
  const renderModule = (ui, name, frame) => ui.render(ui.exports[name], {frame, globalFrame: 9000});
  check('mixed keyboard page', moduleSource, 'position < 78 ? "settings" : "dashboard"', '"settings"', (ui) => assert.ok(find(renderModule(ui, 'KeyboardTourModule', 100), 'data-keyboard-dashboard')));
  for (const [name, needle, replacement, verify] of [
    ['typing reset', '[0, 14]', '[0, 0]', (ui) => assert.equal(ui.exports.keyboardTourAt(160).characters, 12860)],
    ['typing count drifts', '[0, 14]', '[0, 28]', (ui) => assert.equal(ui.exports.keyboardTourAt(160).characters, 12860)],
    ['missing heatmap scroll', '[0, 282]', '[0, 0]', (ui) => assert.ok(ui.exports.keyboardTourAt(179).scroll >= 282)],
    ['pause loses retained seconds', 'Math.min(position - 38, 42)', 'Math.min(position - 38, 0)', (ui) => assert.equal(ui.exports.focusTourAt(95).remaining, 1.3)],
    ['completion leaves zero timer', 'finished ? 300', 'finished ? 0', (ui) => assert.equal(ui.exports.focusTourAt(200).remaining, 300)],
    ['completion keeps focus mode', 'finished ? "rest" : "focus"', '"focus"', (ui) => assert.equal(ui.exports.focusTourAt(200).mode, 'rest')],
    ['history exported early', 'position >= 206', 'position >= 0', (ui) => assert.equal(ui.exports.systemHistoryTourAt(70).exported, false)],
    ['history missing save dialog', 'position >= 188 && position < 206', 'false', (ui) => assert.ok(find(renderModule(ui, 'SystemHistoryTourModule', 195), 'data-system-history-save'))],
    ['history fails to reach network', '[380, 724]', '[380, 380]', (ui) => assert.ok(ui.exports.systemHistoryTourAt(170).scroll >= 724)],
    ['history data restarts', 'position < 120', 'position < 240', (ui) => assert.equal(ui.exports.systemHistoryTourAt(170).scroll, 724)],
    ['battery immediately full', 'level: 0.76', 'level: 1', (ui) => assert.equal(ui.exports.batteryTourAt(65).level, 0.76)],
    ['battery violates power balance', 'chargingWatts: 36', 'chargingWatts: 60', (ui) => {const state = ui.exports.batteryTourAt(65); assert.equal(state.inputWatts, state.chargingWatts + state.systemWatts);}],
    ['battery charges when unplugged', 'onBattery ? 0 : desktopDemo.battery.chargingWatts', 'desktopDemo.battery.chargingWatts', (ui) => assert.equal(ui.exports.batteryTourAt(150).chargingWatts, 0)],
    ['mutes every app', 'index === 1 && muted', 'muted', (ui) => assert.equal(attr(find(renderModule(ui, 'MixerTourModule', 150), 'data-mixer-app', 'Safari'), 'data-muted'), 'false')],
    ['camera remains live', 'frame >= 136', 'frame >= 500', (ui) => assert.equal(find(renderModule(ui, 'PresenterTourModule', 155), 'data-camera-preview'), undefined)],
    ['cleanup removes review item', '!done || index === 2', '!done', (ui) => assert.ok(find(renderModule(ui, 'CleanupTourModule', 110), 'data-cleanup-candidate', 'Old preferences'))],
    ['cleanup skips confirmation', 'frame >= 49 && frame < 74', 'false', (ui) => assert.ok(find(renderModule(ui, 'CleanupTourModule', 60), 'data-cleanup-confirmation'))],
  ]) check(name, moduleSource, needle, replacement, verify);
  for (const [name, marker] of [['history window missing', 'data-system-history-window'], ['keyboard sound menu missing', 'data-keyboard-profile-menu'], ['native battery flow missing', 'data-power-route'], ['prompter controls missing', 'data-teleprompter-controls'], ['review confirmation missing', 'data-cleanup-confirmation']]) {
    const [component, frame] = marker === 'data-system-history-window' ? ['SystemHistoryTourModule', 80] : marker === 'data-keyboard-profile-menu' ? ['KeyboardTourModule', 18] : marker === 'data-power-route' ? ['BatteryTourModule', 65] : marker === 'data-teleprompter-controls' ? ['PresenterTourModule', 40] : ['CleanupTourModule', 60];
    check(name, moduleSource, `"${marker}"`, `"data-removed-${marker}"`, (ui) => assert.ok(find(renderModule(ui, component, frame), marker)));
  }
  check('compact controls removed', sceneSource, 'state.compact ? 0 : 1', '1', (ui) => assert.ok(find(ui.render(ui.exports.SceneDesktopTools, {}, 455), 'data-compact-focus-controls')));
  check('focus status moved behind clipping', sceneSource, '97 : 324', '0 : 0', (ui) => assert.ok(number(find(ui.render(ui.exports.SceneDesktopTools, {}, 455), 'data-focus-status'), 'top') > 34));
  check('full-screen cleaning missing', sceneSource, 'cleaningFrame >= 26 && cleaningFrame < 87', 'false', (ui) => assert.ok(find(ui.render(ui.exports.SceneDesktopTools, {}, 760), 'data-screen-cleaning-cover')));
});
