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
  const isolatedRequire = (name) => name === 'remotion' ? {
    ...Remotion,
    useCurrentFrame: () => clock.frame,
    useVideoConfig: () => ({fps: 60, width: 1920, height: 1080, durationInFrames: 960}),
    Img: (props) => React.createElement('img', props),
  } : require(name);
  new Function('require', 'module', 'exports', bundle.outputFiles[0].text)(isolatedRequire, module, module.exports);
  return {exports: module.exports, render: (Component, props = {}, frame = 0) => {
    clock.frame = frame;
    return parseFragment(renderToStaticMarkup(React.createElement(Component, props)));
  }};
};

const all = (node) => [node, ...(node.childNodes ?? []).flatMap(all)];
const attr = (node, name) => node.attrs?.find((entry) => entry.name === name)?.value;
const feature = (node, name) => all(node).find((entry) => attr(entry, 'data-feature') === name);
const textOf = (node) => node?.nodeName === '#text' ? node.value : (node?.childNodes ?? []).map(textOf).join('');

const analytics = load('src/modules/AIAnalyticsModule.tsx');
const scene = load('src/scenes/Scene2AICenter.tsx');
const {AI_ACTIONS, AI_DURATION, aiSceneStateAt, Scene2AICenter} = scene.exports;

test('selected model totals use input plus output and display Codex usage under ChatGPT', () => {
  const {DailyModelUsageList, aiModelUsage, aiModelTokenTotal} = analytics.exports;
  assert.equal(aiModelTokenTotal, 601_000);
  assert.equal(aiModelTokenTotal, aiModelUsage.reduce((total, usage) => total + usage.inputTokens + usage.outputTokens, 0));
  const list = analytics.render(DailyModelUsageList);
  const content = textOf(list);
  assert.match(content, /Nov 11, 2026.*601k Token/);
  assert.match(content, /ChatGPT.*GPT-5\.1 Codex.*Input 0\.148 M · Output 0\.064 M/);
  assert.doesNotMatch(content, /CODEX|USD|\$/);
  for (const usage of aiModelUsage) {
    const row = all(list).find((node) => attr(node, 'data-model') === usage.model);
    assert.equal(Number(attr(row, 'data-token-total')), usage.inputTokens + usage.outputTokens);
  }
});

test('quota cards preserve 5h and 7d windows, reset dates and a separate Cursor dollar budget', () => {
  const {AIAnalyticsModule, aiAccountBalances, quotaFraction} = analytics.exports;
  const normal = analytics.render(AIAnalyticsModule);
  assert.match(textOf(feature(normal, 'ai.quota.claude')), /Claude5h 72%.*11\/11 13:00 resets7d 44%.*11\/15 09:00 resets/);
  assert.match(textOf(feature(normal, 'ai.quota.codex')), /Codex \/ ChatGPT5h 68%.*7d 31%/);
  assert.match(textOf(feature(normal, 'ai.budget.cursor')), /CursorAvailable budget \$68\.5.*12\/01 00:00 resets/);
  assert.doesNotMatch(textOf(normal), /gateway|Used |Checked |Input /);
  for (const balance of aiAccountBalances) for (const window of balance.windows) {
    assert.ok(quotaFraction(window) >= 0 && quotaFraction(window) <= 1);
    if (window.kind === 'fiveHours') assert.equal(window.durationSeconds, 18_000);
    if (window.kind === 'weekly') assert.equal(window.durationSeconds, 604_800);
    if (balance.provider !== 'cursor') assert.equal(window.unit, 'percent');
  }
});

test('quota thresholds and missing denominators match native remaining allowance semantics', () => {
  const {quotaSeverity, quotaFraction, quotaValue, AccountBalanceCard} = analytics.exports;
  const base = {id: 'plan', kind: 'budget', unit: 'usd', resetsAt: '2026-12-01T00:00:00+08:00'};
  for (const [remainingPercent, expected] of [[0, 'exhausted'], [0.1, 'critical'], [10, 'critical'], [10.1, 'warning'], [20, 'warning'], [20.1, 'normal'], [100, 'normal']]) {
    assert.equal(quotaSeverity({...base, remainingPercent}), expected);
  }
  assert.equal(quotaSeverity({...base, remaining: 0}), 'exhausted');
  assert.equal(quotaSeverity({...base, remaining: 2}), 'normal');
  assert.equal(quotaFraction({...base, remaining: 2}), undefined);
  assert.equal(quotaFraction({...base, remaining: 2, limit: 0}), undefined);
  assert.equal(quotaFraction({...base, remaining: 2, limit: 10}), 0.2);
  assert.equal(quotaValue({...base, remaining: 2}), '$2');
  const unknown = analytics.render(AccountBalanceCard, {balance: {provider: 'cursor', title: 'Cursor', windows: [{...base, remaining: 2}]}});
  assert.equal(all(unknown).filter((node) => attr(node, 'stroke-dasharray') !== undefined).length, 0, 'An amount without a denominator cannot invent an arc');
  const empty = analytics.render(AccountBalanceCard, {balance: {provider: 'cursor', title: 'Cursor', windows: []}});
  assert.equal(textOf(empty), 'Cursor');
});

test('named provider windows remain separate from the canonical nested quota rings', () => {
  const {AccountBalanceCard} = analytics.exports;
  const resetsAt = '2026-11-15T09:00:00+08:00';
  const windows = [
    {id: 'additional:feature', kind: 'fiveHours', name: 'Review quota', unit: 'percent', remainingPercent: 5, durationSeconds: 18_000, resetsAt},
    {id: 'five_hour', kind: 'fiveHours', unit: 'percent', remainingPercent: 72, durationSeconds: 18_000, resetsAt},
    {id: 'opus', kind: 'weekly', name: 'Opus', unit: 'percent', remainingPercent: 9, resetsAt},
    {id: 'seven_day', kind: 'weekly', unit: 'percent', remainingPercent: 44, resetsAt},
  ];
  const card = analytics.render(AccountBalanceCard, {balance: {provider: 'claude', title: 'Claude', windows}});
  const rings = all(card).filter((node) => node.tagName === 'svg' && attr(node, 'width') !== '12');
  assert.equal(rings.length, 3);
  assert.equal(attr(rings[0], 'width'), '52');
  const canonical = all(rings[0]).map((node) => attr(node, 'data-quota-window')).filter(Boolean);
  assert.deepEqual(canonical, ['seven_day', 'five_hour']);
  assert.match(textOf(card), /Review quota 5%/);
  assert.match(textOf(card), /Opus 9%/);
});

test('clicking a date reveals its model breakdown and scrolling keeps the same selected day', () => {
  const before = scene.render(Scene2AICenter, {}, AI_ACTIONS.selectDay - 1);
  assert.equal(feature(before, 'ai.usage.models'), undefined);
  const after = scene.render(Scene2AICenter, {}, AI_ACTIONS.selectDay + 6);
  assert.equal(attr(feature(after, 'ai.usage.models'), 'data-usage-date'), '2026-11-11');
  assert.equal(attr(feature(after, 'ai.usage.trend'), 'data-today-tokens'), '601000');
  assert.equal(all(after).filter((node) => attr(node, 'data-selected') === 'true').length, 1);
  const atModels = aiSceneStateAt(AI_ACTIONS.models + 42);
  const atBalance = aiSceneStateAt(AI_ACTIONS.balance + 42);
  assert.equal(atModels.scroll, 180);
  assert.equal(atBalance.scroll, 322);
  assert.equal(atModels.selected, true);
  assert.equal(atBalance.selected, true);
});

test('the shared trend grows to the native history viewport without clipping the final sample', () => {
  const ui = load('src/modules/AIModule.tsx');
  const expanded = ui.render(ui.exports.TrendChart, {reveal: 1, todayTokens: 601_000, width: 722, height: 180});
  const chart = feature(expanded, 'ai.usage.trend');
  assert.equal(attr(chart, 'width'), '722');
  assert.equal(attr(chart, 'height'), '180');
  const labels = all(chart).filter((node) => node.tagName === 'text');
  const lastLabel = labels.find((node) => textOf(node) === '11/11');
  assert.equal(attr(lastLabel, 'x'), '708');
  assert.equal(attr(lastLabel, 'y'), '176');
  const lastCircle = all(chart).find((node) => node.tagName === 'circle' && attr(node, 'r') === '3.2');
  assert.equal(attr(lastCircle, 'cx'), '708');
  assert.ok(Number(attr(lastCircle, 'cy')) > 50 && Number(attr(lastCircle, 'cy')) < 70);
});

test('the history export uses a real entry, save stage and completed result without clearing usage', () => {
  const settings = scene.render(Scene2AICenter, {}, AI_ACTIONS.viewHistory);
  assert.match(textOf(feature(settings, 'ai.usage.settings')), /View HistoryExportClear/);
  assert.equal(feature(settings, 'ai.usage.history'), undefined);
  const history = scene.render(Scene2AICenter, {}, AI_ACTIONS.historyDay + 6);
  const panel = feature(history, 'ai.usage.history');
  assert.ok(panel);
  assert.match(textOf(panel), /AI usage historyClearExportTime range24 hours7 days30 daysAll/);
  assert.equal(attr(all(panel).find((node) => node.tagName === 'svg' && attr(node, 'data-feature') === 'ai.usage.trend'), 'height'), '180');
  assert.equal(feature(panel, 'ai.usage.exported'), undefined);
  const saving = scene.render(Scene2AICenter, {}, AI_ACTIONS.save);
  assert.match(textOf(feature(saving, 'ai.usage.save')), /Save As:AI usage\.xlsxWhere:DocumentsCancelExport/);
  assert.equal(feature(saving, 'ai.usage.exported'), undefined);
  const saved = scene.render(Scene2AICenter, {}, AI_ACTIONS.saved + 18);
  assert.match(textOf(feature(saved, 'ai.usage.exported')), /Saved to AI usage\.xlsx/);
  assert.equal(feature(saved, 'ai.usage.save'), undefined);
  assert.equal(attr(feature(saved, 'ai.usage.models'), 'data-token-total'), '601000');
  assert.ok(AI_ACTIONS.balance - AI_ACTIONS.saved >= 90, 'The saved result needs readable screen time');
});

test('the pointer reaches the selected heat cell and each displayed history or export control', () => {
  const module = load('src/modules/AIModule.tsx').exports;
  const day = aiSceneStateAt(AI_ACTIONS.selectDay);
  assert.equal(day.cursor.x, 264 + module.AI_HEATMAP_TARGET.x);
  assert.equal(day.cursor.y, module.AI_HEATMAP_TARGET.y);
  const expected = [
    [AI_ACTIONS.settings, 1000, 111], [AI_ACTIONS.viewHistory, 443, 204],
    [AI_ACTIONS.historyDay, 948, 365], [AI_ACTIONS.export, 967, 82], [AI_ACTIONS.save, 821, 377],
  ];
  for (const [frame, x, y] of expected) {
    const state = aiSceneStateAt(frame);
    assert.equal(state.cursor.x, x, `Pointer misses the control at ${frame}`);
    assert.equal(state.cursor.y, y, `Pointer misses the control at ${frame}`);
  }
});

test('one low quota observation changes the card and survives as the same compact double-ring notice', () => {
  const {AIAnalyticsModule, aiAccountBalances} = analytics.exports;
  const original = JSON.stringify(aiAccountBalances);
  const low = analytics.render(AIAnalyticsModule, {lowQuota: true});
  const claude = feature(low, 'ai.quota.claude');
  assert.match(textOf(claude), /5h 8%.*7d 44%/);
  assert.equal(all(claude).filter((node) => attr(node, 'data-severity') === 'critical').length, 1);
  assert.equal(JSON.stringify(aiAccountBalances), original, 'Rendering a warning must not mutate the base observation');
  assert.equal(aiSceneStateAt(AI_ACTIONS.lowQuota - 1).lowQuota, false);
  assert.equal(aiSceneStateAt(AI_ACTIONS.lowQuota).lowQuota, true);
  const compact = scene.render(Scene2AICenter, {}, AI_ACTIONS.collapse + 36);
  const notice = feature(compact, 'ai.quota.compact');
  assert.equal(attr(notice, 'data-notice-id'), 'ai-balance-low-claude');
  assert.match(textOf(notice), /5h 8%7d 44%/);
  assert.ok(feature(notice, 'ai.quota.warning'));
  assert.equal(all(notice).filter((node) => attr(node, 'data-quota-window')).length, 2);
});

test('duration scaling and crossfade lead preserve the finished compact result and privacy statement', () => {
  assert.equal(AI_DURATION, 960);
  assert.deepEqual(aiSceneStateAt(480), aiSceneStateAt(488, 976));
  const last = scene.render(Scene2AICenter, {duration: 976}, 975);
  assert.ok(feature(last, 'ai.quota.compact'));
  assert.equal(feature(last, 'ai.usage.history'), undefined);
  assert.match(textOf(feature(last, 'ai.privacy')), /Structured metadata only\..*Never reads your prompts\..*Prompts and answer bodies are never read\./);
});
