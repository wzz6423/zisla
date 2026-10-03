/**
 * Chapter 3 — what it does.
 *
 * The island opens and six module cards fan out beneath it. Cards rise on a
 * stagger, hold, and dim again; the island stays expanded for the whole chapter
 * so the tray reads as one continuous surface rather than a slideshow.
 */
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { createIsland, type Island } from '../island';
import { createLabel, type Label3D } from '../island';
import { createMoteField, poseMoteField } from '../motes';
import { ACCENT, createGlowTexture } from '../textures';
import { clamp01, easeOutBack, easeOutCubic, progress, smoothstep } from '../math';

export interface FeaturesScene {
  group: THREE.Group;
  island: Island;
  update(local: number, weight: number): void;
  /**
   * Switches the card row between a wide single line and a compact two-column
   * grid, so a narrow window never crops the outer cards.
   */
  setLayout(width: number): void;
  dispose(): void;
}

interface ModuleCard {
  group: THREE.Group;
  label: Label3D;
  material: THREE.MeshPhysicalMaterial;
  accentMaterial: THREE.MeshBasicMaterial;
  /** The three abstract content bars, kept by reference so opacity is cheap. */
  barMaterials: THREE.MeshBasicMaterial[];
  /** Index in the row, used for the stagger and the reading wave. */
  index: number;
  /** Resting position for the current layout. */
  restPosition: THREE.Vector3;
}

const CARD_GAP = 1.62;

export const createFeaturesScene = (chips: readonly string[]): FeaturesScene => {
  const group = new THREE.Group();

  const motes = createMoteField(420, 4242);
  group.add(motes.points);

  const island = createIsland(chips.slice(0, 6));
  island.group.position.set(0, 1.5, 0);
  group.add(island.group);

  const cards: ModuleCard[] = chips.map((name, index) => {
    const container = new THREE.Group();
    const column = index - (chips.length - 1) / 2;
    container.position.set(column * CARD_GAP, -0.55, 0.4 + Math.abs(column) * 0.22);

    const material = new THREE.MeshPhysicalMaterial({
      color: 0x161820,
      roughness: 0.24,
      metalness: 0.2,
      clearcoat: 0.9,
      clearcoatRoughness: 0.14,
      transparent: true,
      opacity: 0,
    });
    const mesh = new THREE.Mesh(new RoundedBoxGeometry(1.42, 1.66, 0.12, 4, 0.09), material);
    container.add(mesh);

    const accentMaterial = new THREE.MeshBasicMaterial({
      color: ACCENT,
      transparent: true,
      opacity: 0,
    });
    const accent = new THREE.Mesh(new THREE.PlaneGeometry(0.62, 0.05), accentMaterial);
    accent.position.set(0, 0.52, 0.07);
    container.add(accent);

    // Abstract content marks: bars only, no fabricated controls or icons.
    const barMaterials: THREE.MeshBasicMaterial[] = [];
    for (let row = 0; row < 3; row += 1) {
      const barMaterial = new THREE.MeshBasicMaterial({
        color: 0xe4e4e7,
        transparent: true,
        opacity: 0,
      });
      barMaterials.push(barMaterial);
      const bar = new THREE.Mesh(
        new THREE.PlaneGeometry(0.9 - row * 0.16, 0.045),
        barMaterial,
      );
      bar.position.set(-0.05, 0.28 - row * 0.19, 0.07);
      container.add(bar);
    }

    const label = createLabel(name, { fontSize: 28, color: '#fafafa', width: 1.24 });
    label.mesh.position.set(0, -0.62, 0.07);
    container.add(label.mesh);

    group.add(container);

    return {
      group: container,
      label,
      material,
      accentMaterial,
      barMaterials,
      index,
      restPosition: container.position.clone(),
    };
  });

  /**
   * Wide viewports get a single line of six cards; narrow ones get a 3x2 grid,
   * because a six-across row simply does not fit a phone-width frame.
   */
  const setLayout = (width: number): void => {
    const compact = width < 760;
    const columns = compact ? 3 : chips.length;
    const gap = compact ? 1.34 : CARD_GAP;
    const scale = compact ? 0.62 : 1;

    cards.forEach((card) => {
      const column = card.index % columns;
      const row = Math.floor(card.index / columns);
      const offset = column - (columns - 1) / 2;
      // Rows share a Z plane: pushing lower rows back would skew the grid into
      // a diagonal once perspective is applied.
      card.restPosition.set(offset * gap, (compact ? -0.5 : -0.55) - row * 1.42, 0.4 + Math.abs(offset) * 0.22);
      card.group.userData.restScale = scale;
    });

    island.group.scale.setScalar(compact ? 0.56 : 1);
    island.group.position.y = compact ? 1.95 : 1.5;
    underglow.scale.set(compact ? 8 : 13, compact ? 4 : 5, 1);
  };

  const underglowMaterial = new THREE.SpriteMaterial({
    map: createGlowTexture(),
    color: ACCENT,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const underglow = new THREE.Sprite(underglowMaterial);
  underglow.scale.set(13, 5, 1);
  underglow.position.set(0, 0.2, -1.1);
  group.add(underglow);

  const update = (local: number, weight: number): void => {
    const visible = clamp01(weight);

    // The tray opens across the first 2.4s and stays open.
    const expand = easeOutCubic(progress(local, 0.2, 2.4)) * (1 - 0.12 * progress(local, 12.6, 14.4));
    island.setExpand(expand);
    island.group.position.y = (island.group.scale.x < 0.9 ? 1.95 : 1.5) + Math.sin(local * 0.5) * 0.03;
    island.setOpacity(visible);

    // A highlight wave travels across the row twice.
    const wave = progress(local, 5.2, 8.6);
    cards.forEach((card) => {
      const delay = card.index * 0.16;
      const entrance = easeOutBack(progress(local, 1.6 + delay, 3.1 + delay));
      const exit = 1 - easeOutCubic(progress(local, 12.4, 14.2));

      // Entrance rises from the layout's resting spot, so a grid reflow applies too.
      // x/z are re-applied every frame because `setLayout` may have moved them
      // while this card was off-screen.
      card.group.position.x = card.restPosition.x;
      card.group.position.z = card.restPosition.z;
      card.group.position.y = card.restPosition.y + (1 - entrance) * -2.4;
      const restScale = (card.group.userData.restScale as number | undefined) ?? 1;
      card.group.scale.setScalar(restScale * (0.72 + entrance * 0.28));
      card.group.rotation.y = (1 - entrance) * 0.5;

      // Wave position moves across the row; each card lights as it passes.
      const waveDistance = Math.abs(wave * (cards.length + 1.6) - card.index - 0.8);
      const highlight = wave > 0 && wave < 1 ? Math.exp(-waveDistance * waveDistance * 2.4) : 0;

      const opacity = visible * exit * smoothstep(progress(local, 1.6 + delay, 2.4 + delay));
      card.material.opacity = (0.72 + highlight * 0.24) * opacity;
      card.label.setOpacity(opacity);
      card.accentMaterial.opacity = opacity * (0.3 + highlight * 0.62);
      card.barMaterials.forEach((material, order) => {
        material.opacity = opacity * Math.max(0.08, 0.26 + highlight * 0.3 - order * 0.05);
      });
    });

    underglowMaterial.opacity = (0.12 + 0.1 * (wave > 0 && wave < 1 ? 1 : 0)) * visible;

    poseMoteField(motes, {
      time: local,
      spread: 0.05,
      swirl: 0.04,
      rise: 0.03,
      opacity: 0.13 * visible,
      size: 0.05,
    });
  };

  const dispose = (): void => {
    motes.dispose();
    island.dispose();
    cards.forEach((card) => {
      card.group.traverse((child) => {
        if (child instanceof THREE.Mesh) {
          child.geometry.dispose();
          const material = child.material as THREE.Material | THREE.Material[];
          if (Array.isArray(material)) material.forEach((entry) => entry.dispose());
          else material.dispose();
        }
      });
      card.label.dispose();
    });
    underglowMaterial.map?.dispose();
    underglowMaterial.dispose();
  };

  return { group, island, update, setLayout, dispose };
};