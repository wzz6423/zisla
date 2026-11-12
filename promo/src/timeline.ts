export const FPS = 60;

// The incoming scene fades over the still-opaque outgoing scene.
export const CROSSFADE = 16;

export const SCENES = {
  awakening: {from: 0, duration: 480},
  aiCenter: {from: 480, duration: 720},
  flow: {from: 1200, duration: 780},
  mail: {from: 1980, duration: 600},
  bento: {from: 2580, duration: 600},
  outro: {from: 3180, duration: 420},
} as const;

export const TOTAL_FRAMES = SCENES.outro.from + SCENES.outro.duration;

// Shared readouts use film time; local frame zero includes the crossfade lead.
export const filmFrame = (scene: keyof typeof SCENES, frame: number): number => frame + Math.max(0, SCENES[scene].from - CROSSFADE);
