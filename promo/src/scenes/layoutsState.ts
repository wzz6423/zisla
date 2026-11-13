import bearSprite from '../../../mac/Resources/Pets/bear/sprite.png';
import chickSprite from '../../../mac/Resources/Pets/chick/sprite.png';
import {ease, track} from '../motion';
import {BAR_HEIGHT, NOTCH_WIDTH, STAGE} from '../theme';

export const LAYOUTS_DURATION = 1020;
export const LAYOUT_ACTIONS = {
  pill: 108,
  chooseCustom: 222,
  custom: 246,
  bottom: 330,
  left: 414,
  right: 498,
  confirm: 582,
  confirmed: 588,
  pets: 642,
  chick: 690,
  petRight: 738,
  chooseFile: 786,
  importSheet: 822,
  name: 834,
  import: 888,
  imported: 906,
} as const;

export const LAYOUT_SETTINGS = {x: 404, y: 246, width: 472, triggerX: 777, styleY: 322, positionY: 363, adjustY: 404};
export const PLACEMENT_CONFIRM = {x: 696, y: 454};

type Edge = 'top' | 'bottom' | 'left' | 'right';
type Placement = {mode: 'camera' | 'custom'; edge: Edge; offset: number; inwardDistance: number};
export type LayoutFrame = {x: number; y: number; width: number; height: number};

const CAMERA: Placement = {mode: 'camera', edge: 'top', offset: 0.5, inwardDistance: 0};
export const PLACEMENT_PREVIEW_SIZE = 24;
const ACTIVITY_THICKNESS = 32;
const ACTIVITY_LENGTH = 62;
const DRAG_FRAMES = 42;
const INSET = 8;
const CURSOR_POINTS = [
  [0, 1040, 480], [82, 777, 322], [102, 777, 400], [108, 777, 400],
  [196, 777, 363], [216, 777, 439], [222, 777, 439], [588, 696, 454],
  [622, 1040, 440], [656, 777, 322], [684, 777, 400], [690, 777, 400],
  [710, 777, 404], [732, 777, 482], [738, 777, 482], [776, 777, 363],
  [786, 777, 363], [816, 780, 432], [822, 780, 432], [834, 565, 419],
  [878, 772, 514], [888, 772, 514], [906, 772, 514], [954, 1010, 540],
] as const;

export const CUSTOM_PLACEMENTS: readonly {at: number; placement: Placement}[] = [
  {at: LAYOUT_ACTIONS.custom, placement: {mode: 'custom', edge: 'top', offset: 0.3, inwardDistance: 56}},
  {at: LAYOUT_ACTIONS.bottom, placement: {mode: 'custom', edge: 'bottom', offset: 0.65, inwardDistance: 16}},
  {at: LAYOUT_ACTIONS.left, placement: {mode: 'custom', edge: 'left', offset: 0.48, inwardDistance: 24}},
  {at: LAYOUT_ACTIONS.right, placement: {mode: 'custom', edge: 'right', offset: 0.5, inwardDistance: 56}},
];

// ScreenLayout uses bottom-up offsets on vertical edges; CSS coordinates run from the top.
export const placementFrame = (placement: Placement, preview = false): LayoutFrame => {
  if (placement.mode === 'camera') return {x: (STAGE.width - NOTCH_WIDTH - 80) / 2, y: 2, width: NOTCH_WIDTH + 80, height: ACTIVITY_THICKNESS};
  const vertical = placement.edge === 'left' || placement.edge === 'right';
  const thickness = preview ? PLACEMENT_PREVIEW_SIZE : ACTIVITY_THICKNESS;
  const length = preview ? PLACEMENT_PREVIEW_SIZE : ACTIVITY_LENGTH + (vertical ? 6 : 0);
  const width = vertical ? thickness : length;
  const height = vertical ? length : thickness;
  const gap = Math.min(thickness * 3, Math.max(INSET, placement.inwardDistance));
  const x = Math.min(STAGE.width - INSET - width, Math.max(INSET, STAGE.width * placement.offset - width / 2));
  const y = Math.min(STAGE.height - INSET - height, Math.max(INSET, STAGE.height * (1 - placement.offset) - height / 2));
  switch (placement.edge) {
    case 'top': {
      const overlapsNotch = x < (STAGE.width + NOTCH_WIDTH) / 2 && x + width > (STAGE.width - NOTCH_WIDTH) / 2 && gap < BAR_HEIGHT - 2;
      return {x, y: overlapsNotch ? BAR_HEIGHT - 2 + INSET : gap, width, height};
    }
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
  const gap = Math.min(PLACEMENT_PREVIEW_SIZE * 3, Math.max(INSET, distance - PLACEMENT_PREVIEW_SIZE / 2));
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
  const editing = local >= LAYOUT_ACTIONS.chooseCustom && local < LAYOUT_ACTIONS.confirmed;
  const dragging = editing && local >= LAYOUT_ACTIONS.custom && local < LAYOUT_ACTIONS.right + DRAG_FRAMES;
  const confirmation = Math.min(1, Math.max(0, (local - LAYOUT_ACTIONS.confirm) / 18));
  const committedPlacement = local < LAYOUT_ACTIONS.confirmed ? CAMERA : CUSTOM_PLACEMENTS[3]!.placement;
  let previewPlacement: Placement = {...CAMERA, mode: 'custom'};
  let cursor = {
    x: track(local, CURSOR_POINTS.map(([at, x]) => [at, x])),
    y: track(local, CURSOR_POINTS.map(([at, , y]) => [at, y])),
  };
  for (const step of CUSTOM_PLACEMENTS) {
    const previous = previewPlacement;
    const from = placementFrame(previous, true);
    const to = placementFrame(step.placement, true);
    if (local >= step.at + DRAG_FRAMES) previewPlacement = step.placement;
    else if (local >= step.at) {
      cursor = {
        x: ease(local, [step.at, step.at + DRAG_FRAMES], [from.x + from.width / 2, to.x + to.width / 2]),
        y: ease(local, [step.at, step.at + DRAG_FRAMES], [from.y + from.height / 2, to.y + to.height / 2]),
      };
      previewPlacement = placementNearest(cursor.x, cursor.y, previous.edge);
      break;
    }
    if (editing && local >= step.at && local < step.at + DRAG_FRAMES * 2) {
      cursor = {
        x: to.x + to.width / 2,
        y: to.y + to.height / 2,
      };
    }
  }
  if (editing && local < LAYOUT_ACTIONS.custom) {
    const from = placementFrame(previewPlacement, true);
    cursor = {
      x: ease(local, [LAYOUT_ACTIONS.chooseCustom, LAYOUT_ACTIONS.custom], [LAYOUT_SETTINGS.triggerX, from.x + from.width / 2]),
      y: ease(local, [LAYOUT_ACTIONS.chooseCustom, LAYOUT_ACTIONS.custom], [439, from.y + from.height / 2]),
    };
  } else if (editing && local >= LAYOUT_ACTIONS.right + DRAG_FRAMES) {
    const from = placementFrame(previewPlacement, true);
    cursor = {
      x: ease(local, [LAYOUT_ACTIONS.right + DRAG_FRAMES + 12, LAYOUT_ACTIONS.confirm - 6], [from.x + from.width / 2, PLACEMENT_CONFIRM.x]),
      y: ease(local, [LAYOUT_ACTIONS.right + DRAG_FRAMES + 12, LAYOUT_ACTIONS.confirm - 6], [from.y + from.height / 2, PLACEMENT_CONFIRM.y]),
    };
  }
  const pressed = dragging || [LAYOUT_ACTIONS.pill, LAYOUT_ACTIONS.chooseCustom, LAYOUT_ACTIONS.confirm, LAYOUT_ACTIONS.chick, LAYOUT_ACTIONS.petRight, LAYOUT_ACTIONS.chooseFile, LAYOUT_ACTIONS.importSheet, LAYOUT_ACTIONS.name, LAYOUT_ACTIONS.import].some((at) => local >= at && local < at + 6);
  const placement = editing ? previewPlacement : committedPlacement;
  const rect = style === 'notch' ? {x: (STAGE.width - NOTCH_WIDTH - 80) / 2, y: 0, width: NOTCH_WIDTH + 80, height: BAR_HEIGHT} : placementFrame(placement, editing);
  const pets = local >= LAYOUT_ACTIONS.pets;
  const pet = local < LAYOUT_ACTIONS.chick ? layoutPets.bear : layoutPets.chick;
  const petSide = local < LAYOUT_ACTIONS.petRight ? 'left' : 'right';
  const importStage = local < LAYOUT_ACTIONS.chooseFile ? null
    : local < LAYOUT_ACTIONS.importSheet ? 'file'
      : local < LAYOUT_ACTIONS.import ? 'name'
        : local < LAYOUT_ACTIONS.imported ? 'processing' : 'imported';
  const petName = importStage === 'imported' ? 'Pixel Chick (Imported)' : pet.name;
  const name = local < LAYOUT_ACTIONS.name ? 'Pocket Chick'
    : 'Pixel Chick'.slice(0, Math.min(11, Math.floor((local - LAYOUT_ACTIONS.name) / 3)));
  const menu = local >= 82 && local < LAYOUT_ACTIONS.pill ? 'style'
    : local >= 196 && local < LAYOUT_ACTIONS.chooseCustom ? 'position'
      : local >= 656 && local < LAYOUT_ACTIONS.chick ? 'pet'
        : local >= 710 && local < LAYOUT_ACTIONS.petRight ? 'side' : null;
  const vertical = placement.edge === 'left' || placement.edge === 'right';
  const petHeight = 24;
  const petWidth = petHeight * pet.width / pet.height;
  const petRect = {
    x: vertical ? rect.x + (rect.width - petWidth) / 2 : petSide === 'left' ? rect.x - 4 - petWidth : rect.x + rect.width + 4,
    y: vertical ? petSide === 'left' ? rect.y - 4 - petHeight : rect.y + rect.height + 4 : rect.y + (rect.height - petHeight) / 2,
    width: petWidth,
    height: petHeight,
  };
  return {local, style, placement, committedPlacement, rect, editing, dragging, confirmation, cursor, pressed, pets, pet, petSide, petRect, petName, importStage, name, menu};
};

export type LayoutState = ReturnType<typeof layoutStateAt>;
