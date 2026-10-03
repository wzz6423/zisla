/**
 * Shared particle field.
 *
 * A single `Points` cloud serves every chapter: chapters only change the
 * uniforms, which keeps the draw-call count flat no matter how many motes are
 * on screen and makes the field deterministic under scrubbing.
 */
import * as THREE from 'three';
import { createGlowTexture } from './textures';
import { createRandom } from './math';

export interface MoteField {
  points: THREE.Points;
  material: THREE.PointsMaterial;
  /** Unit disk of mote seeds; scenes read it to derive their own drift. */
  seeds: Float32Array;
  count: number;
  dispose(): void;
}

export const createMoteField = (count: number, seed = 20260903): MoteField => {
  const random = createRandom(seed);
  const positions = new Float32Array(count * 3);
  const seeds = new Float32Array(count * 3);

  for (let index = 0; index < count; index += 1) {
    // A flattened ellipsoid reads as depth-of-field bokeh rather than a sphere.
    const radius = 4 + random() * 16;
    const theta = random() * Math.PI * 2;
    const phi = Math.acos(2 * random() - 1);

    positions[index * 3] = radius * Math.sin(phi) * Math.cos(theta);
    positions[index * 3 + 1] = radius * Math.cos(phi) * 0.42;
    positions[index * 3 + 2] = radius * Math.sin(phi) * Math.sin(theta);

    seeds[index * 3] = random() * Math.PI * 2;
    seeds[index * 3 + 1] = 0.4 + random() * 1.6;
    seeds[index * 3 + 2] = 0.3 + random() * 0.9;
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

  const material = new THREE.PointsMaterial({
    size: 0.06,
    map: createGlowTexture(),
    color: 0xfafafa,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    sizeAttenuation: true,
  });

  const points = new THREE.Points(geometry, material);
  points.frustumCulled = false;

  return {
    points,
    material,
    seeds,
    count,
    dispose: () => {
      geometry.dispose();
      material.map?.dispose();
      material.dispose();
    },
  };
};

/**
 * Applies a per-chapter drift to the shared field.
 *
 * `spread` pushes motes outward from the origin, `swirl` rotates them around
 * the Y axis and `rise` lifts them; the remaining arguments shape the look.
 */
export const poseMoteField = (
  field: MoteField,
  options: { time: number; spread: number; swirl: number; rise: number; opacity: number; size: number },
): void => {
  const { time, spread, swirl, rise, opacity, size } = options;
  const position = field.points.geometry.getAttribute('position') as THREE.BufferAttribute;
  const array = position.array as Float32Array;

  for (let index = 0; index < field.count; index += 1) {
    const baseX = array[index * 3];
    const baseY = array[index * 3 + 1];
    const baseZ = array[index * 3 + 2];

    const phase = field.seeds[index * 3];
    const speed = field.seeds[index * 3 + 1];
    const bob = field.seeds[index * 3 + 2];

    const angle = swirl * time * speed + phase;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const scaled = 1 + spread;

    array[index * 3] = baseX * scaled * cos - baseZ * scaled * sin;
    array[index * 3 + 1] = baseY + Math.sin(time * speed + phase) * 0.18 * bob + rise * time * speed * 0.2;
    array[index * 3 + 2] = baseX * scaled * sin + baseZ * scaled * cos;
  }

  position.needsUpdate = true;
  field.material.opacity = opacity;
  field.material.size = size;
};