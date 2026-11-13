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
const moduleFrame = (name, frame) => ui.render(ui.exports[name], {frame, globalFrame: 8220 + frame});

test('Settings covers the shortened timeline once and keeps fractional-frame boundaries continuous', () => {
  const {SETTINGS_TOUR_DURATION, SETTINGS_TOUR_STEPS, settingsTourAt} = scene.exports;
  assert.equal(SETTINGS_TOUR_DURATION, 1080);
  assert.deepEqual(SETTINGS_TOUR_STEPS.map((step) => step.id), ['windows', 'quickActions', 'information', 'permissions', 'lockScreen', 'management', 'recommended']);
  let end = 0;
  for (const step of SETTINGS_TOUR_STEPS) {assert.equal(step.from, end); end += step.duration;}
  assert.equal(end, SETTINGS_TOUR_DURATION);
  const seen = [];
  let previous;
  for (let frame = 0; frame < 1096; frame++) {
    const state = settingsTourAt(frame, 1096);
    assert.ok(state.frame >= 0 && state.frame < state.step.duration);
    if (!previous || state.step.id !== previous.step.id) seen.push(state.step.id);
    else assert.ok(state.frame > previous.frame);
    previous = state;
  }
  assert.deepEqual(seen, SETTINGS_TOUR_STEPS.map((step) => step.id));
  assert.equal(settingsTourAt(-10, 1096).frame, 0);
  assert.equal(settingsTourAt(1095, 1096).frame, 149);
  assert.deepEqual(settingsTourAt(2000, 1096), settingsTourAt(1095, 1096));
  for (const local of [40, 100 + 85, 100 + 270, 700 + 60]) {
    const rendered = scene.render(scene.exports.SceneSettings, {duration: 1096}, local * 1095 / 1079);
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
  for (const frame of [55, 75, 99]) {
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
  assert.doesNotMatch(textOf(moduleFrame('QuickActionsTourModule', 59)), /€18.40 copied/);
  assert.match(textOf(moduleFrame('QuickActionsTourModule', 60)), /€18.40 copied/);
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
  for (const frame of [60, 85, 184, 210, 240, 270, 299]) {
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
  const installing = moduleFrame('ManagementTourModule', 35);
  assert.equal(find(installing, 'role', 'alertdialog'), undefined);
  assert.match(textOf(installing), /GeminiInstalling/);
  assert.doesNotMatch(textOf(installing), /Gemini CLI installed/);
  const installed = moduleFrame('ManagementTourModule', 50);
  assert.match(textOf(installed), /GeminiInstalledUpdateUninstall.*Gemini CLI installed/);
  assert.equal(find(installed, 'data-management-section', 'skills'), undefined);
  const skills = moduleFrame('ManagementTourModule', 95);
  assert.ok(find(skills, 'data-management-section', 'skills'));
  assert.equal(find(skills, 'data-management-section', 'cli'), undefined);
  assert.match(textOf(skills), /Symbolic linksFile copies.*Sync targetsCodexClaudeAgents/);
  assert.doesNotMatch(textOf(skills), /Gemini CLI installed|Pi|Gemini/);
  assert.doesNotMatch(textOf(skills), /Skills synced to enabled CLIs/);
  assert.match(textOf(moduleFrame('ManagementTourModule', 130)), /Skills synced to enabled CLIs/);
});

test('Recommended tools open a separate app from the Dock and Features owns the lid preview', () => {
  const tools = moduleFrame('RecommendedTourModule', 15);
  const list = find(tools, 'data-recommended-section', 'tools');
  assert.match(textOf(list), /DetectInstall missingUpdate installed.*OpenScreen.*DockDoor.*Quiet.md/);
  assert.doesNotMatch(textOf(list), /Open app|InstalledOpen|Launch app/);
  assert.ok(find(tools, 'data-open-quiet-md'));
  const app = moduleFrame('RecommendedTourModule', 45);
  assert.ok(find(app, 'data-recommended-app', 'Quiet.md'));
  assert.equal(find(app, 'data-recommended-section'), undefined);
  assert.match(textOf(app), /Quiet.md · Launch checklist.*Quiet.md opened as a separate app/s);
  const preview = moduleFrame('RecommendedTourModule', 90);
  assert.ok(find(preview, 'data-recommended-section', 'features'));
  assert.equal(find(preview, 'data-recommended-app'), undefined);
  assert.match(textOf(preview), /Lid-close animation.*Preview animationPreview/);
  const depth = find(preview, 'data-lid-preview');
  assert.ok(Number(style(depth).transform.match(/rotateX\(([\d.]+)deg\)/)[1]) > 0);
  const done = moduleFrame('RecommendedTourModule', 130);
  assert.equal(style(find(done, 'data-lid-preview')).transform, 'rotateX(0deg)');
  assert.equal(number(find(done, 'data-lid-preview'), 'opacity'), 1);
  assert.match(textOf(done), /Preview ended · Desktop restored/);
  assert.doesNotMatch(textOf(done), /Quiet.md opened/);
});

test('Settings outcomes remain readable for at least 42 actual frames after the timeline squeeze', () => {
  const counts = {windows: 0, currency: 0, repair: 0, info: 0, permission: 0, paused: 0, installed: 0, synced: 0, opened: 0, restored: 0};
  for (let frame = 0; frame < 1096; frame++) {
    const state = scene.exports.settingsTourAt(frame, 1096);
    const local = state.frame;
    if (state.step.id === 'windows' && ui.exports.windowsTourAt(local).activated) counts.windows++;
    if (state.step.id === 'quickActions') {const action = ui.exports.quickActionsTourAt(local); if (action.done) counts[action.repair ? 'repair' : 'currency']++;}
    if (state.step.id === 'information') {const info = ui.exports.informationTourAt(local); if (!info.care && local >= 72) counts.info++;}
    if (state.step.id === 'permissions' && ui.exports.permissionsTourAt(local).granted) counts.permission++;
    if (state.step.id === 'lockScreen' && local >= 38) counts.paused++;
    if (state.step.id === 'management') {const cli = ui.exports.managementTourAt(local); if (cli.installed && !cli.skills) counts.installed++; if (cli.synchronized) counts.synced++;}
    if (state.step.id === 'recommended') {const apps = ui.exports.recommendedTourAt(local); if (apps.opened && !apps.features) counts.opened++; if (apps.restored) counts.restored++;}
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
    ['RecommendedTourModule', [15, 70, 90], 1040, 446],
    ['LockScreenTourModule', [37, 60], 1280, 720],
  ]) {
    for (const frame of frames) {
      const tree = moduleFrame(name, frame);
      for (const tip of cursor(tree).filter((node) => number(node, 'opacity') > 0)) inside(number(tip, 'left') + 2, number(tip, 'top') + 2, width, height);
    }
  }
});
