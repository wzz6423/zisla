// 宣传片的配乐生成脚本：全部由正弦叠加和噪声合成，没有第三方素材，固定种子保证每次结果一致。
// 用法：node tools/make-soundtrack.mjs public/audio/zisla-launch.wav
// 之后用 ffmpeg 把 wav 转成 mp3，再交给 Remotion 渲染。
import {mkdirSync, writeFileSync} from 'node:fs';
import {dirname} from 'node:path';

const SR = 44100;
const DURATION = 50; // 与影片等长
const N = SR * DURATION;
const TAU = Math.PI * 2;
const BEAT = 60 / 96; // 96 BPM

const L = new Float64Array(N);
const R = new Float64Array(N);
const PLUCK = new Float64Array(N); // 拨弦走单独缓冲，过一遍反馈延迟再混回来

const midi = (note) => 440 * 2 ** ((note - 69) / 12);

const rng = (() => {
  let a = 20261111;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
})();

// 每层只用"拉起 / 落下"两段包络，中间保持
const envelope = (t, total, attack, release) => Math.max(0, Math.min(1, t / attack, (total - t) / release));

// 垫底和声：两个轻微失谐的振荡器分居左右，不加混响也有宽度
function padNote(t0, len, freq, gain) {
  const i0 = Math.round(t0 * SR);
  const i1 = Math.min(N, Math.round((t0 + len) * SR));
  const total = (i1 - i0) / SR;
  const drift = rng() * TAU;
  for (let i = i0; i < i1; i++) {
    const t = (i - i0) / SR;
    const env = envelope(t, total, 1.6, 1.8) * gain * (1 + 0.05 * Math.sin(TAU * 0.13 * t + drift));
    if (env <= 0) continue;
    // 三角波的谐波比例：比纯正弦暖，又不会像锯齿那样刺
    const a = Math.sin(TAU * freq * t) + 0.11 * Math.sin(TAU * freq * 3 * t) + 0.04 * Math.sin(TAU * freq * 5 * t);
    const b =
      Math.sin(TAU * freq * 0.9977 * t) + 0.11 * Math.sin(TAU * freq * 3 * 0.9977 * t) + 0.04 * Math.sin(TAU * freq * 5 * 0.9977 * t);
    L[i] += env * a * 0.62;
    R[i] += env * b * 0.62;
  }
}

function bassNote(t0, len, freq, gain) {
  const i0 = Math.round(t0 * SR);
  const i1 = Math.min(N, Math.round((t0 + len) * SR));
  const total = (i1 - i0) / SR;
  for (let i = i0; i < i1; i++) {
    const t = (i - i0) / SR;
    const env = envelope(t, total, 0.5, 1.1) * gain;
    if (env <= 0) continue;
    const x = Math.sin(TAU * freq * t) + 0.26 * Math.sin(TAU * freq * 2 * t) * Math.exp(-t / 0.9);
    L[i] += env * x * 0.99;
    R[i] += env * x;
  }
}

function kick(t0, gain) {
  const i0 = Math.round(t0 * SR);
  const i1 = Math.min(N, Math.round((t0 + 0.5) * SR));
  let phase = 0;
  let previous = 0;
  for (let i = i0; i < i1; i++) {
    const t = (i - i0) / SR;
    phase += (TAU * (48 + 82 * Math.exp(-t / 0.035))) / SR; // 累积相位代替算积分，扫频才干净
    const noise = rng() * 2 - 1;
    const click = (noise - previous) * Math.exp(-t / 0.003) * 0.18; // 差分等于高通，噪声变成一击
    previous = noise;
    const x = (Math.sin(phase) * Math.exp(-t / 0.11) + click) * Math.min(1, t / 0.004) * gain;
    L[i] += x;
    R[i] += x;
  }
}

function tick(t0, gain, left, right) {
  const i0 = Math.round(t0 * SR);
  const i1 = Math.min(N, Math.round((t0 + 0.08) * SR));
  let previous = 0;
  for (let i = i0; i < i1; i++) {
    const t = (i - i0) / SR;
    const noise = rng() * 2 - 1;
    const x = (noise - previous) * Math.exp(-t / 0.009) * Math.min(1, t / 0.002) * gain;
    previous = noise;
    L[i] += x * left;
    R[i] += x * right;
  }
}

function pluck(t0, freq) {
  const i0 = Math.round(t0 * SR);
  const i1 = Math.min(N, Math.round((t0 + 1.2) * SR));
  for (let i = i0; i < i1; i++) {
    const t = (i - i0) / SR;
    const x = Math.sin(TAU * freq * t) + 0.25 * Math.sin(TAU * freq * 2 * t) + 0.08 * Math.sin(TAU * freq * 3 * t);
    PLUCK[i] += x * Math.min(1, t / 0.005) * Math.exp(-t / 0.3);
  }
}

function bell(t0, freq, gain, decay) {
  const partials = [
    [1, 1, decay],
    [2, 0.42, decay * 0.62],
    [2.76, 0.2, decay * 0.42],
    [5.4, 0.06, decay * 0.24],
  ];
  const i0 = Math.round(t0 * SR);
  const i1 = Math.min(N, Math.round((t0 + decay + 0.6) * SR));
  for (let i = i0; i < i1; i++) {
    const t = (i - i0) / SR;
    let x = 0;
    for (const [ratio, amp, tau] of partials) x += amp * Math.sin(TAU * freq * ratio * t) * Math.exp(-t / tau);
    const env = Math.min(1, t / 0.005) * gain;
    L[i] += x * env * 0.9;
    R[i] += x * env;
  }
}

// 一阶低通，把白噪声捏成"风"而不是"沙"
function lowpass(input, cutoff) {
  const out = new Float64Array(input.length);
  const a = 1 - Math.exp((-TAU * cutoff) / SR);
  let y = 0;
  for (let i = 0; i < input.length; i++) {
    y += a * (input[i] - y);
    out[i] = y;
  }
  return out;
}

function whoosh(tPeak, gain) {
  const rise = 1.3;
  const fall = 1;
  const count = Math.round((rise + fall) * SR);
  const noise = new Float64Array(count);
  for (let i = 0; i < count; i++) noise[i] = rng() * 2 - 1;
  const low = lowpass(noise, 320);
  const high = lowpass(noise, 2600);
  const i0 = Math.round((tPeak - rise) * SR);
  for (let i = 0; i < count; i++) {
    const index = i0 + i;
    if (index < 0 || index >= N) continue;
    const t = i / SR;
    const u = t < rise ? t / rise : 1 - (t - rise) / fall;
    const env = Math.sin((Math.PI / 2) * Math.max(0, u)) ** 2 * gain;
    const x = (high[i] - low[i]) * env;
    L[index] += x;
    if (index + 220 < N) R[index + 220] += x * 0.92; // 右声道晚 5ms，噪声就有方向感
  }
}

function subSwell(t0, len, freq, gain) {
  const i0 = Math.round(t0 * SR);
  const i1 = Math.min(N, Math.round((t0 + len) * SR));
  const total = (i1 - i0) / SR;
  for (let i = i0; i < i1; i++) {
    const t = (i - i0) / SR;
    const env = envelope(t, total, 1.6, 1) * gain;
    const x = Math.sin(TAU * freq * t) * env;
    L[i] += x;
    R[i] += x;
  }
}

// 和声走一圈 Am9 – Fmaj7 – C – G，两遍，再落回 Am
const CHORDS = [
  {t: 0, pad: [57, 60, 64, 59], bass: 45}, // Am9
  {t: 5, pad: [53, 57, 60, 64], bass: 41}, // Fmaj7
  {t: 10, pad: [60, 64, 67], bass: 48}, // C
  {t: 15, pad: [59, 62, 67], bass: 43}, // G
  {t: 20, pad: [57, 60, 64], bass: 45}, // Am
  {t: 25, pad: [53, 57, 60, 64], bass: 41}, // Fmaj7
  {t: 30, pad: [60, 64, 67], bass: 48}, // C
  {t: 35, pad: [59, 62, 67], bass: 43}, // G
  {t: 40, pad: [50, 53, 57], bass: 38}, // Dm
  {t: 45, pad: [57, 60, 64, 69], bass: 45}, // Am
];

// 苏醒：低频垫底，2.2s 岛展开时给一声铃和一记气声
subSwell(0.3, 2.8, 55, 0.1);
bell(2.2, midi(76), 0.12, 3);
whoosh(2.2, 0.06);

for (const chord of CHORDS) {
  chord.pad.forEach((note, index) => padNote(chord.t, 6.2, midi(note), 0.042 - index * 0.005));
  bassNote(chord.t, 5.6, midi(chord.bass), 0.085);
}

// 第二至五幕的落点各给一次提示：铃 + 气声
bell(8, midi(72), 0.09, 2.4);
bell(20, midi(76), 0.1, 2.4);
bell(33, midi(79), 0.11, 2.6);
bell(43, midi(81), 0.12, 3.4);
for (const scene of [8, 20, 33, 43]) whoosh(scene, 0.085);

// 第二幕起有心跳一样的低频脉冲，第三幕起加碎拍
for (let bar = 3; bar <= 18; bar += 1) {
  kick(bar * 2.5, 0.3);
  kick(bar * 2.5 + 1.25, 0.2);
}

let flip = 0;
for (let t = 20 + BEAT / 2; t < 45; t += BEAT) {
  tick(t, 0.028, flip % 2 ? 0.75 : 1, flip % 2 ? 1 : 0.75);
  flip += 1;
}

// 第四幕起加拨弦：A 小调五声，整套和声都不会撞音
const PENTATONIC = [69, 72, 74, 76, 79, 81];
let step = 2;
for (let t = 30; t < 45; t += BEAT) {
  step = Math.min(PENTATONIC.length - 1, Math.max(0, step + Math.floor(rng() * 3) - 1));
  pluck(t, midi(PENTATONIC[step]));
}

// 拨弦过一遍反馈延迟，尾巴甩回左右两侧
const DELAY = Math.round(0.234375 * SR);
for (let i = DELAY; i < N; i++) PLUCK[i] += PLUCK[i - DELAY] * 0.34;
for (let i = 0; i < N; i++) {
  L[i] += PLUCK[i] * 0.05;
  if (i + 1500 < N) R[i + 1500] += PLUCK[i] * 0.05;
}

// 收尾最后一声
bell(45.6, midi(69), 0.09, 3);
bell(45.6, midi(76), 0.05, 3);

for (let i = 0; i < N; i++) {
  const t = i / SR;
  let fade = 1;
  if (t < 0.4) fade *= 0.5 - 0.5 * Math.cos((Math.PI * t) / 0.4);
  if (t > 47.6) fade *= Math.max(0, 0.5 + 0.5 * Math.cos((Math.PI * (t - 47.6)) / 2.1));
  L[i] *= fade;
  R[i] *= fade;
}

let peak = 0;
for (let i = 0; i < N; i++) {
  L[i] = Math.tanh(L[i] * 1.1); // 轻微软削顶，把峰值收圆
  R[i] = Math.tanh(R[i] * 1.1);
  peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
}
const scale = 0.89 / peak;
let energy = 0;
for (let i = 0; i < N; i++) {
  L[i] *= scale;
  R[i] *= scale;
  energy += L[i] * L[i] + R[i] * R[i];
}

const out = process.argv[2] ?? 'public/audio/zisla-launch.wav';
const data = Buffer.alloc(44 + N * 4);
data.write('RIFF', 0);
data.writeUInt32LE(36 + N * 4, 4);
data.write('WAVE', 8);
data.write('fmt ', 12);
data.writeUInt32LE(16, 16);
data.writeUInt16LE(1, 20);
data.writeUInt16LE(2, 22);
data.writeUInt32LE(SR, 24);
data.writeUInt32LE(SR * 4, 28);
data.writeUInt16LE(4, 32);
data.writeUInt16LE(16, 34);
data.write('data', 36);
data.writeUInt32LE(N * 4, 40);
let offset = 44;
for (let i = 0; i < N; i++) {
  data.writeInt16LE(Math.round(L[i] * 32767), offset);
  data.writeInt16LE(Math.round(R[i] * 32767), offset + 2);
  offset += 4;
}
mkdirSync(dirname(out), {recursive: true});
writeFileSync(out, data);
console.log(
  `wrote ${out}: ${DURATION}s @ ${SR} Hz stereo, peak ${(20 * Math.log10(0.89)).toFixed(1)} dBFS, rms ${(
    10 * Math.log10(energy / (2 * N))
  ).toFixed(1)} dBFS`,
);
