import bearSprite from '../../../mac/Resources/Pets/bear/sprite.png';
import chickSprite from '../../../mac/Resources/Pets/chick/sprite.png';
import {ease, track} from '../motion';
import {BAR_HEIGHT, NOTCH_WIDTH, STAGE} from '../theme';

export const LAYOUTS_DURATION = 1200;
export const LAYOUT_ACTIONS = {
  pill: 132,
  chooseCustom: 252,
  custom: 270,
  bottom: 384,
  left: 516,
  right: 648,
  camera: 780,
  chick: 906,
  petRight: 930,
  chooseFile: 996,
  importSheet: 1032,
  name: 1048,
  import: 1094,
  imported: 1114,
} as const;

export const LAYOUT_SETTINGS = {x: 404, y: 246, width: 472, triggerX: 777, styleY: 322, positionY: 363, adjustY: 404};
export const PLACEMENT_CONFIRM = {x: 696, y: 454};

type Edge = 'top' | 'bottom' | 'left' | 'right';
type Placement = {mode: 'camera' | 'custom'; edge: Edge; offset: number; inwardDistance: number};
export type LayoutFrame = {x: number; y: number; width: number; height: number};

const CAMERA: Placement = {mode: 'camera', edge: 'top', offset: 0.5, inwardDistance: 0};
const THICKNESS = 32;
const LENGTH = 240;
const INSET = 8;
const CURSOR_POINTS = [
  [0, 1040, 480], [104, 777, 322], [127, 777, 400], [138, 777, 400],
  [228, 777, 363], [246, 777, 439], [252, 777, 439], [306, 696, 454],
  [366, 777, 404], [420, 696, 454], [498, 777, 404], [552, 696, 454],
  [630, 777, 404], [684, 696, 454], [756, 777, 363], [775, 777, 405],
  [786, 777, 405], [882, 777, 322], [901, 777, 400], [912, 777, 400],
  [916, 777, 404], [925, 777, 482], [936, 777, 482], [988, 777, 363],
  [1004, 777, 363], [1026, 780, 432], [1038, 780, 432], [1048, 565, 419],
  [1084, 772, 514], [1100, 772, 514], [1142, 1010, 540],
] as const;

export const CUSTOM_PLACEMENTS: readonly {at: number; placement: Placement}[] = [
  {at: LAYOUT_ACTIONS.custom, placement: {mode: 'custom', edge: 'top', offset: 0.3, inwardDistance: 56}},
  {at: LAYOUT_ACTIONS.bottom, placement: {mode: 'custom', edge: 'bottom', offset: 0.65, inwardDistance: 16}},
  {at: LAYOUT_ACTIONS.left, placement: {mode: 'custom', edge: 'left', offset: 0.48, inwardDistance: 24}},
  {at: LAYOUT_ACTIONS.right, placement: {mode: 'custom', edge: 'right', offset: 0.5, inwardDistance: 56}},
];

// ScreenLayout uses bottom-up offsets on vertical edges; CSS coordinates run from the top.
export const placementFrame = (placement: Placement): LayoutFrame => {
  if (placement.mode === 'camera') return {x: (STAGE.width - LENGTH) / 2, y: 2, width: LENGTH, height: THICKNESS};
  const vertical = placement.edge === 'left' || placement.edge === 'right';
  const width = vertical ? THICKNESS : LENGTH;
  const height = vertical ? LENGTH : THICKNESS;
  const gap = Math.min(THICKNESS * 3, Math.max(INSET, placement.inwardDistance));
  const x = Math.min(STAGE.width - INSET - width, Math.max(INSET, STAGE.width * placement.offset - width / 2));
  const y = Math.min(STAGE.height - INSET - height, Math.max(INSET, STAGE.height * (1 - placement.offset) - height / 2));
  switch (placement.edge) {
    case 'top': return {x, y: gap, width, height};
    case 'bottom': return {x, y: STAGE.height - gap - height, width, height};
    case 'left': return {x: gap, y, width, height};
    case 'right': return {x: STAGE.width - gap - width, y, width, height};
  }
};

export const placementNearest = (x: number, y: number, preferredEdge: Edge): Placement => {
  const distances: readonly (readonly [Edge, number])[] = [['top', y], ['bottom', STAGE.height - y], ['left', x], ['right', STAGE.width - x]];
  const distance = Math.min(...distances.map((entry) => entry[1]));
  const nearest = distances.filter((entry) => Math.abs(entry[1] - distance) < 0.001);
  const edge = (nearest.find((entry) => entry[0] === preferredEdge) ?? nearest[0])![0];
  const vertical = edge === 'left' || edge === 'right';
  const gap = Math.min(THICKNESS * 3, Math.max(INSET, distance - THICKNESS / 2));
  return {mode: 'custom', edge, offset: vertical ? 1 - y / STAGE.height : x / STAGE.width, inwardDistance: gap === INSET ? 0 : gap};
};

export const layoutPets = {
  bear: {id: 'bear', name: 'Bear', src: bearSprite, width: 162, height: 140},
  chick: {id: 'chick', name: 'Chick', src: chickSprite, width: 137, height: 136},
} as const;

// The CC0 pets have one frame. Native PetSpriteView breathes and bobs them every 1.4 seconds.
export const petMotionAt = (frame: number, fps: number) => {
  const phase = Math.cos((frame / fps) * Math.PI * 2 / 1.4);
  return {scale: 1 - phase * 0.03, lift: -phase * 0.04};
};

export const layoutStateAt = (frame: number, duration = LAYOUTS_DURATION) => {
  const local = frame * LAYOUTS_DURATION / duration;
  const style = local < LAYOUT_ACTIONS.pill ? 'notch' : 'pill';
  let placement = CAMERA;
  let editing = false;
  let dragging = false;
  let confirmation = 0;
  let cursor = {x: LAYOUT_SETTINGS.triggerX, y: LAYOUT_SETTINGS.styleY};
  let pressed = false;
  for (const step of CUSTOM_PLACEMENTS) {
    const previous = placement.mode === 'camera' && local >= LAYOUT_ACTIONS.chooseCustom && local < LAYOUT_ACTIONS.camera
      ? {...placement, mode: 'custom' as const} : placement;
    const start = step.at - 18;
    if (local >= step.at + 18) placement = step.placement;
    else if (local >= step.at) {
      const from = placementFrame(previous);
      const to = placementFrame(step.placement);
      const x = ease(local, [step.at, step.at + 18], [from.x + from.width / 2, to.x + to.width / 2]);
      const y = ease(local, [step.at, step.at + 18], [from.y + from.height / 2, to.y + to.height / 2]);
      placement = placementNearest(x, y, previous.edge);
    }
    if (local >= start && local < step.at + 36) {
      if (local < step.at) placement = previous;
      editing = true;
      dragging = local >= step.at && local < step.at + 18;
      confirmation = Math.min(1, Math.max(0, (local - step.at - 30) / 18));
      const from = placementFrame(previous);
      const to = placementFrame(step.placement);
      cursor = {
        x: track(local, [[start, LAYOUT_SETTINGS.triggerX], [step.at, from.x + from.width / 2], [step.at + 18, to.x + to.width / 2], [step.at + 29, PLACEMENT_CONFIRM.x], [step.at + 36, PLACEMENT_CONFIRM.x]]),
        y: track(local, [[start, step.at === LAYOUT_ACTIONS.custom ? 439 : LAYOUT_SETTINGS.adjustY], [step.at, from.y + from.height / 2], [step.at + 18, to.y + to.height / 2], [step.at + 29, PLACEMENT_CONFIRM.y], [step.at + 36, PLACEMENT_CONFIRM.y]]),
      };
      pressed = dragging || (local >= step.at + 30 && local < step.at + 36)
        || (local >= LAYOUT_ACTIONS.chooseCustom && local < LAYOUT_ACTIONS.chooseCustom + 6);
    }
  }
  if (local >= LAYOUT_ACTIONS.camera) placement = CAMERA;
  const rect = style === 'notch' ? {x: (STAGE.width - NOTCH_WIDTH - 80) / 2, y: 0, width: NOTCH_WIDTH + 80, height: BAR_HEIGHT + 2} : placementFrame(placement);
  const pets = local >= LAYOUT_ACTIONS.camera;
  const pet = local < LAYOUT_ACTIONS.chick ? layoutPets.bear : layoutPets.chick;
  const petSide = local < LAYOUT_ACTIONS.petRight ? 'left' : 'right';
  const importStage = local < LAYOUT_ACTIONS.chooseFile ? null
    : local < LAYOUT_ACTIONS.importSheet ? 'file'
      : local < LAYOUT_ACTIONS.import ? 'name'
        : local < LAYOUT_ACTIONS.imported ? 'processing' : 'imported';
  const petName = importStage === 'imported' ? 'Pixel Chick (Imported)' : pet.name;
  const name = local < LAYOUT_ACTIONS.name ? 'Pocket Chick'
    : 'Pixel Chick'.slice(0, Math.min(11, Math.floor((local - LAYOUT_ACTIONS.name) / 3)));
  const menu = local >= 104 && local < LAYOUT_ACTIONS.pill ? 'style'
    : local >= 228 && local < LAYOUT_ACTIONS.chooseCustom ? 'position'
      : local >= LAYOUT_ACTIONS.camera - 24 && local < LAYOUT_ACTIONS.camera ? 'camera'
        : local >= 882 && local < LAYOUT_ACTIONS.chick ? 'pet'
          : local >= 916 && local < LAYOUT_ACTIONS.petRight ? 'side' : null;

  if (!editing) {
    cursor = {
      x: track(local, CURSOR_POINTS.map(([at, x]) => [at, x])),
      y: track(local, CURSOR_POINTS.map(([at, , y]) => [at, y])),
    };
    pressed = [LAYOUT_ACTIONS.pill, LAYOUT_ACTIONS.chooseCustom, LAYOUT_ACTIONS.camera, LAYOUT_ACTIONS.chick, LAYOUT_ACTIONS.petRight, LAYOUT_ACTIONS.chooseFile, LAYOUT_ACTIONS.importSheet, LAYOUT_ACTIONS.name, LAYOUT_ACTIONS.import].some((at) => local >= at && local < at + 6);
  }
  return {local, style, placement, rect, editing, dragging, confirmation, cursor, pressed, pets, pet, petSide, petName, importStage, name, menu};
};

export type LayoutState = ReturnType<typeof layoutStateAt>;
