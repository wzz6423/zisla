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
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 9600}), Img: (props) => React.createElement('img', props)} : require(name);
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
const moduleFrame = (name, frame) => ui.render(ui.exports[name], {frame, globalFrame: 8220 + frame});
const recommendedFrame = (frame) => recommended.render(recommended.exports.RecommendedDesktopTour, {frame});

test('Quick Actions keep a single pointer through source copy, top-bar menu and execution', () => {
  for (let frame = 0; frame < 300; frame++) {
    const tree = moduleFrame('QuickActionsTourModule', frame);
    const visible = cursor(tree).filter((node) => number(node, 'opacity') > 0);
    assert.ok(visible.length <= 1, `Quick Actions frame ${frame} has ${visible.length} visible pointers`);
  }
  assert.equal(ui.exports.quickActionsTourAt(34).menu, false, 'The menu must wait for the more-actions click');
  assert.equal(ui.exports.quickActionsTourAt(39).menu, false);
  assert.equal(ui.exports.quickActionsTourAt(40).menu, true);
  assert.equal(ui.exports.quickActionsTourAt(60).menu, true, 'The clicked menu item must still be present at the click frame');
  assert.equal(ui.exports.quickActionsTourAt(65).menu, true);
  assert.equal(ui.exports.quickActionsTourAt(66).done, true);
  assert.equal(ui.exports.quickActionsTourAt(184).started, false, 'The repair button must still exist at the click frame');
  assert.equal(ui.exports.quickActionsTourAt(189).started, false);
  assert.equal(ui.exports.quickActionsTourAt(190).started, true);
  for (const [frame, copied] of [[23, false], [24, true], [153, false], [154, true]]) assert.equal(ui.exports.quickActionsTourAt(frame).copied, copied);
  for (const [frame, x, y] of [[18, 405, 430], [34, 872.5, 17], [60, 789, 65], [132, 791, 389], [148, 640, 400], [184, 819, 17]]) {
    const tip = cursor(moduleFrame('QuickActionsTourModule', frame)).find((node) => number(node, 'opacity') > 0);
    assert.ok(tip);
    assert.equal(number(tip, 'left') + 2, x);
    assert.equal(number(tip, 'top') + 2, y);
    assert.match(style(tip).transform, /scale\(0\.9\)/);
  }
  for (const [from, data, value] of [[18, 'data-copied-currency'], [34, 'data-quick-action-more'], [60, 'role', 'menuitem'], [132, 'data-repair-alert-ok'], [148, 'data-quick-action-source', 'Studio.app'], [184, 'data-quick-action-primary']]) {
    for (let frame = from; frame < from + 6; frame++) assert.ok(find(moduleFrame('QuickActionsTourModule', frame), data, value), `${data} disappears during the press at frame ${frame}`);
  }
});

test('Quick Action controls remain single-line and reserve the entire physical notch', () => {
  for (const [frame, width, left, label] of [[40, 560, 360, 'Copy result'], [160, 620, 330, 'Repair and open']]) {
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
  const before = moduleFrame('LockScreenTourModule', 37);
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
  const stopped = moduleFrame('LockScreenTourModule', 38);
  for (const frame of [39, 60, 79]) {
    const later = moduleFrame('LockScreenTourModule', frame);
    assert.equal(attr(find(later, 'data-lock-playback-progress'), 'data-elapsed'), attr(find(stopped, 'data-lock-playback-progress'), 'data-elapsed'));
    assert.equal(textOf(find(later, 'data-lock-lyrics')), textOf(find(stopped, 'data-lock-lyrics')));
  }
  assert.equal(attr(find(stopped, 'data-lock-action', 'toggle'), 'aria-label'), 'Play');
  const advanced = ui.exports.lockScreenTourAt(37, 8220);
  assert.ok(advanced.elapsed > ui.exports.lockScreenTourAt(0, 8220).elapsed);
  assert.equal(ui.exports.lockScreenTourAt(79, 8220).elapsed, ui.exports.lockScreenTourAt(38, 8220).elapsed);
  const anchored = ui.render(ui.exports.LockScreenTourModule, {frame: 60, globalFrame: 9999, clockAnchor: 8220});
  assert.equal(attr(find(anchored, 'data-lock-playback-progress'), 'data-elapsed'), String(ui.exports.lockScreenTourAt(60, 8220).elapsed));
});

test('CLI film focuses the demonstrated installation while native source retains uninstall actions', () => {
  const source = readFileSync(new URL('../../mac/Sources/Zisla/AIAgentModuleView.swift', import.meta.url), 'utf8');
  assert.match(source, /commandsForCLIUninstallation\(installedKinds\)/);
  assert.match(source, /commandsForCLIUninstallation\(\[kind\]\)/);
  assert.doesNotMatch(textOf(moduleFrame('ManagementTourModule', 50)), /Uninstall/);
  assert.equal(find(moduleFrame('ManagementTourModule', 12), 'role', 'alertdialog'), undefined);
  assert.equal(find(moduleFrame('ManagementTourModule', 17), 'role', 'alertdialog'), undefined);
  assert.ok(find(moduleFrame('ManagementTourModule', 18), 'role', 'alertdialog'));
  assert.ok(find(moduleFrame('ManagementTourModule', 25), 'data-cli-confirm-submit'));
  assert.ok(find(moduleFrame('ManagementTourModule', 30), 'role', 'alertdialog'));
  assert.equal(find(moduleFrame('ManagementTourModule', 31), 'role', 'alertdialog'), undefined);
  const sync = moduleFrame('ManagementTourModule', 102);
  const syncTip = cursor(sync).find((node) => number(node, 'opacity') > 0);
  assert.ok(syncTip, 'Skills sync must have a pointer at its click frame');
  assert.match(style(syncTip).transform, /scale\(0\.9\)/);
  assert.ok(find(sync, 'data-skills-sync'));
  assert.doesNotMatch(textOf(sync), /Skills synced to enabled CLIs/);
  assert.match(textOf(moduleFrame('ManagementTourModule', 108)), /Skills synced to enabled CLIs/);
  for (let frame = 0; frame < 150; frame++) assert.ok(cursor(moduleFrame('ManagementTourModule', frame)).filter((node) => number(node, 'opacity') > 0).length <= 1, `CLI frame ${frame} has duplicate pointers`);
  for (const [from, data, value, x, y] of [[12, 'data-cli-action', 'Gemini', 952, 262], [25, 'data-cli-confirm-submit', undefined, 354, 126], [102, 'data-skills-sync', undefined, 956, 80]]) {
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
  const list = recommendedFrame(15);
  assert.equal(find(list, 'data-recommended-dock'), undefined, 'A simulated Dock cannot be embedded in Settings');
  assert.match(textOf(find(list, 'data-recommended-section', 'tools')), /OpenScreen.*DockDoor.*Zshell/);
  assert.equal(find(list, 'data-open-quiet-md'), undefined);
  const app = recommendedFrame(45);
  assert.ok(find(app, 'data-recommended-app', 'Zshell'), 'Recommended apps must open in a separate desktop window');
  assert.equal(find(app, 'data-recommended-section'), undefined);
  const applications = recommended.render(recommended.exports.RecommendedDesktopTour, {frame: 30});
  assert.ok(find(applications, 'data-recommended-applications'));
  assert.equal(find(applications, 'data-recommended-app'), undefined);
  const icon = find(applications, 'alt', 'Zshell');
  assert.match(attr(icon, 'src'), /^data:image\/png;base64,/);
  const png = Buffer.from(attr(icon, 'src').split(',')[1], 'base64');
  assert.equal(png.readUInt32BE(16), 128);
  assert.equal(png.readUInt32BE(20), 128);
  assert.ok(find(app, 'data-zshell-projects'));
  assert.ok(find(app, 'data-zshell-terminal'));
  assert.ok(find(app, 'data-zshell-tabs'));
  const snapshot = recommended.render(recommended.exports.ZshellTourDesktop);
  assert.equal(textOf(find(app, 'data-recommended-app')), textOf(find(snapshot, 'data-recommended-app')));
  assert.equal(find(snapshot, 'data-recommended-section'), undefined);
  assert.doesNotMatch(textOf(snapshot), /opened as a separate app/);
  assert.equal(ui.exports.recommendedTourAt(33).opened, false);
  assert.equal(ui.exports.recommendedTourAt(34).opened, true);
  assert.deepEqual(ui.exports.recommendedTourAt(209), {opened: true});
  for (const frame of [34, 77, 107]) {
    const opened = recommendedFrame(frame);
    assert.equal(textOf(find(opened, 'data-recommended-app')), textOf(find(snapshot, 'data-recommended-app')));
    assert.equal(find(opened, 'data-recommended-section'), undefined);
    assert.equal(cursor(opened).length, 0);
  }
});

test('isolated ablations expose delayed actions, notch width, frozen playback and desktop ownership', () => {
  const replace = (before, after) => (source) => {assert.ok(source.includes(before), `Ablation target missing: ${before}`); return source.replace(before, after);};
  const instantCopy = load('src/modules/tour/SettingsTourModule.tsx', replace('localFrame >= (repair ? 34 : 24)', 'localFrame >= (repair ? 28 : 18)'));
  assert.notEqual(instantCopy.exports.quickActionsTourAt(23).copied, ui.exports.quickActionsTourAt(23).copied);
  const instantMenu = load('src/modules/tour/SettingsTourModule.tsx', replace('localFrame >= 40 && localFrame < example.at', 'localFrame >= 34 && localFrame < example.at'));
  assert.notEqual(instantMenu.exports.quickActionsTourAt(34).menu, ui.exports.quickActionsTourAt(34).menu);
  const instantRepair = load('src/modules/tour/SettingsTourModule.tsx', replace('repair && localFrame >= 70', 'repair && localFrame >= 64'));
  assert.notEqual(instantRepair.exports.quickActionsTourAt(184).started, ui.exports.quickActionsTourAt(184).started);
  const narrower = load('src/modules/tour/SettingsTourModule.tsx', replace('width: state.repair ? 620 : 560', 'width: 560'));
  const narrowToast = find(narrower.render(narrower.exports.QuickActionsTourModule, {frame: 160}), 'data-quick-action-toast');
  assert.notEqual(number(narrowToast.childNodes.find((node) => node.tagName === 'div'), 'width'), 620);
  const unfrozen = load('src/modules/tour/SettingsTourModule.tsx', replace('Math.min(frame, 38)', 'frame'));
  assert.notEqual(unfrozen.exports.lockScreenTourAt(60, 8220).elapsed, ui.exports.lockScreenTourAt(60, 8220).elapsed);
  const unanchored = load('src/modules/tour/SettingsTourModule.tsx', replace('clockAnchor = globalFrame - frame', 'clockAnchor = globalFrame'));
  const noAnchor = unanchored.render(unanchored.exports.LockScreenTourModule, {frame: 60, globalFrame: 8280});
  assert.notEqual(attr(find(noAnchor, 'data-lock-playback-progress'), 'data-elapsed'), String(ui.exports.lockScreenTourAt(60, 8220).elapsed));
  const instantConfirmation = load('src/modules/tour/SettingsTourModule.tsx', replace('confirmation: frame >= 18 && frame < 31', 'confirmation: frame >= 12 && frame < 31'));
  assert.equal(instantConfirmation.exports.managementTourAt(12).confirmation, true);
  assert.equal(ui.exports.managementTourAt(12).confirmation, false);
  const instantInstall = load('src/modules/tour/SettingsTourModule.tsx', replace('confirmation: frame >= 18 && frame < 31', 'confirmation: frame >= 18 && frame < 25'));
  assert.equal(instantInstall.exports.managementTourAt(25).confirmation, false);
  assert.equal(ui.exports.managementTourAt(25).confirmation, true);
  const lateSync = load('src/modules/tour/SettingsTourModule.tsx', replace('TourPointer, { frame, at: 102, x: 956, y: 80 }', 'TourPointer, { frame, at: 108, x: 956, y: 80 }'));
  const syncTip = cursor(lateSync.render(lateSync.exports.ManagementTourModule, {frame: 102})).find((node) => number(node, 'opacity') > 0);
  assert.equal(style(syncTip).transform, 'scale(1)');
  const openedEarly = load('src/modules/tour/RecommendedDesktopTour.tsx', replace('opened: frame >= 34', 'opened: frame >= 28'));
  assert.equal(find(openedEarly.render(openedEarly.exports.RecommendedDesktopTour, {frame: 30}), 'data-recommended-applications'), undefined);
  const withoutApplications = load('src/modules/tour/RecommendedDesktopTour.tsx', replace('if (frame < 24)', 'if (frame < 34)'));
  assert.equal(find(withoutApplications.render(withoutApplications.exports.RecommendedDesktopTour, {frame: 30}), 'data-recommended-applications'), undefined);
  const missingDesktop = load('src/modules/tour/RecommendedDesktopTour.tsx', (source) => {
    const replaced = source.replace(/state\.opened \?[^\n]*?jsx\)\(ZshellTourDesktop, \{\}\)/, 'state.opened ? null');
    assert.notEqual(replaced, source);
    return replaced;
  });
  assert.equal(find(missingDesktop.render(missingDesktop.exports.RecommendedDesktopTour, {frame: 45}), 'data-zshell-desktop'), undefined);
});

test('Settings covers the shortened timeline once and keeps fractional-frame boundaries continuous', () => {
  const {SETTINGS_TOUR_DURATION, SETTINGS_TOUR_STEPS, settingsTourAt} = scene.exports;
  assert.equal(SETTINGS_TOUR_DURATION, 1140);
  assert.deepEqual(SETTINGS_TOUR_STEPS.map((step) => step.id), ['windows', 'quickActions', 'information', 'permissions', 'lockScreen', 'management', 'recommended']);
  let end = 0;
  for (const step of SETTINGS_TOUR_STEPS) {assert.equal(step.from, end); end += step.duration;}
  assert.equal(end, SETTINGS_TOUR_DURATION);
  const seen = [];
  let previous;
  for (let frame = 0; frame < 1156; frame++) {
    const state = settingsTourAt(frame, 1156);
    assert.ok(state.frame >= 0 && state.frame < state.step.duration);
    if (!previous || state.step.id !== previous.step.id) seen.push(state.step.id);
    else assert.ok(state.frame > previous.frame);
    previous = state;
  }
  assert.deepEqual(seen, SETTINGS_TOUR_STEPS.map((step) => step.id));
  assert.equal(settingsTourAt(-10, 1156).frame, 0);
  assert.equal(settingsTourAt(1155, 1156).frame, 209);
  assert.deepEqual(settingsTourAt(2000, 1156), settingsTourAt(1155, 1156));
  for (const local of [40, 100 + 85, 100 + 270, 700 + 60]) {
    const rendered = scene.render(scene.exports.SceneSettings, {duration: 1156}, local * 1155 / 1139);
    assert.ok(!all(rendered).some((node) => number(node, 'width') === 1040 && number(node, 'height') === 446), 'Desktop and lock-screen demonstrations cannot be trapped in the Settings card');
  }
});

test('Dock and Command-Tab preview only one selected app and close on activation', () => {
  const dock = moduleFrame('WindowsTourModule', 18);
  const dockPreview = find(dock, 'data-window-preview-app', 'Safari');
  assert.ok(dockPreview);
  assert.equal(attr(dockPreview, 'data-preview-source'), 'dock');
  assert.deepEqual(all(dockPreview).filter((node) => attr(node, 'data-preview-title')).map((node) => attr(node, 'data-preview-title')), ['Launch review', 'Documentation']);
  assert.match(textOf(dockPreview), /^Safari/);
  const switcher = moduleFrame('WindowsTourModule', 40);
  const notes = find(switcher, 'data-window-preview-app', 'Notes');
  assert.ok(notes);
  assert.equal(attr(notes, 'data-preview-source'), 'switcher');
  assert.equal(all(switcher).filter((node) => attr(node, 'data-window-preview-app')).length, 1);
  assert.deepEqual(all(notes).filter((node) => attr(node, 'data-preview-title')).map((node) => attr(node, 'data-preview-title')), ['Launch checklist', 'Review notes']);
  assert.doesNotMatch(textOf(notes), /Safari|Documentation|Notes/);
  assert.ok(find(switcher, 'data-command-tab'));
  for (const frame of [58, 75, 99]) {
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
  assert.deepEqual(quickActionExamples.map((item) => [item.from, item.duration]), [[0, 120], [120, 180]]);
  for (let frame = 0; frame < 300; frame++) {
    const state = quickActionsTourAt(frame);
    assert.equal(state.repair, frame >= 120);
    assert.equal(state.done, state.frame >= state.example.at);
    assert.ok(state.frame >= 0 && state.frame < state.example.duration);
  }
  assert.equal(quickActionsTourAt(119).repair, false);
  assert.equal(quickActionsTourAt(120).frame, 0);
  assert.deepEqual(quickActionsTourAt(-10), quickActionsTourAt(0));
  assert.deepEqual(quickActionsTourAt(400), quickActionsTourAt(299));
  assert.doesNotMatch(textOf(moduleFrame('QuickActionsTourModule', 65)), /€18.40 copied/);
  assert.match(textOf(moduleFrame('QuickActionsTourModule', 66)), /€18.40 copied/);
  assert.doesNotMatch(textOf(moduleFrame('QuickActionsTourModule', 239)), /Studio.app opened after checks/);
  assert.match(textOf(moduleFrame('QuickActionsTourModule', 270)), /Studio · Launch project.*Studio.app opened after checks/);
  assert.match(textOf(moduleFrame('QuickActionsTourModule', 210)), /Checking integrity, signature and macOS assessment/);
});

test('Quick Actions use the real top bar, dismiss after execution and repair without a fictional confirmation', () => {
  const currency = moduleFrame('QuickActionsTourModule', 40);
  const toast = find(currency, 'data-quick-action-toast');
  assert.ok(toast);
  const bar = toast.childNodes.find((node) => node.tagName === 'div');
  assert.equal(number(bar, 'top'), 0);
  assert.equal(number(bar, 'left'), 360);
  assert.equal(number(bar, 'width'), 560);
  assert.equal(number(bar, 'height'), 34);
  const menu = find(currency, 'data-quick-action-menu');
  assert.deepEqual(all(menu).filter((node) => attr(node, 'role') === 'menuitem').map(textOf), ['Copy result', 'Copy full expression']);
  const repair = moduleFrame('QuickActionsTourModule', 160);
  assert.ok(find(repair, 'data-quick-action-toast'));
  assert.match(textOf(find(repair, 'data-quick-action-toast')), /Studio.app.*Repair and open/);
  assert.equal(find(repair, 'data-quick-action-menu'), undefined);
  assert.equal(find(repair, 'role', 'alertdialog'), undefined);
  assert.doesNotMatch(textOf(repair), /Show in Finder|Confirm|Continue|Remove quarantine\?/);
  assert.deepEqual(ui.exports.quickActionExamples[1].options, ['Repair and open']);
  assert.equal(attr(find(moduleFrame('QuickActionsTourModule', 125), 'role', 'alertdialog'), 'aria-label'), 'macOS application opening alert');
  for (const frame of [66, 85, 190, 210, 240, 270, 299]) {
    const done = moduleFrame('QuickActionsTourModule', frame);
    assert.equal(find(done, 'data-quick-action-toast'), undefined);
    assert.equal(find(done, 'data-quick-action-menu'), undefined);
  }
});

test('Info scrolls all twelve native modules, drags within the viewport and reorders only once', () => {
  const expected = ['Home', 'Shelf', 'Clipboard', 'Download', 'Weather & Agenda', 'Toolbox', 'Quick Notes', 'AI Info', 'Keyboard Info', 'Mail', 'CPU', 'App Volume Mixer'];
  assert.deepEqual(ui.exports.INFORMATION_TOUR_ORDER, expected);
  const visible = new Set();
  for (let frame = 0; frame < 114; frame++) {
    const state = ui.exports.informationTourAt(frame);
    state.order.forEach((name, index) => {const top = 43 + index * 44 - state.scroll; if (top >= 0 && top + 44 <= 354) visible.add(name);});
    assert.equal(new Set(state.order).size, 12);
    assert.deepEqual(state.order, frame < 72 ? expected : ['AI Info', ...expected.filter((name) => name !== 'AI Info')]);
    if (state.dragging) inside(80, state.dragY, 960, 354);
  }
  assert.deepEqual([...visible].sort(), [...expected].sort());
  for (const frame of [48, 60, 71]) {
    const tree = moduleFrame('InformationTourModule', frame);
    const viewport = find(tree, 'data-information-viewport');
    const ghost = find(tree, 'data-information-drag');
    assert.ok(ghost);
    assert.equal(number(viewport, 'height'), 354);
    assert.match(attr(viewport, 'class'), /overflow-hidden/);
    assert.equal(style(ghost).width, '100%');
    assert.equal(style(ghost)['box-sizing'], 'border-box');
    assert.ok(number(ghost, 'top') >= 0 && number(ghost, 'top') + number(ghost, 'height') <= 354);
    const pointer = cursor(viewport);
    assert.equal(pointer.length, 1);
    inside(number(pointer[0], 'left') + 2, number(pointer[0], 'top') + 2, 960, 354);
  }
  const reordered = moduleFrame('InformationTourModule', 90);
  assert.equal(find(reordered, 'data-information-drag'), undefined);
  assert.equal(attr(find(reordered, 'data-information-item'), 'data-information-item'), 'AI Info');
  assert.match(textOf(reordered), /AI Info moved first · Toolbar updated/);
});

test('Wellbeing uses the same Info scroller with native interval fields and Save', () => {
  assert.equal(ui.exports.informationTourAt(113).care, false);
  assert.equal(ui.exports.informationTourAt(114).care, true);
  const care = moduleFrame('InformationTourModule', 135);
  const viewport = find(care, 'data-information-viewport');
  const scroll = find(viewport, 'data-information-scroll');
  const fields = find(care, 'data-feature', 'userCare');
  assert.ok(all(scroll).includes(fields));
  assert.equal(all(care).filter((node) => attr(node, 'data-information-viewport') !== undefined).length, 1);
  assert.equal(all(care).filter((node) => attr(node, 'data-feature') === 'userCare').length, 1);
  assert.match(textOf(fields), /Wellbeing.*0Hours45Minutes0SecondsSave.*A natural break resets the reminder timer/);
  assert.doesNotMatch(textOf(care), /AI Info moved first/);
  const translation = Number(style(scroll).transform.match(/translateY\((-?[\d.]+)px\)/)[1]);
  assert.equal(1041 + translation, 12);
  assert.ok(12 + 210 <= number(viewport, 'height'));
});

test('Permissions retain single-column descriptions, states and native manual settings actions', () => {
  const initial = moduleFrame('PermissionsTourModule', 0);
  const viewport = find(initial, 'data-permission-viewport');
  const list = find(viewport, 'data-permission-scroll');
  assert.match(attr(list, 'class'), /flex-col/);
  assert.match(attr(viewport, 'class'), /overflow-hidden/);
  const cards = all(list).filter((node) => attr(node, 'data-permission'));
  assert.equal(cards.length, 15);
  assert.equal(ui.exports.permissionDemo.find((item) => item.id === 'system_audio').name, 'System Audio');
  assert.equal(ui.exports.permissionDemo.find((item) => item.id === 'files').name, 'File Access');
  for (const permission of ui.exports.permissionDemo) {
    const card = find(initial, 'data-permission', permission.id);
    assert.ok(textOf(card).includes(permission.name));
    assert.ok(textOf(card).includes(permission.body));
    assert.equal(number(card, 'height'), 138);
    if (permission.manual) {
      assert.match(textOf(card), /Enable in System Settings.*Open System Settings/);
      assert.doesNotMatch(textOf(card), /Allowed/);
    } else if (permission.id !== 'microphone') {
      assert.match(textOf(card), /Allowed/);
      assert.equal(find(card, 'data-permission-action'), undefined);
    }
  }
  assert.doesNotMatch(textOf(initial), /Feature enabled|Files & Folders|System Audio Recording/);
  for (const node of all(initial)) assert.notEqual(attr(node, 'role'), 'switch');
});

test('Microphone permission scrolls into view, requests before granting and removes its action afterward', () => {
  const state = ui.exports.permissionsTourAt(32);
  assert.equal(state.scroll, 570);
  assert.ok(4 * 150 - state.scroll >= 0 && 4 * 150 + 138 - state.scroll <= 337);
  assert.equal(ui.exports.permissionsTourAt(43).requesting, false);
  assert.equal(ui.exports.permissionsTourAt(44).requesting, true);
  assert.equal(ui.exports.permissionsTourAt(82).granted, false);
  const waiting = moduleFrame('PermissionsTourModule', 60);
  const microphone = find(waiting, 'data-permission', 'microphone');
  assert.match(textOf(microphone), /Requesting…Allow/);
  assert.ok(all(find(microphone, 'data-permission-action')).some((node) => attr(node, 'class')?.includes('lucide-loader-circle')));
  assert.doesNotMatch(textOf(waiting), /Microphone permission granted/);
  const done = moduleFrame('PermissionsTourModule', 110);
  assert.match(textOf(find(done, 'data-permission', 'microphone')), /Allowed/);
  assert.equal(find(find(done, 'data-permission', 'microphone'), 'data-permission-action'), undefined);
  assert.match(textOf(done), /Microphone permission granted/);
  for (const permission of ui.exports.permissionDemo.filter((item) => item.manual)) assert.doesNotMatch(textOf(find(done, 'data-permission', permission.id)), /Allowed/);
});

test('CLI installation confirms in one modal, reports success and then moves to the native Skills section', () => {
  const before = moduleFrame('ManagementTourModule', 10);
  assert.ok(find(before, 'data-management-section', 'cli'));
  assert.equal(find(before, 'role', 'alertdialog'), undefined);
  const confirmation = moduleFrame('ManagementTourModule', 30);
  const dialog = find(confirmation, 'role', 'alertdialog');
  assert.equal(attr(dialog, 'aria-label'), 'CLI installation confirmation');
  assert.match(textOf(dialog), /Install Gemini\?.*Download and install Gemini CLI.*CancelContinue/);
  assert.equal(cursor(confirmation).length, 1, 'The modal must own the only pointer');
  const tip = cursor(dialog)[0];
  assert.ok(tip);
  inside(number(tip, 'left') + 2, number(tip, 'top') + 2, number(dialog, 'width'), 161);
  const installing = moduleFrame('ManagementTourModule', 39);
  assert.equal(find(installing, 'role', 'alertdialog'), undefined);
  assert.match(textOf(installing), /GeminiInstalling/);
  assert.doesNotMatch(textOf(installing), /Gemini CLI installed/);
  const installed = moduleFrame('ManagementTourModule', 50);
  assert.match(textOf(installed), /GeminiInstalledUpdate.*Gemini CLI installed/);
  assert.equal(find(installed, 'data-management-section', 'skills'), undefined);
  const skills = moduleFrame('ManagementTourModule', 95);
  assert.ok(find(skills, 'data-management-section', 'skills'));
  assert.equal(find(skills, 'data-management-section', 'cli'), undefined);
  assert.match(textOf(skills), /Symbolic linksFile copies.*Sync targetsCodexClaudeAgents/);
  assert.doesNotMatch(textOf(skills), /Gemini CLI installed|Pi|Gemini/);
  assert.doesNotMatch(textOf(skills), /Skills synced to enabled CLIs/);
  assert.match(textOf(moduleFrame('ManagementTourModule', 130)), /Skills synced to enabled CLIs/);
});

test('Recommended tools show native management controls and open a separate Zshell application', () => {
  const tools = recommendedFrame(15);
  const list = find(tools, 'data-recommended-section', 'tools');
  assert.match(textOf(list), /Desktop applications.*OpenScreen.*DockDoor.*Zshell/);
  assert.ok(find(list, 'aria-label', 'Detect recommended tools'));
  assert.ok(find(list, 'aria-label', 'Install missing tools'));
  assert.ok(find(list, 'aria-label', 'Update installed tools'));
  assert.doesNotMatch(textOf(list), /Open app|InstalledOpen|Launch app/);
  assert.equal(find(tools, 'data-recommended-dock'), undefined);
  assert.ok(find(recommendedFrame(30), 'data-open-zshell'));
  const app = recommendedFrame(45);
  assert.ok(find(app, 'data-recommended-app', 'Zshell'));
  assert.equal(find(app, 'data-recommended-section'), undefined);
  assert.match(textOf(app), /Zshell.*launch-project.*zsh.*Zshell opened as a separate app/s);
});

test('Settings outcomes remain readable for at least 42 actual frames after the timeline squeeze', () => {
  const counts = {windows: 0, currency: 0, repair: 0, info: 0, permission: 0, paused: 0, installed: 0, synced: 0, opened: 0};
  for (let frame = 0; frame < 1156; frame++) {
    const state = scene.exports.settingsTourAt(frame, 1156);
    const local = state.frame;
    if (state.step.id === 'windows' && ui.exports.windowsTourAt(local).activated) counts.windows++;
    if (state.step.id === 'quickActions') {const action = ui.exports.quickActionsTourAt(local); if (action.done) counts[action.repair ? 'repair' : 'currency']++;}
    if (state.step.id === 'information') {const info = ui.exports.informationTourAt(local); if (!info.care && local >= 72) counts.info++;}
    if (state.step.id === 'permissions' && ui.exports.permissionsTourAt(local).granted) counts.permission++;
    if (state.step.id === 'lockScreen' && local >= 38) counts.paused++;
    if (state.step.id === 'management') {const cli = ui.exports.managementTourAt(local); if (cli.installed && !cli.skills) counts.installed++; if (cli.synchronized) counts.synced++;}
    if (state.step.id === 'recommended') {const apps = ui.exports.recommendedTourAt(local); if (apps.opened && local < lid.exports.LID_PREVIEW_TIMING.start) counts.opened++;}
  }
  for (const [name, frames] of Object.entries(counts)) assert.ok(frames >= 42, `${name} result lasts only ${frames} actual frames`);
  assert.match(textOf(moduleFrame('LockScreenTourModule', 60)), /Playback paused/);
  assert.doesNotMatch(textOf(moduleFrame('LockScreenTourModule', 37)), /Playback paused/);
});

test('visible Settings pointers stay inside their local stage or module without duplicate modal pointers', () => {
  for (const [name, frames, width, height] of [
    ['WindowsTourModule', [18, 40, 54], 1280, 720],
    ['QuickActionsTourModule', [18, 40, 59, 148, 160, 183], 1280, 720],
    ['PermissionsTourModule', [32, 44, 60], 1040, 446],
    ['ManagementTourModule', [10, 95, 107], 1040, 446],
    ['LockScreenTourModule', [37, 60], 1280, 720],
  ]) {
    for (const frame of frames) {
      const tree = moduleFrame(name, frame);
      for (const tip of cursor(tree).filter((node) => number(node, 'opacity') > 0)) inside(number(tip, 'left') + 2, number(tip, 'top') + 2, width, height);
    }
  }
  for (const frame of [24, 28, 33, 45, 77]) {
    const tree = recommendedFrame(frame);
    assert.ok(cursor(tree).filter((node) => number(node, 'opacity') > 0).length <= 1);
    for (const tip of cursor(tree).filter((node) => number(node, 'opacity') > 0)) inside(number(tip, 'left') + 2, number(tip, 'top') + 2, 1280, 720);
  }
});
