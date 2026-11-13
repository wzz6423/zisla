export const FPS = 60;

// The incoming scene fades over the still-opaque outgoing scene.
export const CROSSFADE = 16;

export const SCENES = {
  awakening: {from: 0, duration: 300},
  layouts: {from: 300, duration: 960},
  aiCenter: {from: 1260, duration: 840},
  flow: {from: 2100, duration: 900},
  mail: {from: 3000, duration: 480},
  everyday: {from: 3480, duration: 1440},
  creative: {from: 4920, duration: 1920},
  desktop: {from: 6840, duration: 1460},
  settings: {from: 8300, duration: 1140},
  outro: {from: 9440, duration: 160},
} as const;

export const TOTAL_FRAMES = SCENES.outro.from + SCENES.outro.duration;

// Shared readouts use film time; local frame zero includes the crossfade lead.
export const filmFrame = (scene: keyof typeof SCENES, frame: number): number => frame + Math.max(0, SCENES[scene].from - CROSSFADE);
