import {spawnSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {soundtrack} from '../src/soundtrack.ts';
import {FPS, TOTAL_FRAMES} from '../src/timeline.ts';

const source = process.argv[2];
if (!source) throw new Error('Usage: node tools/make-soundtrack.mjs <original.mp3> [output.mp3]');

const output = process.argv[3] ?? fileURLToPath(new URL('../public/audio/zisla-launch.mp3', import.meta.url));
const duration = TOTAL_FRAMES / FPS;
mkdirSync(dirname(output), {recursive: true});

// Keep one uninterrupted passage and its original dynamics; only the film edges are faded.
const result = spawnSync('ffmpeg', [
  '-hide_banner', '-loglevel', 'error', '-y',
  '-i', source,
  '-map', '0:a:0', '-vn', '-t', String(duration),
  '-af', `volume=-2dB,afade=t=in:st=0:d=0.4:curve=hsin,afade=t=out:st=${duration - 4.2}:d=3.8:curve=hsin`,
  '-ar', '44100', '-ac', '2', '-c:a', 'libmp3lame', '-b:a', '320k',
  '-id3v2_version', '3',
  '-metadata', `title=${soundtrack.title} (zisla launch film edit)`,
  '-metadata', `artist=${soundtrack.artist}`,
  '-metadata', `copyright=${soundtrack.attribution}`,
  '-metadata', `comment=Continuous first ${duration} seconds; gain -2 dB; edge fades. Source: ${soundtrack.source}. License: ${soundtrack.licenseUrl}`,
  output,
], {stdio: 'inherit'});

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
