export const FPS = 60;

// 相邻两幕叠化的帧数：后一幕在前一幕之上淡入
export const CROSSFADE = 16;

export const SCENES = {
  awakening: {from: 0, duration: 480},
  aiCenter: {from: 480, duration: 720},
  flow: {from: 1200, duration: 780},
  bento: {from: 1980, duration: 600},
  outro: {from: 2580, duration: 420},
} as const;

export const TOTAL_FRAMES = SCENES.outro.from + SCENES.outro.duration;

// 歌曲进度、番茄钟这类读数跨幕连续，要按全片帧号算。
// 除第一幕外，幕内第 0 帧是叠化起点，比名义起点早 CROSSFADE 帧。
export const filmFrame = (scene: keyof typeof SCENES, frame: number): number => frame + Math.max(0, SCENES[scene].from - CROSSFADE);
