/**
 * Canvas-drawn textures.
 *
 * Every label in the animation is rendered on a 2D canvas and uploaded as a
 * texture rather than using a font loader or DOM overlay: the labels have to
 * live inside the 3D scene so they share perspective, depth of field and
 * lighting with the geometry they annotate.
 */
import * as THREE from 'three';

export interface TextOptions {
  fontSize?: number;
  color?: string;
  weight?: number;
  letterSpacing?: number;
  align?: 'left' | 'center';
  /** Extra space around the glyphs, in canvas pixels. */
  padding?: number;
  uppercase?: boolean;
}

const FONT_STACK =
  '-apple-system, "SF Pro Display", "Inter", "PingFang SC", "Noto Sans SC", "Helvetica Neue", sans-serif';

const applyLetterSpacing = (
  context: CanvasRenderingContext2D,
  text: string,
  spacing: number,
  x: number,
  y: number,
): void => {
  if (spacing === 0) {
    context.fillText(text, x, y);
    return;
  }
  let cursor = x;
  for (const char of text) {
    context.fillText(char, cursor, y);
    cursor += context.measureText(char).width + spacing;
  }
};

/**
 * Renders one line of text to a texture sized to the measured glyph run, so the
 * plane keeps a 1:1 aspect ratio and never gets stretched by the aspect fit.
 */
export const createTextTexture = (
  text: string,
  options: TextOptions = {},
): { texture: THREE.Texture; aspect: number } => {
  const {
    fontSize = 64,
    color = '#fafafa',
    weight = 500,
    letterSpacing = 0,
    align = 'center',
    padding = 24,
    uppercase = false,
  } = options;

  const content = uppercase ? text.toUpperCase() : text;
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d');
  if (!context) {
    throw new Error('2D canvas context is unavailable, cannot build the showcase labels.');
  }

  const font = `${weight} ${fontSize}px ${FONT_STACK}`;
  context.font = font;
  const metrics = context.measureText(content);
  const runWidth = metrics.width + letterSpacing * Math.max(0, content.length - 1);

  canvas.width = Math.max(8, Math.ceil(runWidth + padding * 2));
  canvas.height = Math.max(8, Math.ceil(fontSize * 1.5 + padding));

  // Re-assigning the font is required: resizing the canvas resets 2D state.
  context.font = font;
  context.textBaseline = 'middle';
  context.fillStyle = color;

  const drawX = align === 'center' ? (canvas.width - runWidth) / 2 : padding;
  applyLetterSpacing(context, content, letterSpacing, drawX, canvas.height / 2);

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 4;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.needsUpdate = true;

  return { texture, aspect: canvas.width / canvas.height };
};

/** A soft radial sprite reused for glows, dust motes and light blooms. */
export const createGlowTexture = (): THREE.Texture => {
  const size = 128;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const context = canvas.getContext('2d');
  if (!context) {
    throw new Error('2D canvas context is unavailable, cannot build the glow texture.');
  }
  const gradient = context.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, 'rgba(255, 255, 255, 1)');
  gradient.addColorStop(0.35, 'rgba(255, 255, 255, 0.42)');
  gradient.addColorStop(1, 'rgba(255, 255, 255, 0)');
  context.fillStyle = gradient;
  context.fillRect(0, 0, size, size);

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
};

/** The zisla accent, matching `--accent` in the marketing site stylesheet. */
export const ACCENT = 0xc8cf3a;
export const FOREGROUND = 0xfafafa;
export const BACKGROUND = 0x09090b;
export const MUTED = 0xa1a1aa;