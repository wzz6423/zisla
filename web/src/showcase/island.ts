/**
 * The island itself: the one persistent object every chapter reuses.
 *
 * It mirrors the shipped macOS surface rather than inventing a concept UI — a
 * wide rounded slab of system material with a collapsed pill inside it, an
 * expanded content plane, and a thin accent seam along the crown.
 */
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { ACCENT, FOREGROUND, MUTED, createTextTexture } from './textures';
import { clamp01, easeOutCubic, smoothstep } from './math';

export const ISLAND_WIDTH = 6.4;
export const ISLAND_HEIGHT = 0.86;
/** Resting opacity of the glass, before a chapter's crossfade weight is applied. */
const GLASS_OPACITY = 0.72;

/**
 * Glass without `transmission`: a clearcoat physical material over a low-alpha
 * base reads like the system material, costs one draw call instead of an extra
 * full-scene transmission pass, and stays smooth on integrated GPUs.
 */
const createGlassMaterial = (): THREE.MeshPhysicalMaterial =>
  new THREE.MeshPhysicalMaterial({
    // Light enough to read as a lit surface: the shipped island is system
    // material over a desktop, not a black slab in a void.
    color: 0x2f333f,
    metalness: 0.16,
    roughness: 0.14,
    clearcoat: 1,
    clearcoatRoughness: 0.06,
    transparent: true,
    opacity: 0.72,
    envMapIntensity: 2.1,
  });

export interface Island {
  group: THREE.Group;
  /** The outer slab. Scales on Z to fake the collapse/expand travel. */
  slab: THREE.Mesh;
  glassMaterial: THREE.MeshPhysicalMaterial;
  /** The small pill shown in the collapsed state. */
  pill: THREE.Mesh;
  pillMaterial: THREE.MeshBasicMaterial;
  /** Content plane revealed as the island expands. */
  content: THREE.Mesh;
  contentMaterial: THREE.MeshBasicMaterial;
  /** Accent seam along the crown, brightened while expanded. */
  seamMaterial: THREE.MeshBasicMaterial;
  /**
   * `expand` runs 0 (collapsed pill) to 1 (full tray). Every chapter drives it
   * from its own local time so the expansion always reads as one continuous move.
   */
  setExpand(expand: number): void;
  setContentOpacity(opacity: number): void;
  /** Fades the whole island with the chapter's crossfade weight. */
  setOpacity(opacity: number): void;
  dispose(): void;
}

/** Draws the fictional tray contents: status dots, bars and short labels. */
const createContentTexture = (labels: readonly string[]): THREE.CanvasTexture => {
  const width = 1024;
  const height = 256;
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d');
  if (!context) {
    throw new Error('2D canvas context is unavailable, cannot build the island content.');
  }

  context.clearRect(0, 0, width, height);
  context.fillStyle = 'rgba(9, 9, 11, 0.55)';
  context.fillRect(0, 0, width, height);

  const columns = Math.max(1, labels.length);
  const columnWidth = width / columns;

  context.textBaseline = 'middle';
  labels.forEach((label, index) => {
    const x = index * columnWidth;

    context.fillStyle = 'rgba(255, 255, 255, 0.08)';
    context.fillRect(x + 14, 26, 1, height - 52);

    context.fillStyle = ACCENT_HEX;
    context.beginPath();
    context.arc(x + 38, 52, 7, 0, Math.PI * 2);
    context.fill();

    context.fillStyle = 'rgba(250, 250, 250, 0.92)';
    context.font = '600 26px -apple-system, "SF Pro Text", "PingFang SC", sans-serif';
    context.fillText(label, x + 58, 53);

    // A deterministically sized bar stands in for live progress data.
    context.fillStyle = 'rgba(255, 255, 255, 0.14)';
    context.fillRect(x + 26, 96, columnWidth - 52, 8);
    const ratio = 0.34 + ((index * 37) % 55) / 100;
    context.fillStyle = index % 3 === 0 ? ACCENT_HEX : 'rgba(250, 250, 250, 0.55)';
    context.fillRect(x + 26, 96, (columnWidth - 52) * ratio, 8);

    context.fillStyle = 'rgba(161, 161, 170, 0.85)';
    context.font = '400 20px -apple-system, "SF Pro Text", "PingFang SC", sans-serif';
    context.fillText('12:48', x + 26, 140);
  });

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;
  return texture;
};

const ACCENT_HEX = '#c8cf3a';

export const createIsland = (contentLabels: readonly string[]): Island => {
  const group = new THREE.Group();

  const glassMaterial = createGlassMaterial();
  const slab = new THREE.Mesh(
    new RoundedBoxGeometry(ISLAND_WIDTH, ISLAND_HEIGHT, 0.34, 6, 0.17),
    glassMaterial,
  );
  group.add(slab);

  // Accent seam: a thin emissive strip that catches the crown of the slab.
  const seamMaterial = new THREE.MeshBasicMaterial({
    color: ACCENT,
    transparent: true,
    opacity: 0.25,
  });
  const seam = new THREE.Mesh(new THREE.PlaneGeometry(ISLAND_WIDTH - 0.9, 0.016), seamMaterial);
  seam.position.set(0, ISLAND_HEIGHT / 2 - 0.045, 0.176);
  group.add(seam);

  // Collapsed pill.
  const pillMaterial = new THREE.MeshBasicMaterial({
    color: FOREGROUND,
    transparent: true,
    opacity: 0.9,
  });
  const pill = new THREE.Mesh(new RoundedBoxGeometry(1.42, 0.3, 0.16, 4, 0.08), pillMaterial);
  pill.position.z = 0.05;
  group.add(pill);

  // Expanded content plane, sitting just in front of the slab.
  const contentMaterial = new THREE.MeshBasicMaterial({
    map: createContentTexture(contentLabels),
    transparent: true,
    opacity: 0,
    depthWrite: false,
  });
  const content = new THREE.Mesh(new THREE.PlaneGeometry(ISLAND_WIDTH - 0.6, 0.62), contentMaterial);
  content.position.z = 0.2;
  group.add(content);

  // Tracks the last expand value so `setOpacity` can respect the pill's dissolve.
  let lastExpand = 0;

  const setExpand = (expand: number): void => {
    const amount = clamp01(expand);
    const eased = easeOutCubic(amount);
    lastExpand = amount;

    // The slab grows taller and the seam brightens as the tray opens.
    slab.scale.y = 1 + eased * 1.62;
    seamMaterial.opacity = 0.25 + eased * 0.62;
    seam.position.y = (ISLAND_HEIGHT / 2) * slab.scale.y - 0.05 * slab.scale.y;
    seam.scale.x = 1 - eased * 0.06;

    // The pill shrinks toward the left edge and dissolves as content arrives.
    pill.scale.x = 1 - eased * 0.34;
    pill.position.x = -2.1 * eased;
    pillMaterial.opacity = 0.9 * (1 - smoothstep(amount * 1.6));

    contentMaterial.opacity = smoothstep((amount - 0.28) / 0.72);
    content.scale.set(1, 1, 1);
    content.position.y = -0.02 - eased * 0.02;
  };

  const setContentOpacity = (opacity: number): void => {
    contentMaterial.opacity = clamp01(opacity);
  };

  /** Scenes fade the island with their crossfade weight; the base opacity lives here. */
  const setOpacity = (opacity: number): void => {
    const amount = clamp01(opacity);
    glassMaterial.opacity = GLASS_OPACITY * amount;
    pillMaterial.opacity = 0.9 * amount * (1 - smoothstep(lastExpand * 1.6));
    seamMaterial.opacity = (0.25 + lastExpand * 0.62) * amount;
  };

  const dispose = (): void => {
    slab.geometry.dispose();
    glassMaterial.dispose();
    seam.geometry.dispose();
    seamMaterial.dispose();
    pill.geometry.dispose();
    pillMaterial.dispose();
    content.geometry.dispose();
    contentMaterial.map?.dispose();
    contentMaterial.dispose();
  };

  setExpand(0);

  return {
    group,
    slab,
    glassMaterial,
    pill,
    pillMaterial,
    content,
    contentMaterial,
    seamMaterial,
    setExpand,
    setContentOpacity,
    setOpacity,
    dispose,
  };
};

/** A small floating label plane used for chapter annotations. */
export interface Label3D {
  mesh: THREE.Mesh;
  material: THREE.MeshBasicMaterial;
  setOpacity(opacity: number): void;
  dispose(): void;
}

export const createLabel = (
  text: string,
  options: {
    fontSize?: number;
    color?: string;
    width?: number;
    letterSpacing?: number;
    align?: 'left' | 'center';
    /**
     * Draws the label over everything, ignoring depth. Needed when the label
     * shares a plane with geometry it must stay legible against — `renderOrder`
     * alone does not do this, because it only sorts within a pass.
     */
    alwaysOnTop?: boolean;
  } = {},
): Label3D => {
  const {
    fontSize = 44,
    color = '#fafafa',
    width = 2.4,
    letterSpacing = 1,
    align = 'center',
    alwaysOnTop = false,
  } = options;
  const { texture, aspect } = createTextTexture(text, {
    fontSize,
    color,
    letterSpacing,
    align,
    padding: 18,
  });
  const material = new THREE.MeshBasicMaterial({
    map: texture,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    depthTest: !alwaysOnTop,
  });
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, width / aspect), material);
  if (alwaysOnTop) mesh.renderOrder = 3;

  return {
    mesh,
    material,
    setOpacity: (opacity: number) => {
      material.opacity = clamp01(opacity);
    },
    dispose: () => {
      mesh.geometry.dispose();
      texture.dispose();
      material.dispose();
    },
  };
};

export const MUTED_COLOR = MUTED;