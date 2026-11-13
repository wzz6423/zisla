import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {soundtracks} from '../src/soundtrack.ts';
import {FPS, TOTAL_FRAMES} from '../src/timeline.ts';

const script = fileURLToPath(new URL('./make-soundtrack.mjs', import.meta.url));
const run = (args, env = process.env) => spawnSync(process.execPath, [script, ...args], {encoding: 'utf8', env});

test('soundtrack variants identify separate original works and share the fixed film duration', () => {
  assert.deepEqual(Object.keys(soundtracks), ['funk', 'cinematic']);
  assert.equal(TOTAL_FRAMES / FPS, 160);
  assert.equal(soundtracks.funk.title, 'Funkorama');
  assert.equal(soundtracks.cinematic.title, 'The Miracle of Flight');
  assert.notEqual(soundtracks.funk.audio, soundtracks.cinematic.audio);
  for (const track of Object.values(soundtracks)) {
    assert.equal(new URL(track.source).protocol, 'https:');
    assert.equal(track.licenseUrl, 'https://creativecommons.org/licenses/by/4.0/');
    assert.ok(track.attribution.includes(track.artist));
  }
});

test('missing input and unsupported variants fail before creating an output directory', () => {
  const taskDir = mkdtempSync(join(tmpdir(), 'zisla-soundtrack-test-'));
  try {
    assert.notEqual(run([]).status, 0);
    const invalid = run(['source.mp3', join(taskDir, 'new-directory/output.mp3'), 'unsupported']);
    assert.notEqual(invalid.status, 0);
    assert.match(invalid.stderr, /Unknown soundtrack/);
    assert.equal(existsSync(join(taskDir, 'new-directory')), false, 'Invalid variants must not create an output directory');
    assert.throws(() => readFileSync(join(taskDir, 'new-directory/output.mp3')));
  } finally { rmSync(taskDir, {recursive: true, force: true}); }
});

test('a missing encoder reports failure without creating media', () => {
  const taskDir = mkdtempSync(join(tmpdir(), 'zisla-soundtrack-test-'));
  try {
    const output = join(taskDir, 'output.mp3');
    const result = run(['source.mp3', output, 'funk'], {...process.env, PATH: taskDir});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /ENOENT/);
    assert.equal(existsSync(output), false);
  } finally { rmSync(taskDir, {recursive: true, force: true}); }
});

test('continuous audio edits pass literal paths and only their own attribution to ffmpeg, propagating encoder failures', () => {
  const taskDir = mkdtempSync(join(tmpdir(), 'zisla-soundtrack-test-'));
  try {
    const bin = join(taskDir, 'bin');
    mkdirSync(bin);
    const log = join(taskDir, 'args.json');
    writeFileSync(join(bin, 'ffmpeg'), `#!${process.execPath}\nconst fs = require('node:fs');\nfs.writeFileSync(process.env.ZISLA_SOUNDTRACK_TEST_ARGS, JSON.stringify(process.argv.slice(2)));\nprocess.exit(Number(process.env.ZISLA_SOUNDTRACK_TEST_EXIT || 0));\n`, {mode: 0o755});
    const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, ZISLA_SOUNDTRACK_TEST_ARGS: log};
    const source = join(taskDir, 'source $(touch wrong).mp3');
    const output = join(taskDir, 'a new directory/`touch wrong`.mp3');
    for (const variant of ['funk', 'cinematic']) {
      const result = run([source, output, variant], env);
      assert.equal(result.status, 0, result.stderr);
      const args = JSON.parse(readFileSync(log, 'utf8'));
      assert.equal(args[args.indexOf('-i') + 1], source);
      assert.equal(args.at(-1), output);
      assert.equal(args[args.indexOf('-t') + 1], '160');
      assert.equal(args[args.indexOf('-map_metadata') + 1], '-1');
      assert.equal(args[args.indexOf('-af') + 1], 'volume=-2dB,afade=t=in:st=0:d=0.4:curve=hsin,afade=t=out:st=155.8:d=3.8:curve=hsin');
      assert.doesNotMatch(args.join(' '), /aloop|concat|amix/);
      assert.ok(args.includes(`artist=${soundtracks[variant].artist}`));
      assert.ok(args.includes(`copyright=${soundtracks[variant].attribution}`));
      assert.ok(!args.includes(`artist=${soundtracks[variant === 'funk' ? 'cinematic' : 'funk'].artist}`));
    }
    assert.equal(run([source, output, 'funk'], {...env, ZISLA_SOUNDTRACK_TEST_EXIT: '7'}).status, 7);
    assert.throws(() => readFileSync(join(taskDir, 'wrong')));
  } finally { rmSync(taskDir, {recursive: true, force: true}); }
});
