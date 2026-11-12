export const FPS = 60;

// The incoming scene fades over the still-opaque outgoing scene.
export const CROSSFADE = 16;

export const SCENES = {
  awakening: {from: 0, duration: 480},
  layouts: {from: 480, duration: 1200},
  aiCenter: {from: 1680, duration: 720},
  flow: {from: 2400, duration: 780},
  mail: {from: 3180, duration: 600},
  everyday: {from: 3780, duration: 1560},
  creative: {from: 5340, duration: 2700},
  desktop: {from: 8040, duration: 1500},
  settings: {from: 9540, duration: 1200},
  outro: {from: 10740, duration: 420},
} as const;

export const TOTAL_FRAMES = SCENES.outro.from + SCENES.outro.duration;

// Shared readouts use film time; local frame zero includes the crossfade lead.
export const filmFrame = (scene: keyof typeof SCENES, frame: number): number => frame + Math.max(0, SCENES[scene].from - CROSSFADE);
