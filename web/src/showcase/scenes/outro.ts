/**
 * Chapter 5 — outro.
 *
 * The tray collapses back to the pill, the camera settles, and the end card
 * holds long enough to read. The loop point is designed to be seamless: at
 * local 0 the geometry matches the opening chapter's final frame.
 */
import * as THREE from 'three';
import { createIsland, type Island } from '../island';
import { createLabel, type Label3D } from '../island';
import { createMoteField, poseMoteField } from '../motes';
import { createGlowTexture } from '../textures';
import { clamp01, easeOutCubic, progress, smoothstep } from '../math';

export interface OutroOptions {
  product: string;
  tagline: string;
  cta: string;
}

export interface OutroScene {
  group: THREE.Group;
  island: Island;
  update(local: number, weight: number): void;
  dispose(): void;
}

export const createOutroScene = (options: OutroOptions): OutroScene => {
  const group = new THREE.Group();

  const motes = createMoteField(700, 31337);
  group.add(motes.points);

  const island = createIsland([]);
  island.group.position.set(0, 0.9, 0);
  group.add(island.group);

  // The DOM overlay carries this chapter's title and caption, so the end card
  // only adds what the overlay cannot: the wordmark mark and the URL. The CTA
  // sits high enough to clear the transport bar.
  const product: Label3D = createLabel(options.product, {
    fontSize: 108,
    color: '#fafafa',
    width: 4.4,
    letterSpacing: 8,
  });
// Above the island, below the DOM title block in the upper left.
  product.mesh.position.set(0, 2.05, 0);
  group.add(product.mesh);

  const cta: Label3D = createLabel(options.cta, {
    fontSize: 26,
    color: '#c8cf3a',
    width: 3.6,
    letterSpacing: 2,
  });
  cta.mesh.position.set(0, -1.05, 0);
  group.add(cta.mesh);

  // A single hairline under the wordmark, drawn left to right.
  const ruleMaterial = new THREE.MeshBasicMaterial({
    color: 0xc8cf3a,
    transparent: true,
    opacity: 0,
  });
  const rule = new THREE.Mesh(new THREE.PlaneGeometry(1, 0.018), ruleMaterial);
  rule.position.set(0, 1.52, 0);
  group.add(rule);

  const glowMaterial = new THREE.SpriteMaterial({
    map: createGlowTexture(),
    color: 0xc8cf3a,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const glow = new THREE.Sprite(glowMaterial);
  glow.scale.set(15, 9, 1);
  glow.position.set(0, 0.9, -2.8);
  group.add(glow);

  const update = (local: number, weight: number): void => {
    const visible = clamp01(weight);

    // Collapse from fully open to the resting pill over the first 1.8s.
    const collapse = easeOutCubic(progress(local, 0.2, 1.8));
    island.setExpand(1 - collapse);
    island.group.position.y = 0.9 + (1 - collapse) * 0.4;
    island.setOpacity(visible);

    product.setOpacity(smoothstep(progress(local, 0.9, 2.1)) * visible);
    cta.setOpacity(smoothstep(progress(local, 2.5, 3.8)) * visible);

    const ruleProgress = easeOutCubic(progress(local, 1.4, 3.1));
    rule.scale.x = 3.4 * ruleProgress;
    ruleMaterial.opacity = smoothstep(progress(local, 1.4, 2)) * 0.8 * visible;

    glowMaterial.opacity = (0.06 + 0.05 * Math.sin(local * 0.8)) * visible * collapse;

    poseMoteField(motes, {
      time: local,
      spread: -0.06,
      swirl: 0.03,
      rise: 0.02,
      opacity: 0.15 * visible,
      size: 0.05,
    });
  };

  const dispose = (): void => {
    motes.dispose();
    island.dispose();
    product.dispose();
    cta.dispose();
    rule.geometry.dispose();
    ruleMaterial.dispose();
    glowMaterial.map?.dispose();
    glowMaterial.dispose();
  };

  return { group, island, update, dispose };
};