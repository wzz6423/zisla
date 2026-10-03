/**
 * Chapter 4 — how it works.
 *
 * Four technical claims, each staged as a small diorama that appears beside the
 * island rather than as text on a slide. The focus test is the centrepiece: a
 * second window stays put and keeps its own content while the island expands in
 * front of it, which is exactly the behaviour the README claims.
 */
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { createIsland, type Island } from '../island';
import { createLabel, type Label3D } from '../island';
import { createMoteField, poseMoteField } from '../motes';
import { ACCENT } from '../textures';
import { clamp01, easeOutCubic, envelope, progress } from '../math';

export interface HighlightsScene {
  group: THREE.Group;
  island: Island;
  update(local: number, weight: number): void;
  dispose(): void;
}

interface Row {
  group: THREE.Group;
  label: Label3D;
  markMaterial: THREE.MeshBasicMaterial;
  windowMaterial?: THREE.MeshStandardMaterial;
}

const ROW_GAP = 1.16;

/** A small window with abstract text lines, used for the focus demonstration. */
const createBackdropWindow = (): {
  group: THREE.Group;
  materials: THREE.MeshStandardMaterial[];
  lines: THREE.MeshBasicMaterial[];
} => {
  const group = new THREE.Group();
  const materials: THREE.MeshStandardMaterial[] = [];
  const lines: THREE.MeshBasicMaterial[] = [];

  const frame = new THREE.MeshStandardMaterial({
    color: 0x1a1c22,
    roughness: 0.78,
    metalness: 0.08,
    transparent: true,
    opacity: 0,
  });
  materials.push(frame);
  const body = new THREE.Mesh(new RoundedBoxGeometry(4.6, 3.9, 0.16, 4, 0.11), frame);
  group.add(body);

  // Three lines only, stacked in the upper half so the claim rows below have
  // their own space.
  for (let index = 0; index < 3; index += 1) {
    const lineMaterial = new THREE.MeshBasicMaterial({
      color: index === 0 ? ACCENT : 0x8b8d98,
      transparent: true,
      opacity: 0,
    });
    lines.push(lineMaterial);
    const bar = new THREE.Mesh(
      new THREE.PlaneGeometry(index === 0 ? 2.1 : 3.4 - index * 0.42, 0.09),
      lineMaterial,
    );
    bar.position.set(-0.5, 1.32 - index * 0.4, 0.1);
    group.add(bar);
  }

  return { group, materials, lines };
};

export const createHighlightsScene = (rows: readonly string[]): HighlightsScene => {
  const group = new THREE.Group();

  const motes = createMoteField(360, 9091);
  group.add(motes.points);

  const island = createIsland([]);
  // Pushed right and back so the island never sits under the DOM title block in
  // the upper left, and the claim rows own the left half of the frame.
  island.group.position.set(2.5, 0.95, 0.6);
  island.group.scale.setScalar(0.8);
  group.add(island.group);

  // The window that must not be disturbed while the island expands.
  const backdrop = createBackdropWindow();
  backdrop.group.position.set(-4.7, 0.1, -2.2);
  backdrop.group.rotation.y = 0.42;
  group.add(backdrop.group);

  // The backdrop window is turned to face the camera's left, so its rows are
    // parented to it and counter-rotated back to front-facing; a label plane
    // parented directly to a rotated group would render its text mirrored.
    const rowsAnchor = new THREE.Group();
    rowsAnchor.position.copy(backdrop.group.position);
    rowsAnchor.rotation.copy(backdrop.group.rotation);
    group.add(rowsAnchor);

    const rowGroups: Row[] = rows.map((text, index) => {
      const container = new THREE.Group();
      // Rows sit inside the window's lower half, clear of its title bar.
      container.position.set(0, -0.55 - index * ROW_GAP, 0.5);

      const markMaterial = new THREE.MeshBasicMaterial({
        color: ACCENT,
        transparent: true,
        opacity: 0,
        depthTest: false,
        depthWrite: false,
      });
      const mark = new THREE.Mesh(new THREE.PlaneGeometry(0.16, 0.16), markMaterial);
      mark.position.set(-1.92, 0, 0);
      mark.renderOrder = 3;
      container.add(mark);

      const label = createLabel(text, {
    fontSize: 30,
      color: '#f4f4f5',
      width: 3.5,
      align: 'left',
      alwaysOnTop: true,
    });
      label.mesh.position.set(-1.74, 0, 0);
      container.add(label.mesh);

      // Cancel the anchor's Y rotation so the text faces the camera squarely.
      container.rotation.y = -backdrop.group.rotation.y;
      rowsAnchor.add(container);
      return { group: container, label, markMaterial };
    });

  // A scan line sweeps the island to suggest a single material being sampled.
  const scanMaterial = new THREE.MeshBasicMaterial({
    color: ACCENT,
    transparent: true,
    opacity: 0,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  });
  const scan = new THREE.Mesh(new THREE.PlaneGeometry(0.06, 1.8), scanMaterial);
  scan.position.set(2.5, 0.95, 1.5);
  group.add(scan);

  const focusRingMaterial = new THREE.MeshBasicMaterial({
    color: ACCENT,
    transparent: true,
    opacity: 0,
  });
// The ring marks the untouched window's title bar.
  const focusRing = new THREE.Mesh(new THREE.RingGeometry(0.22, 0.27, 48), focusRingMaterial);
  focusRing.position.set(-2.62, 1.32, -2.05);
  focusRing.rotation.y = 0.42;
  group.add(focusRing);

  const update = (local: number, weight: number): void => {
    const visible = clamp01(weight);

    // Row 0 lands with the island expansion; the other three follow on a stagger.
    rowGroups.forEach((row, index) => {
      const amount =
        index === 0
          ? envelope(local, 0.3, 1.5, 12.6, 1.8)
          : envelope(local, 3.4 + (index - 1) * 2.3, 1.4, 12.6, 1.8);
      const entrance = easeOutCubic(amount);

      // Entrance slides in from the left and settles onto its resting row.
      row.group.position.x = (1 - entrance) * -0.7;
      row.group.position.y = -0.55 - index * ROW_GAP + (1 - entrance) * 0.24;
      row.label.setOpacity(amount * visible);
      // Each mark breathes on its own phase so the list never blinks in unison.
      row.markMaterial.opacity = amount * visible * (0.6 + 0.3 * Math.sin(local * 2 + index));
    });

    // The focus claim: island opens while the backdrop window keeps its content
    // and never brightens — the visual proof that no activation happened.
    const expand = easeOutCubic(progress(local, 0.3, 2.2)) * (1 - 0.9 * progress(local, 11.4, 13.6));
    island.setExpand(expand);
    island.group.position.y = 0.95 + Math.sin(local * 0.42) * 0.025;
    island.setOpacity(visible);

    const windowAmount = envelope(local, 0.9, 1.6, 11.8, 1.6);
    backdrop.materials.forEach((material) => {
      material.opacity = windowAmount * visible * 0.72;
    });
    backdrop.lines.forEach((line, index) => {
      // Content stays at a constant level: no activation, no highlight.
      line.opacity = windowAmount * visible * (index === 0 ? 0.6 : 0.34);
    });
    focusRingMaterial.opacity = windowAmount * visible * 0.34 * (1 - progress(local, 8.4, 9.6));

    // The scan sweeps across the island's own width, not the whole frame.
    const scanProgress = progress(local, 4.6, 8.2);
    const scanActive = scanProgress > 0 && scanProgress < 1;
    scan.position.x = 0.1 + scanProgress * 4.8;
    scanMaterial.opacity = scanActive ? 0.42 * visible : 0;

    poseMoteField(motes, {
      time: local,
      spread: 0.02,
      swirl: 0.03,
      rise: 0.015,
      opacity: 0.1 * visible,
      size: 0.045,
    });
  };

  const dispose = (): void => {
    motes.dispose();
    island.dispose();
    backdrop.group.traverse((child) => {
      if (child instanceof THREE.Mesh) child.geometry.dispose();
    });
    backdrop.materials.forEach((material) => material.dispose());
    backdrop.lines.forEach((material) => material.dispose());
    rowGroups.forEach((row) => {
      row.group.traverse((child) => {
        if (child instanceof THREE.Mesh) child.geometry.dispose();
      });
      row.markMaterial.dispose();
      row.label.dispose();
    });
    scan.geometry.dispose();
    scanMaterial.dispose();
    focusRing.geometry.dispose();
    focusRingMaterial.dispose();
  };

  return { group, island, update, dispose };
};