import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as Remotion from 'remotion';

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));

const load = (entryPoint) => {
  const clock = {frame: 0};
  const bundle = buildSync({absWorkingDir: root, entryPoints: [entryPoint], bundle: true, packages: 'external', platform: 'node', format: 'cjs', jsx: 'automatic', write: false, loader: {'.svg': 'dataurl', '.png': 'dataurl'}});
  const module = {exports: {}};
  const isolatedRequire = (name) => name === 'remotion' ? {...Remotion, useCurrentFrame: () => clock.frame, useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 11160}), Img: (props) => React.createElement('img', props)} : require(name);
  new Function('require', 'module', 'exports', bundle.outputFiles[0].text)(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props = {}, frame = 0) => {clock.frame = frame; return renderToStaticMarkup(React.createElement(Component, props));}};
};

const textOf = (html) => html.replace(/<[^>]*>/g, '').replaceAll('&amp;', '&').replaceAll('&#x27;', "'").replaceAll('&quot;', '"');

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
        const expanded = at(midpoint * duration / nominal, duration);
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
  assert.doesNotMatch(textOf(ui.render(ui.exports.NotesTourModule, {frame: 80})), /Saved to Apple Notes/);
  assert.match(textOf(ui.render(ui.exports.NotesTourModule, {frame: 180})), /Saved to Apple Notes/);
  assert.match(textOf(ui.render(ui.exports.ClipboardTourModule, {frame: 180})), /Copied to clipboard/);
  const agenda = textOf(ui.render(ui.exports.AgendaTourModule, {frame: 180}));
  for (const text of ['Kyoto', 'Lisbon', 'Tromsø', 'Calendar and reminders', 'Reminder completed', 'resets the reminder timer']) assert.ok(agenda.includes(text), text);
});

test('a context note preserves its text, screenshot and reminder after saving', () => {
  const ui = load('src/modules/tour/EverydayTourModule.tsx');
  const before = textOf(ui.render(ui.exports.ContextNotesTourModule, {frame: 15}));
  const after = textOf(ui.render(ui.exports.ContextNotesTourModule, {frame: 180}));
  assert.ok(!before.includes(ui.exports.everydayDemo.context.text));
  for (const text of [ui.exports.everydayDemo.context.text, 'Every 3 hours', 'Window screenshot', 'View screenshot', 'Saved · Shown when you return']) assert.ok(after.includes(text), text);
});

test('briefing previews all eight templates and shows PNG output only after export', () => {
  const ui = load('src/modules/tour/EverydayTourModule.tsx');
  assert.equal(ui.exports.briefingTemplates.length, 8);
  const preview = textOf(ui.render(ui.exports.BriefingTourModule, {frame: 70}));
  for (const template of ui.exports.briefingTemplates) assert.ok(preview.includes(template.title));
  assert.doesNotMatch(preview, /Saved: Daily briefing/);
  assert.match(textOf(ui.render(ui.exports.BriefingTourModule, {frame: 190})), /Exporting PNG/);
  assert.match(textOf(ui.render(ui.exports.BriefingTourModule, {frame: 250})), /Saved: Daily briefing — Nov 11.png/);
});

test('voice transitions from recording to cleanup and inserted numbered transcript', () => {
  const ui = load('src/modules/tour/EverydayTourModule.tsx');
  const recording = textOf(ui.render(ui.exports.VoiceTourModule, {frame: 80, globalFrame: 5300}));
  assert.match(recording, /Recording · Release to finish/);
  assert.match(recording, /ToggleHold to talk/);
  assert.match(recording, /LM Studio/);
  for (const vocabulary of ui.exports.voiceVocabularies) assert.ok(recording.includes(vocabulary));
  assert.match(textOf(ui.render(ui.exports.VoiceTourModule, {frame: 150, globalFrame: 5370})), /Cleaning the transcript/);
  const done = textOf(ui.render(ui.exports.VoiceTourModule, {frame: 230, globalFrame: 5450}));
  assert.ok(done.includes(ui.exports.everydayDemo.voice.cleaned));
  assert.match(done, /Cleaned transcript inserted/);
  assert.match(done, /Ollama/);
});

test('mixer changes Safari volume while muting only Music', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  const before = textOf(ui.render(ui.exports.MixerTourModule, {frame: 0}));
  assert.match(before, /Safari100%/);
  const after = textOf(ui.render(ui.exports.MixerTourModule, {frame: 150}));
  assert.match(after, /Safari30%/);
  assert.match(after, /Music80%/);
  assert.match(after, /Safari at 30% · Music muted/);
});

test('keyboard counts and focus background-sound selection follow visible actions', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  const start = textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 0}));
  assert.match(start, /Holy Panda/);
  assert.match(start, /12,846/);
  const after = textOf(ui.render(ui.exports.KeyboardTourModule, {frame: 150}));
  assert.match(after, /Custom sound pack/);
  assert.match(after, /12,860/);
  assert.match(after, /14 characters added/);
  const focus = textOf(ui.render(ui.exports.FocusTourModule, {frame: 200}));
  assert.match(focus, /Focus completed/);
  assert.match(focus, /macOS background soundsStreamStop/);
  assert.match(textOf(ui.render(ui.exports.FocusTourModule, {frame: 150})), /macOS background soundsOceanStop/);
  assert.match(focus, /Stop on lock, screen saver or sleep/);
});

test('screen and keyboard cleaning, mirror and teleprompter show their stop states', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  assert.match(textOf(ui.render(ui.exports.CleaningTourModule, {frame: 40})), /Exit screen cleaning/);
  assert.match(textOf(ui.render(ui.exports.CleaningTourModule, {frame: 120})), /Keyboard input blocked/);
  assert.match(textOf(ui.render(ui.exports.CleaningTourModule, {frame: 170})), /Keyboard input resumed/);
  const presenter = textOf(ui.render(ui.exports.PresenterTourModule, {frame: 150}));
  assert.match(presenter, /Script paused at your place/);
  assert.match(presenter, /Camera stopped/);
});

test('system export and reviewed cleanup retain data requiring review', () => {
  const ui = load('src/modules/tour/DesktopTourModule.tsx');
  const system = textOf(ui.render(ui.exports.SystemHistoryTourModule, {frame: 180, globalFrame: 9500}));
  for (const text of ['CPU', 'GPU', 'Memory', 'Network', 'Disk:', 'Fan:', 'Public IPv4 + IPv6', 'Saved: System history.xlsx']) assert.ok(system.includes(text), text);
  assert.match(textOf(ui.render(ui.exports.CleanupTourModule, {frame: 60})), /Move 2 items to Trash/);
  const done = textOf(ui.render(ui.exports.CleanupTourModule, {frame: 100}));
  assert.match(done, /2 items moved to Trash · 344 MB · Review item kept/);
  assert.match(done, /Old preferencesReview required3 MB/);
});

test('window switch and all four Quick Actions have concrete results', () => {
  const ui = load('src/modules/tour/SettingsTourModule.tsx');
  assert.match(textOf(ui.render(ui.exports.WindowsTourModule, {frame: 140})), /Notes window activated/);
  for (const [index, example] of ui.exports.quickActionExamples.entries()) {
    const pending = textOf(ui.render(ui.exports.QuickActionsTourModule, {frame: index * 60 + 10}));
    assert.ok(pending.includes(example.input));
    assert.ok(!pending.includes(example.result));
    assert.ok(textOf(ui.render(ui.exports.QuickActionsTourModule, {frame: index * 60 + 45})).includes(example.result));
  }
});

test('permissions, separate lock-screen playback and management update their statuses', () => {
  const ui = load('src/modules/tour/SettingsTourModule.tsx');
  assert.equal(ui.exports.permissionDemo.length, 15);
  const permissions = textOf(ui.render(ui.exports.PermissionsTourModule, {frame: 130}));
  for (const item of ui.exports.permissionDemo) assert.ok(permissions.includes(item.name));
  assert.match(permissions, /Microphone permission granted/);
  const locked = textOf(ui.render(ui.exports.LockScreenTourModule, {frame: 130, globalFrame: 10500}));
  assert.match(locked, /Separate overlay/);
  assert.match(locked, /Playback paused/);
  assert.ok(!locked.includes('MenuBar') && !locked.includes('System permissions'));
  const managed = textOf(ui.render(ui.exports.ManagementTourModule, {frame: 145}));
  assert.match(managed, /Gemini CLI installed/);
  assert.match(managed, /Skills synced to enabled CLIs/);
});

test('recommended apps remain separate and lid preview restores the desktop', () => {
  const ui = load('src/modules/tour/SettingsTourModule.tsx');
  const result = textOf(ui.render(ui.exports.RecommendedTourModule, {frame: 220}));
  for (const app of ui.exports.recommendedDemo) assert.ok(result.includes(app.name));
  assert.match(result, /Quiet.md opened as a separate app/);
  assert.match(result, /Preview ended · Desktop restored/);
});
