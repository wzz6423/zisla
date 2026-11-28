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
  return {exports: module.exports, render: (Component, props = {}, frame = 0) => {clock.frame = frame; return parseFragment(renderToStaticMarkup(React.createElement(Component, props)));}};
};
const all = (node) => [node, ...(node?.childNodes ?? []).flatMap(all)];
const attr = (node, name) => node?.attrs?.find((entry) => entry.name === name)?.value;
const textOf = (node) => node?.nodeName === '#text' ? node.value : (node?.childNodes ?? []).map(textOf).join('');
const find = (tree, name, value) => all(tree).find((node) => attr(node, name) !== undefined && (value === undefined || attr(node, name) === value));
const style = (node) => Object.fromEntries((attr(node, 'style') ?? '').split(';').filter(Boolean).map((entry) => {const colon = entry.indexOf(':'); return [entry.slice(0, colon), entry.slice(colon + 1)];}));
const number = (node, name) => Number.parseFloat(style(node)[name] ?? '0');
const cursor = (tree) => all(tree).filter((node) => node.tagName === 'svg' && attr(node, 'viewBox') === '0 0 20 26');
const inside = (x, y, width, height) => assert.ok(x >= 0 && x <= width && y >= 0 && y <= height, `Point (${x}, ${y}) leaves ${width} × ${height}`);
const ui = load('src/modules/tour/SettingsTourModule.tsx');
const scene = load('src/scenes/SceneSettings.tsx');
const recommended = load('src/modules/tour/RecommendedDesktopTour.tsx');
const lid = load('src/modules/tour/LidCloseDesktopPreview.tsx');
const moduleFrame = (name, frame) => ui.render(ui.exports[name], {frame, globalFrame: 6200 + frame});
const recommendedFrame = (frame) => recommended.render(recommended.exports.RecommendedDesktopTour, {frame});

test('Quick Actions keep a single pointer through source copy, top-bar menu and execution', () => {
  for (let frame = 0; frame < 200; frame++) {
    const tree = moduleFrame('QuickActionsTourModule', frame);
    const visible = cursor(tree).filter((node) => number(node, 'opacity') > 0);
    assert.ok(visible.length <= 1, `Quick Actions frame ${frame} has ${visible.length} visible pointers`);
  }
  assert.equal(ui.exports.quickActionsTourAt(22).menu, false, 'The menu must wait for the more-actions click');
  assert.equal(ui.exports.quickActionsTourAt(27).menu, false);
  assert.equal(ui.exports.quickActionsTourAt(28).menu, true);
  assert.equal(ui.exports.quickActionsTourAt(38).menu, true, 'The clicked menu item must still be present at the click frame');
  assert.equal(ui.exports.quickActionsTourAt(43).menu, true);
  assert.equal(ui.exports.quickActionsTourAt(44).done, true);
  assert.equal(ui.exports.quickActionsTourAt(88 + 44).started, false, 'The repair button must still exist at the click frame');
  assert.equal(ui.exports.quickActionsTourAt(88 + 49).started, false);
  assert.equal(ui.exports.quickActionsTourAt(88 + 50).started, true);
  for (const [frame, copied] of [[15, false], [16, true], [88 + 25, false], [88 + 26, true]]) assert.equal(ui.exports.quickActionsTourAt(frame).copied, copied);
  for (const [frame, x, y] of [[10, 405, 430], [22, 872.5, 17], [38, 789, 65], [88 + 10, 791, 389], [88 + 20, 640, 400], [88 + 44, 819, 17]]) {
    const tip = cursor(moduleFrame('QuickActionsTourModule', frame)).find((node) => number(node, 'opacity') > 0);
    assert.ok(tip);
    assert.equal(number(tip, 'left') + 2, x);
    assert.equal(number(tip, 'top') + 2, y);
    assert.match(style(tip).transform, /scale\(0\.9\)/);
  }
  for (const [from, data, value] of [[10, 'data-copied-currency'], [22, 'data-quick-action-more'], [38, 'role', 'menuitem'], [88 + 10, 'data-repair-alert-ok'], [88 + 20, 'data-quick-action-source', 'Studio.app'], [88 + 44, 'data-quick-action-primary']]) {
    for (let frame = from; frame < from + 6; frame++) assert.ok(find(moduleFrame('QuickActionsTourModule', frame), data, value), `${data} disappears during the press at frame ${frame}`);
  }
});

test('Quick Action controls remain single-line and reserve the entire physical notch', () => {
  for (const [frame, width, left, label] of [[30, 560, 360, 'Copy result'], [88 + 38, 620, 330, 'Repair and open']]) {
    const toast = find(moduleFrame('QuickActionsTourModule', frame), 'data-quick-action-toast');
    const bar = toast.childNodes.find((node) => node.tagName === 'div');
    assert.equal(number(bar, 'width'), width);
    assert.equal(number(bar, 'left'), left);
    assert.equal(number(bar, 'top'), 0);
    const primary = find(bar, 'data-quick-action-primary');
    assert.ok(primary, 'The native primary action needs a measurable target');
    assert.equal(textOf(primary), label);
    assert.match(attr(primary, 'class'), /whitespace-nowrap/);
    assert.match(attr(primary, 'class'), /shrink-0/);
    const wings = bar.childNodes.filter((node) => node.tagName === 'div');
    assert.equal(number(wings[0], 'width'), (width - 190) / 2);
    assert.equal(number(wings[1], 'width'), 190);
    assert.equal(number(wings[2], 'width'), (width - 190) / 2);
    assert.ok(find(bar, 'data-quick-action-more'));
    assert.ok(find(bar, 'data-quick-action-dismiss'));
  }
});

test('Lock screen matches the three native overlays, five playback controls and paused progress', () => {
  const before = moduleFrame('LockScreenTourModule', 31);
  const header = find(before, 'data-lock-overlay', 'header');
  const status = find(before, 'data-lock-overlay', 'status');
  const player = find(before, 'data-lock-overlay', 'player');
  assert.ok(header && status && player, 'Lock screen overlays must remain independently placed');
  assert.deepEqual([number(header, 'left'), number(header, 'top'), number(header, 'width'), number(header, 'height')], [360, 158.4, 560, 72]);
  assert.deepEqual([number(status, 'left'), number(status, 'top'), number(status, 'width'), number(status, 'height')], [360, 235.4, 560, 46]);
  assert.deepEqual([number(player, 'left'), number(player, 'top'), number(player, 'width'), number(player, 'height')], [430, 387.2, 420, 176]);
  assert.equal(number(find(player, 'data-lock-artwork'), 'width'), 56);
  assert.match(textOf(find(player, 'data-lock-track')), /Paper Lanterns · Mira Solen/);
  assert.ok(textOf(find(player, 'data-lock-lyrics')).length > 0);
  assert.deepEqual(all(player).filter((node) => attr(node, 'data-lock-action')).map((node) => attr(node, 'data-lock-action')), ['mode', 'previous', 'toggle', 'next', 'favorite']);
  const stopped = moduleFrame('LockScreenTourModule', 32);
  for (const frame of [33, 50, 75]) {
    const later = moduleFrame('LockScreenTourModule', frame);
    assert.equal(attr(find(later, 'data-lock-playback-progress'), 'data-elapsed'), attr(find(stopped, 'data-lock-playback-progress'), 'data-elapsed'));
    assert.equal(textOf(find(later, 'data-lock-lyrics')), textOf(find(stopped, 'data-lock-lyrics')));
  }
  assert.equal(attr(find(stopped, 'data-lock-action', 'toggle'), 'aria-label'), 'Play');
  const advanced = ui.exports.lockScreenTourAt(31, 6200);
  assert.ok(advanced.elapsed > ui.exports.lockScreenTourAt(0, 6200).elapsed);
  assert.equal(ui.exports.lockScreenTourAt(75, 6200).elapsed, ui.exports.lockScreenTourAt(32, 6200).elapsed);
});

test('CLI film focuses the demonstrated installation while native source retains uninstall actions', () => {
  const source = readFileSync(new URL('../../mac/Sources/Zisla/AIAgentModuleView.swift', import.meta.url), 'utf8');
  assert.match(source, /commandsForCLIUninstallation\(installedKinds\)/);
  assert.match(source, /commandsForCLIUninstallation\(\[kind\]\)/);
  assert.doesNotMatch(textOf(moduleFrame('ManagementTourModule', 45)), /Uninstall/);
  assert.equal(find(moduleFrame('ManagementTourModule', 10), 'role', 'alertdialog'), undefined);
  assert.equal(find(moduleFrame('ManagementTourModule', 15), 'role', 'alertdialog'), undefined);
  assert.ok(find(moduleFrame('ManagementTourModule', 16), 'role', 'alertdialog'));
  assert.ok(find(moduleFrame('ManagementTourModule', 22), 'data-cli-confirm-submit'));
  assert.ok(find(moduleFrame('ManagementTourModule', 27), 'role', 'alertdialog'));
  assert.equal(find(moduleFrame('ManagementTourModule', 28), 'role', 'alertdialog'), undefined);
  const sync = moduleFrame('ManagementTourModule', 84);
  const syncTip = cursor(sync).find((node) => number(node, 'opacity') > 0);
  assert.ok(syncTip, 'Skills sync must have a pointer at its click frame');
  assert.match(style(syncTip).transform, /scale\(0\.9\)/);
  assert.ok(find(sync, 'data-skills-sync'));
  assert.doesNotMatch(textOf(sync), /Skills synced to enabled CLIs/);
  assert.match(textOf(moduleFrame('ManagementTourModule', 90)), /Skills synced to enabled CLIs/);
  for (let frame = 0; frame < 132; frame++) assert.ok(cursor(moduleFrame('ManagementTourModule', frame)).filter((node) => number(node, 'opacity') > 0).length <= 1, `CLI frame ${frame} has duplicate pointers`);
  for (const [from, data, value, x, y] of [[10, 'data-cli-action', 'Gemini', 952, 262], [22, 'data-cli-confirm-submit', undefined, 354, 126], [84, 'data-skills-sync', undefined, 956, 80]]) {
    for (let frame = from; frame < from + 6; frame++) {
      const tree = moduleFrame('ManagementTourModule', frame);
      assert.ok(find(tree, data, value), `${data} disappears during the press at frame ${frame}`);
      const pointer = cursor(tree).find((node) => number(node, 'opacity') > 0);
      assert.equal(number(pointer, 'left') + 2, x);
      assert.equal(number(pointer, 'top') + 2, y);
      assert.match(style(pointer).transform, /scale\(0\.9\)/);
    }
  }
});

test('Recommended tools transition from the native list through Applications to a standalone Zshell desktop', () => {
  const list = recommendedFrame(14);
  assert.equal(find(list, 'data-recommended-dock'), undefined, 'A simulated Dock cannot be embedded in Settings');
  assert.match(textOf(find(list, 'data-recommended-section', 'tools')), /OpenScreen.*DockDoor.*Zshell/);
  const applications = recommended.render(recommended.exports.RecommendedDesktopTour, {frame: 32});
  assert.ok(find(applications, 'data-recommended-applications'));
  assert.equal(find(applications, 'data-recommended-app'), undefined);
  const icon = find(applications, 'alt', 'Zshell');
  assert.match(attr(icon, 'src'), /^data:image\/png;base64,/);
  const png = Buffer.from(attr(icon, 'src').split(',')[1], 'base64');
  assert.equal(png.readUInt32BE(16), 128);
  assert.equal(png.readUInt32BE(20), 128);
  const app = recommendedFrame(54);
  assert.ok(find(app, 'data-recommended-app', 'Zshell'), 'Recommended apps must open in a separate desktop window');
  assert.equal(find(app, 'data-recommended-section'), undefined);
  const snapshot = recommended.render(recommended.exports.ZshellTourDesktop);
  assert.equal(textOf(find(app, 'data-recommended-app')), textOf(find(snapshot, 'data-recommended-app')));
  assert.equal(ui.exports.recommendedTourAt(43).opened, false);
  assert.equal(ui.exports.recommendedTourAt(44).opened, true);
  for (const frame of [44, 68, 93]) {
    const opened = recommendedFrame(frame);
    assert.equal(textOf(find(opened, 'data-recommended-app')), textOf(find(snapshot, 'data-recommended-app')));
    assert.equal(cursor(opened).length, 0);
  }
});

test('Settings covers the 940-frame 1:1 timeline once and keeps fractional-frame boundaries continuous', () => {
  const {SETTINGS_TOUR_DURATION, SETTINGS_TOUR_STEPS, settingsTourAt} = scene.exports;
  assert.equal(SETTINGS_TOUR_DURATION, 940);
  assert.deepEqual(SETTINGS_TOUR_STEPS.map((step) => step.id), ['windows', 'quickActions', 'information', 'permissions', 'lockScreen', 'management', 'recommended']);
  let end = 0;
  for (const step of SETTINGS_TOUR_STEPS) {assert.equal(step.from, end); end += step.duration;}
  assert.equal(end, SETTINGS_TOUR_DURATION);
  const seen = [];
  let previous;
  for (let frame = 0; frame < 956; frame++) {
    const state = settingsTourAt(frame, 956);
    assert.ok(state.frame >= 0 && state.frame < state.step.duration);
    if (!previous || state.step.id !== previous.step.id) seen.push(state.step.id);
    else assert.ok(state.frame > previous.frame);
    previous = state;
  }
  assert.deepEqual(seen, SETTINGS_TOUR_STEPS.map((step) => step.id));
  assert.equal(settingsTourAt(-10, 956).frame, 0);
  assert.equal(settingsTourAt(955, 956).frame, 183);
  assert.deepEqual(settingsTourAt(2000, 956), settingsTourAt(955, 956));
});

test('Dock and Command-Tab preview only one selected app and close on activation', () => {
  const dock = moduleFrame('WindowsTourModule', 12);
  const dockPreview = find(dock, 'data-window-preview-app', 'Safari');
  assert.ok(dockPreview);
  assert.equal(attr(dockPreview, 'data-preview-source'), 'dock');
  assert.deepEqual(all(dockPreview).filter((node) => attr(node, 'data-preview-title')).map((node) => attr(node, 'data-preview-title')), ['Launch review', 'Documentation']);
  const switcher = moduleFrame('WindowsTourModule', 30);
  const notes = find(switcher, 'data-window-preview-app', 'Notes');
  assert.ok(notes);
  assert.equal(attr(notes, 'data-preview-source'), 'switcher');
  assert.equal(all(switcher).filter((node) => attr(node, 'data-window-preview-app')).length, 1);
  assert.deepEqual(all(notes).filter((node) => attr(node, 'data-preview-title')).map((node) => attr(node, 'data-preview-title')), ['Launch checklist', 'Review notes']);
  assert.ok(find(switcher, 'data-command-tab'));
  for (const frame of [44, 65, 87]) {
    const done = moduleFrame('WindowsTourModule', frame);
    assert.equal(find(done, 'data-window-preview-app'), undefined);
    assert.equal(find(done, 'data-command-tab'), undefined);
    assert.equal(attr(find(done, 'data-window-active'), 'data-window-active'), 'Notes');
    assert.match(textOf(done), /Notes window activated/);
  }
});

test('currency and app repair each execute once with their own delayed outcome', () => {
  const {quickActionExamples, quickActionsTourAt} = ui.exports;
  assert.equal(quickActionExamples.length, 2);
  assert.deepEqual(quickActionExamples.map((item) => [item.from, item.duration]), [[0, 88], [88, 112]]);
  for (let frame = 0; frame < 200; frame++) {
    const state = quickActionsTourAt(frame);
    assert.equal(state.repair, frame >= 88);
    assert.equal(state.done, state.frame >= state.example.at);
    assert.ok(state.frame >= 0 && state.frame < state.example.duration);
  }
  assert.doesNotMatch(textOf(moduleFrame('QuickActionsTourModule', 43)), /€18.40 copied/);
  assert.match(textOf(moduleFrame('QuickActionsTourModule', 44)), /€18.40 copied/);
  assert.doesNotMatch(textOf(moduleFrame('QuickActionsTourModule', 88 + 67)), /Studio.app opened after checks/);
  assert.match(textOf(moduleFrame('QuickActionsTourModule', 88 + 75)), /Studio · Launch project.*Studio.app opened after checks/);
  assert.match(textOf(moduleFrame('QuickActionsTourModule', 88 + 58)), /Checking integrity, signature and macOS assessment/);
});

test('Quick Actions use the real top bar, dismiss after execution and repair without a fictional confirmation', () => {
  const currency = moduleFrame('QuickActionsTourModule', 30);
  const toast = find(currency, 'data-quick-action-toast');
  assert.ok(toast);
  const bar = toast.childNodes.find((node) => node.tagName === 'div');
  assert.equal(number(bar, 'top'), 0);
  assert.equal(number(bar, 'left'), 360);
  assert.equal(number(bar, 'width'), 560);
  assert.equal(number(bar, 'height'), 34);
  const menu = find(currency, 'data-quick-action-menu');
  assert.deepEqual(all(menu).filter((node) => attr(node, 'role') === 'menuitem').map(textOf), ['Copy result', 'Copy full expression']);
  const repair = moduleFrame('QuickActionsTourModule', 88 + 38);
  assert.ok(find(repair, 'data-quick-action-toast'));
  assert.match(textOf(find(repair, 'data-quick-action-toast')), /Studio.app.*Repair and open/);
  assert.equal(find(repair, 'data-quick-action-menu'), undefined);
  assert.equal(find(repair, 'role', 'alertdialog'), undefined);
  assert.equal(attr(find(moduleFrame('QuickActionsTourModule', 88 + 6), 'role', 'alertdialog'), 'aria-label'), 'macOS application opening alert');
  for (const frame of [44, 65, 88 + 50, 88 + 68, 199]) {
    const done = moduleFrame('QuickActionsTourModule', frame);
    assert.equal(find(done, 'data-quick-action-toast'), undefined);
    assert.equal(find(done, 'data-quick-action-menu'), undefined);
  }
});

test('Info scrolls smoothly without teleporting, drags within viewport, and exposes settings search and save locations', () => {
  const expected = ['Home', 'Shelf', 'Clipboard', 'Download', 'Weather & Agenda', 'Toolbox', 'Quick Notes', 'AI Info', 'Keyboard Info', 'Mail', 'CPU', 'App Volume Mixer'];
  assert.deepEqual(ui.exports.INFORMATION_TOUR_ORDER, expected);
  const visible = new Set();
  for (let frame = 0; frame < 92; frame++) {
    const state = ui.exports.informationTourAt(frame);
    state.order.forEach((name, index) => {const top = 43 + index * 44 - state.scroll; if (top >= 0 && top + 44 <= 354) visible.add(name);});
    assert.equal(new Set(state.order).size, 12);
    assert.deepEqual(state.order, frame < 50 ? expected : ['AI Info', ...expected.filter((name) => name !== 'AI Info')]);
    if (state.dragging) inside(80, state.dragY, 960, 354);
  }
  assert.deepEqual([...visible].sort(), [...expected].sort());
  // Smooth scroll from feature order to Wellbeing (no 1-frame 1029px teleport).
  let prevScroll = ui.exports.informationTourAt(92).scroll;
  for (let frame = 93; frame <= 114; frame++) {
    const nextScroll = ui.exports.informationTourAt(frame).scroll;
    assert.ok(nextScroll >= prevScroll, `Info scroll moved backwards at ${frame}`);
    assert.ok(nextScroll - prevScroll < 95, `Info scroll jumped by ${nextScroll - prevScroll}px at frame ${frame}`);
    prevScroll = nextScroll;
  }
  const reordered = moduleFrame('InformationTourModule', 68);
  assert.ok(find(reordered, 'data-settings-search'));
  assert.ok(find(reordered, 'data-feature', 'saveLocations'));
  assert.equal(find(reordered, 'data-information-drag'), undefined);
  assert.equal(attr(find(reordered, 'data-information-item'), 'data-information-item'), 'AI Info');
  assert.match(textOf(reordered), /AI Info moved first · Toolbar updated/);
});

test('Wellbeing uses the same Info scroller with native interval fields and Save', () => {
  assert.equal(ui.exports.informationTourAt(111).care, false);
  assert.equal(ui.exports.informationTourAt(112).care, true);
  const care = moduleFrame('InformationTourModule', 130);
  const viewport = find(care, 'data-information-viewport');
  const scroll = find(viewport, 'data-information-scroll');
  const fields = find(care, 'data-feature', 'userCare');
  assert.ok(all(scroll).includes(fields));
  assert.match(textOf(fields), /Wellbeing.*0Hours45Minutes0SecondsSave.*A natural break resets the reminder timer/);
  const translation = Number(style(scroll).transform.match(/translateY\((-?[\d.]+)px\)/)[1]);
  assert.equal(1041 + translation, 12);
  assert.ok(12 + 210 <= number(viewport, 'height'));
});

test('Permissions retain single-column descriptions, states, spinning request loader and native manual settings actions', () => {
  const initial = moduleFrame('PermissionsTourModule', 0);
  const viewport = find(initial, 'data-permission-viewport');
  const list = find(viewport, 'data-permission-scroll');
  assert.match(attr(list, 'class'), /flex-col/);
  assert.match(attr(viewport, 'class'), /overflow-hidden/);
  const cards = all(list).filter((node) => attr(node, 'data-permission'));
  assert.equal(cards.length, 15);
  assert.equal(ui.exports.permissionDemo.find((item) => item.id === 'system_audio').name, 'System Audio');
  assert.equal(ui.exports.permissionDemo.find((item) => item.id === 'files').name, 'File Access');
  const state = ui.exports.permissionsTourAt(24);
  assert.equal(state.scroll, 570);
  const waitingA = moduleFrame('PermissionsTourModule', 48);
  const waitingB = moduleFrame('PermissionsTourModule', 52);
  const spinnerA = all(find(waitingA, 'data-permission', 'microphone')).find((node) => attr(node, 'class')?.includes('lucide-loader-circle'));
  const spinnerB = all(find(waitingB, 'data-permission', 'microphone')).find((node) => attr(node, 'class')?.includes('lucide-loader-circle'));
  assert.ok(spinnerA && spinnerB);
  assert.notEqual(style(spinnerA).transform, style(spinnerB).transform, 'Request spinner must rotate across frames');
  const done = moduleFrame('PermissionsTourModule', 88);
  assert.match(textOf(find(done, 'data-permission', 'microphone')), /Allowed/);
  assert.equal(find(find(done, 'data-permission', 'microphone'), 'data-permission-action'), undefined);
  assert.match(textOf(done), /Microphone permission granted/);
});

test('CLI installation confirms in one modal, reports success and then moves to the native Skills section', () => {
  const before = moduleFrame('ManagementTourModule', 8);
  assert.ok(find(before, 'data-management-section', 'cli'));
  assert.equal(find(before, 'role', 'alertdialog'), undefined);
  const confirmation = moduleFrame('ManagementTourModule', 24);
  const dialog = find(confirmation, 'role', 'alertdialog');
  assert.equal(attr(dialog, 'aria-label'), 'CLI installation confirmation');
  assert.match(textOf(dialog), /Install Gemini\?.*Download and install Gemini CLI.*CancelContinue/);
  const installing = moduleFrame('ManagementTourModule', 32);
  assert.equal(find(installing, 'role', 'alertdialog'), undefined);
  assert.match(textOf(installing), /GeminiInstalling/);
  const installed = moduleFrame('ManagementTourModule', 50);
  assert.match(textOf(installed), /GeminiInstalledUpdate.*Gemini CLI installed/);
  const skills = moduleFrame('ManagementTourModule', 82);
  assert.ok(find(skills, 'data-management-section', 'skills'));
  assert.match(textOf(skills), /Symbolic linksFile copies.*Sync targetsCodexClaudeAgents/);
  assert.match(textOf(moduleFrame('ManagementTourModule', 110)), /Skills synced to enabled CLIs/);
});

test('Settings outcomes remain readable for at least 42 actual frames', () => {
  const counts = {windows: 0, currency: 0, repair: 0, info: 0, permission: 0, paused: 0, installed: 0, synced: 0, opened: 0};
  for (let frame = 0; frame < 956; frame++) {
    const state = scene.exports.settingsTourAt(frame, 956);
    const local = state.frame;
    if (state.step.id === 'windows' && ui.exports.windowsTourAt(local).activated) counts.windows++;
    if (state.step.id === 'quickActions') {const action = ui.exports.quickActionsTourAt(local); if (action.done) counts[action.repair ? 'repair' : 'currency']++;}
    if (state.step.id === 'information') {const info = ui.exports.informationTourAt(local); if (!info.care && local >= 50) counts.info++;}
    if (state.step.id === 'permissions' && ui.exports.permissionsTourAt(local).granted) counts.permission++;
    if (state.step.id === 'lockScreen' && local >= 32) counts.paused++;
    if (state.step.id === 'management') {const cli = ui.exports.managementTourAt(local); if (cli.installed && !cli.skills) counts.installed++; if (cli.synchronized) counts.synced++;}
    if (state.step.id === 'recommended') {const apps = ui.exports.recommendedTourAt(local); if (apps.opened && local < lid.exports.LID_PREVIEW_TIMING.start) counts.opened++;}
  }
  for (const [name, frames] of Object.entries(counts)) assert.ok(frames >= 42, `${name} result lasts only ${frames} actual frames`);
});

test('visible Settings pointers stay inside their local stage or module without duplicate modal pointers', () => {
  for (const [name, frames, width, height] of [
    ['WindowsTourModule', [12, 30, 40], 1280, 720],
    ['QuickActionsTourModule', [10, 28, 38, 108, 126, 134], 1280, 720],
    ['PermissionsTourModule', [24, 34, 48], 1040, 446],
    ['ManagementTourModule', [10, 82, 88], 1040, 446],
    ['LockScreenTourModule', [31, 50], 1280, 720],
  ]) {
    for (const frame of frames) {
      const tree = moduleFrame(name, frame);
      for (const tip of cursor(tree).filter((node) => number(node, 'opacity') > 0)) inside(number(tip, 'left') + 2, number(tip, 'top') + 2, width, height);
    }
  }
  for (const frame of [22, 32, 38, 44, 70]) {
    const tree = recommendedFrame(frame);
    assert.ok(cursor(tree).filter((node) => number(node, 'opacity') > 0).length <= 1);
    for (const tip of cursor(tree).filter((node) => number(node, 'opacity') > 0)) inside(number(tip, 'left') + 2, number(tip, 'top') + 2, 1280, 720);
  }
});
