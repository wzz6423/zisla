export const FPS = 60;

// The incoming scene fades over the still-opaque outgoing scene.
export const CROSSFADE = 16;

export const SCENES = {
  awakening: {from: 0, duration: 270},
  layouts: {from: 270, duration: 600},
  aiCenter: {from: 870, duration: 690},
  flow: {from: 1560, duration: 780},
  mail: {from: 2340, duration: 420},
  everyday: {from: 2760, duration: 1080},
  creative: {from: 3840, duration: 1140},
  desktop: {from: 4980, duration: 1140},
  settings: {from: 6120, duration: 940},
  outro: {from: 7060, duration: 140},
} as const;

export const TOTAL_FRAMES = SCENES.outro.from + SCENES.outro.duration;

// Shared readouts use film time; local frame zero includes the crossfade lead.
export const filmFrame = (scene: keyof typeof SCENES, frame: number): number => frame + Math.max(0, SCENES[scene].from - CROSSFADE);
