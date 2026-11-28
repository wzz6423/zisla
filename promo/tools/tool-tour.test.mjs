import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';
import {parseFragment} from 'parse5';
import {TOTAL_FRAMES} from '../src/timeline.ts';

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));

const load = (entryPoint) => {
  const clock = {frame: 0};
  const bundle = buildSync({absWorkingDir: root, entryPoints: [entryPoint], bundle: true, packages: 'external', platform: 'node', format: 'cjs', jsx: 'automatic', write: false, loader: {'.svg': 'dataurl', '.png': 'dataurl'}});
  const module = {exports: {}};
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: TOTAL_FRAMES}), Img: (props) => React.createElement('img', props)} : require(name);
  new Function('require', 'module', 'exports', bundle.outputFiles[0].text)(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props = {}, frame = 0) => {clock.frame = frame; return renderToStaticMarkup(React.createElement(Component, props));}};
};

const textOf = (html) => {
  const textContent = (node) => node.nodeName === '#text' ? node.value : (node.childNodes ?? []).map(textContent).join('');
  return textContent(parseFragment(html));
};

test('tour groups cover the budget and keep their final result during a crossfade', () => {
  for (const [source, prefix] of [['SceneEveryday', 'EVERYDAY'], ['SceneDesktopTools', 'DESKTOP'], ['SceneSettings', 'SETTINGS']]) {
    const ui = load(`src/scenes/${source}.tsx`);
    const steps = ui.exports[`${prefix}_TOUR_STEPS`];
    const nominal = ui.exports[`${prefix}_TOUR_DURATION`];
    const at = ui.exports[{EVERYDAY: 'everydayTourAt', DESKTOP: 'desktopTourAt', SETTINGS: 'settingsTourAt'}[prefix]];
    assert.equal(steps[0].from, 0);
    for (let index = 1; index < steps.length; index++) assert.equal(steps[index].from, steps[index - 1].from + steps[index - 1].duration);
    assert.equal(steps.at(-1).from + steps.at(-1).duration, nominal);
    assert.equal(at(-1).step.id, steps[0].id);
    for (const duration of [nominal, nominal + 16, nominal * 2]) {
      for (const step of steps) {
        const midpoint = step.from + Math.floor(step.duration / 2);
        const expanded = at(midpoint * (duration - 1) / (nominal - 1), duration);
        assert.equal(expanded.step.id, step.id);
        assert.ok(Math.abs(expanded.frame - (midpoint - step.from)) < 0.001);
      }
      assert.equal(at(-1, duration).frame, 0);
      const final = at(duration - 1, duration);
      assert.equal(final.step.id, steps.at(-1).id);
      assert.equal(final.frame, steps.at(-1).duration - 1);
      assert.equal(at(duration + 16, duration).frame, final.frame);
      assert.ok(textOf(ui.render(ui.exports[source], {duration}, duration - 1)).length > 200);
    }
  }
});

test('Notes, clipboard and agenda show their saved or completed outcomes', () => {
  const ui = load('src/modules/tour/EverydayTourModule.tsx');
  assert.doesNotMatch(textOf(ui.render(ui.exports.NotesTourModule, {frame: 50})), /Saved to Apple Notes/);
  assert.match(textOf(ui.render(ui.exports.NotesTourModule, {frame: 120})), /Saved to Apple Notes/);
  assert.match(textOf(ui.render(ui.exports.ClipboardTourModule, {frame: 130})), /Copied to clipboard/);
  const agenda = textOf(ui.render(ui.exports.AgendaTourModule, {frame: 110}));
  for (const text of ['Kyoto', 'Lisbon', 'Tromsø', 'Calendar and reminders', 'Reminder completed']) assert.ok(agenda.includes(text), text);
});

test('a context note preserves its text, screenshot and reminder after saving', () => {
  const ui = load('src/modules/tour/EverydayTourModule.tsx');
  const before = textOf(ui.render(ui.exports.ContextNotesTourModule, {frame: 10}));
  const after = textOf(ui.render(ui.exports.ContextNotesTourModule, {frame: 120}));
  assert.ok(!before.includes(ui.exports.everydayDemo.context.text));
  for (const text of [ui.exports.everydayDemo.context.text, 'Every 3 hours', 'Window screenshot', 'Copy screenshot', 'Saved · Shown when you return']) assert.ok(after.includes(text), text);
});

test('briefing previews all eight templates and shows PNG output only after export', () => {
  const ui = load('src/modules/tour/EverydayTourModule.tsx');
  assert.equal(ui.exports.briefingTemplates.length, 8);
  const preview = textOf(ui.render(ui.exports.BriefingTourModule, {frame: 65}));
  for (const template of ui.exports.briefingTemplates) assert.ok(preview.includes(template.title));
  assert.doesNotMatch(preview, /Saved: Daily briefing/);
  assert.match(textOf(ui.render(ui.exports.BriefingTourModule, {frame: 92})), /Exporting PNG/);
  assert.match(textOf(ui.render(ui.exports.BriefingTourModule, {frame: 130})), /Saved: Daily briefing — Nov 11.png/);
});

test('voice transitions from settings through compact recording to one inserted transcript', () => {
  const ui = load('src/modules/tour/EverydayTourModule.tsx');
  const settings = textOf(ui.render(ui.exports.VoiceTourModule, {frame: 20, globalFrame: 3700}));
  assert.match(settings, /Hold to talk/);
  assert.match(settings, /LM Studio/);
  for (const vocabulary of ui.exports.voiceVocabularies) assert.ok(settings.includes(vocabulary));
  const recording = textOf(ui.render(ui.exports.VoiceTourModule, {frame: 66, globalFrame: 3746}));
  assert.match(recording, /Recording · Release to finish/);
  assert.doesNotMatch(recording, /Settings.*Voice input|Recognition vocabulary/);
  assert.match(textOf(ui.render(ui.exports.VoiceTourModule, {frame: 94, globalFrame: 3774})), /Cleaning the transcript/);
  const done = textOf(ui.render(ui.exports.VoiceTourModule, {frame: 130, globalFrame: 3810}));
  assert.ok(done.includes(ui.exports.everydayDemo.voice.cleaned));
  assert.match(done, /Cleaned transcript inserted/);
});

test('mixer changes Safari volume while muting only Music', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  const before = textOf(ui.render(ui.exports.MixerTourModule, {frame: 0}));
  assert.match(before, /Safari100%/);
  const after = textOf(ui.render(ui.exports.MixerTourModule, {frame: 90}));
  const scene = load('src/scenes/SceneDesktopTools.tsx');
  assert.match(after, /Safari30%/);
  assert.match(after, /Music80%/);
  assert.match(textOf(scene.render(scene.exports.SceneDesktopTools, {}, 90)), /Safari at 30% · Music muted/);
});

test('keyboard counts and native focus controls follow visible actions', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  const start = textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 0}));
  assert.match(start, /Holy Panda/);
  assert.doesNotMatch(start, /12,846/);
  assert.match(textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 54})), /12,846/);
  const after = textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 110}));
  assert.match(textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 40})), /custom pack/);
  assert.match(after, /12,860/);
  const scene = load('src/scenes/SceneDesktopTools.tsx');
  assert.match(textOf(scene.render(scene.exports.SceneDesktopTools, {}, 110 + 115)), /14 characters added/);
  const paused = textOf(ui.render(ui.exports.FocusTourModule, {frame: 75}));
  assert.ok(paused.includes('Continue'));
  assert.equal(ui.exports.focusTourAt(75).remaining, 1.3);
  assert.equal(Math.ceil(ui.exports.focusTourAt(110).remaining), 1);
  assert.equal(ui.exports.focusTourAt(140).remaining, 300);
  assert.equal(ui.exports.focusTourAt(175).finished, true);
  const sound = textOf(ui.render(ui.exports.BackgroundSoundsTourModule, {frame: 70}));
  assert.match(sound, /Ocean playing/);
  assert.match(sound, /Stop on lock, screen saver or sleep/);
});

test('screen and keyboard cleaning, mirror and teleprompter show their stop states', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  assert.match(textOf(ui.render(ui.exports.ScreenCleaningCover, {frame: 35})), /Exit screen cleaning/);
  const scene = load('src/scenes/SceneDesktopTools.tsx');
  const cleaningFrom = scene.exports.DESKTOP_TOUR_STEPS.find((step) => step.id === 'cleaning').from;
  assert.match(textOf(scene.render(scene.exports.SceneDesktopTools, {}, cleaningFrom + 100)), /Keyboard input blocked/);
  assert.match(textOf(scene.render(scene.exports.SceneDesktopTools, {}, cleaningFrom + 160)), /Keyboard input resumed/);
  const presenter = textOf(ui.render(ui.exports.PresenterTourModule, {frame: 90}));
  assert.match(presenter, /Script paused at your place/);
  assert.match(presenter, /Camera stopped/);
});

test('system export and reviewed cleanup retain data requiring review', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  const system = textOf(ui.render(ui.exports.SystemHistoryTourModule, {frame: 140, globalFrame: 6000}));
  for (const text of ['CPU', 'GPU', 'Memory', 'Network', 'Disk', 'Fan', 'Saved: System history.xlsx']) assert.ok(system.includes(text), text);
  assert.match(textOf(ui.render(ui.exports.CleanupTourModule, {frame: 38})), /Move 3 items to Trash/);
  const done = textOf(ui.render(ui.exports.CleanupTourModule, {frame: 70}));
  assert.match(done, /3 items moved to Trash · 548 MB · Review item kept/);
  assert.match(done, /Old preferencesReview required.*3 MB/);
});

test('window switch and distinct Quick Actions have concrete results', () => {
  const ui = load('src/modules/tour/SettingsTourModule.tsx');
  assert.match(textOf(ui.render(ui.exports.WindowsTourModule, {frame: 75})), /Notes window activated/);
  for (const example of ui.exports.quickActionExamples) {
    const pending = textOf(ui.render(ui.exports.QuickActionsTourModule, {frame: example.from + 6}));
    assert.ok(pending.includes(example.input));
    assert.ok(!pending.includes(example.result));
    assert.ok(textOf(ui.render(ui.exports.QuickActionsTourModule, {frame: example.from + example.at + 10})).includes(example.result));
  }
});

test('permissions, separate lock-screen playback and management update their statuses', () => {
  const ui = load('src/modules/tour/SettingsTourModule.tsx');
  assert.equal(ui.exports.permissionDemo.length, 15);
  const permissions = textOf(ui.render(ui.exports.PermissionsTourModule, {frame: 90}));
  for (const item of ui.exports.permissionDemo) assert.ok(permissions.includes(item.name));
  assert.match(permissions, /Microphone permission granted/);
  const locked = textOf(ui.render(ui.exports.LockScreenTourModule, {frame: 60, globalFrame: 6700}));
  assert.match(locked, /Paper Lanterns · Mira Solen/);
  assert.match(locked, /Playback paused/);
  assert.ok(!locked.includes('MenuBar') && !locked.includes('System permissions'));
  const installed = textOf(ui.render(ui.exports.ManagementTourModule, {frame: 50}));
  assert.match(installed, /Gemini CLI installed/);
  assert.doesNotMatch(installed, /Sync targets|Skills synced/);
  const synced = textOf(ui.render(ui.exports.ManagementTourModule, {frame: 120}));
  assert.match(synced, /Skills synced to enabled CLIs/);
  assert.doesNotMatch(synced, /Gemini CLI installed/);
});

test('recommended apps remain separate and the lid animation keeps the Zshell desktop', () => {
  const ui = load('src/modules/tour/RecommendedDesktopTour.tsx');
  const lid = load('src/modules/tour/LidCloseDesktopPreview.tsx');
  const browsing = textOf(ui.render(ui.exports.RecommendedDesktopTour, {frame: 10}));
  for (const app of ui.exports.recommendedDemo) assert.ok(browsing.includes(app.name));
  assert.doesNotMatch(browsing, /Zshell opened as a separate app/);
  const opened = textOf(ui.render(ui.exports.RecommendedDesktopTour, {frame: 56}));
  assert.match(opened, /Zshell opened as a separate app/);
  assert.doesNotMatch(opened, /Lid-close animation|Preview ended/);
  const completed = lid.render(lid.exports.LidCloseDesktopPreview, {frame: 180});
  const result = textOf(completed);
  assert.match(result, /Zshell.*launch-project.*Lid-close animation/s);
  assert.doesNotMatch(result, /Settings → Features|Preview animation|Preview ended/);
  assert.equal(lid.exports.lidPreviewAt(180).angle, 125);
  assert.doesNotMatch(result, /Zshell opened as a separate app/);
});
