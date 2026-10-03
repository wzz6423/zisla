/**
 * Chapter 1 — opening.
 *
 * The zisla wordmark resolves out of the mote field, then the island rises and
 * settles. Motion is deliberately slow: PRODUCT.md asks for restraint, and the
 * first thing the viewer should feel is "quiet", not "demo reel".
 */
import * as THREE from 'three';
import { createIsland, type Island } from '../island';
import { createLabel, type Label3D } from '../island';
import { createMoteField, poseMoteField } from '../motes';
import { createGlowTexture } from '../textures';
import { clamp01, easeOutCubic, progress, smoothstep } from '../math';

export interface OpeningScene {
  group: THREE.Group;
  island: Island;
  update(local: number, weight: number): void;
  dispose(): void;
}

export const createOpeningScene = (): OpeningScene => {
  const group = new THREE.Group();

  const motes = createMoteField(900);
  group.add(motes.points);

  const wordmark: Label3D = createLabel('zisla', {
    fontSize: 128,
    color: '#fafafa',
    width: 5.2,
    letterSpacing: 6,
  });
  // Sits well above the island so the two never read as overlapping type.
  wordmark.mesh.position.set(0, 1.85, 0);
  group.add(wordmark.mesh);

  // No 3D tagline here: the DOM overlay already carries this chapter's caption,
  // and a second copy of the same sentence in the scene reads as a mistake.

  // A soft halo behind the island sells the "light from above" idea.
  const haloMaterial = new THREE.SpriteMaterial({
    map: createGlowTexture(),
    color: 0xc8cf3a,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const halo = new THREE.Sprite(haloMaterial);
  halo.scale.set(16, 16, 1);
  halo.position.set(0, 1.8, -2.4);
  group.add(halo);

  const island = createIsland([]);
  island.group.position.set(0, -2.9, 0);
  island.group.scale.setScalar(0.7);
  group.add(island.group);

  const update = (local: number, weight: number): void => {
    const visible = clamp01(weight);

    // Wordmark fades up first, then the island rises beneath it.
    wordmark.setOpacity(smoothstep(progress(local, 0.1, 1.5)) * visible);
    wordmark.mesh.position.y = 1.85 + (1 - easeOutCubic(progress(local, 0.1, 2.2))) * 0.34;

    const rise = easeOutCubic(progress(local, 2.2, 5.4));
    island.group.position.y = -2.9 + rise * 2.9;
    island.group.scale.setScalar(0.7 + rise * 0.3);
    island.group.rotation.z = (1 - rise) * -0.06;
    island.setOpacity(visible);
    // The pill only appears once the island has almost settled, so the rise
    // reads as the slab landing before anything appears inside it.
    island.pillMaterial.opacity *= smoothstep(progress(local, 3.2, 4.4));
    island.seamMaterial.opacity *= 0.4;
    haloMaterial.opacity = 0.1 * rise * visible;

    poseMoteField(motes, {
      time: local,
      spread: -0.12 * (1 - rise),
      swirl: 0.05,
      rise: 0.04,
      opacity: (0.16 + 0.2 * (1 - rise)) * visible,
      size: 0.055,
    });
  };

  const dispose = (): void => {
    motes.dispose();
    wordmark.dispose();
    haloMaterial.map?.dispose();
    haloMaterial.dispose();
    island.dispose();
  };

  return { group, island, update, dispose };
};