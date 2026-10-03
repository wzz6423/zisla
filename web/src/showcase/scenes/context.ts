/**
 * Chapter 2 — the problem.
 *
 * Six fictional source apps drift in as dim slabs, scattered and unreadable,
 * then converge toward the island. This is the only place the animation shows
 * clutter; PRODUCT.md explicitly rejects generic SaaS card walls, so the slabs
 * stay abstract (no fake UI chrome, no invented company logos) and never
 * resolve into a screenshot.
 */
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { createLabel, type Label3D } from '../island';
import { createMoteField, poseMoteField } from '../motes';
import { ACCENT, createGlowTexture } from '../textures';
import { clamp01, easeInOutCubic, easeOutCubic, progress, smoothstep } from '../math';

export interface ContextScene {
  group: THREE.Group;
  update(local: number, weight: number): void;
  dispose(): void;
}

interface SourceSlab {
  group: THREE.Group;
  label: Label3D;
  material: THREE.MeshStandardMaterial;
  accentMaterial: THREE.MeshBasicMaterial;
  /** Scatter position, and the tight position it converges to. */
  from: THREE.Vector3;
  to: THREE.Vector3;
  delay: number;
  spin: number;
}

export const createContextScene = (sources: readonly string[]): ContextScene => {
  const group = new THREE.Group();

  const motes = createMoteField(520, 771);
  group.add(motes.points);

  const slabs: SourceSlab[] = sources.map((name, index) => {
    const angle = (index / sources.length) * Math.PI * 2 + 0.4;
    const radius = 4.4 + (index % 3) * 1.5;
    const height = 1.5 + (index % 2) * 1.5;

    const container = new THREE.Group();
    container.position.set(
      Math.cos(angle) * radius,
      height * (index % 2 === 0 ? 1 : 0.35),
      Math.sin(angle) * radius * 0.55 - 1.2,
    );

    const material = new THREE.MeshStandardMaterial({
      color: 0x2a2c34,
      roughness: 0.52,
      metalness: 0.16,
      transparent: true,
      opacity: 0,
    });
    const mesh = new THREE.Mesh(new RoundedBoxGeometry(2.3, 1.36, 0.14, 4, 0.1), material);
    container.add(mesh);

    // A single accent bar per slab hints at "live" without faking any UI.
    const accentMaterial = new THREE.MeshBasicMaterial({
      color: ACCENT,
      transparent: true,
      opacity: 0,
    });
    const bar = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 0.045), accentMaterial);
    bar.position.set(0, 0.42, 0.08);
    container.add(bar);

    const label = createLabel(name, { fontSize: 30, color: '#e4e4e7', width: 1.7 });
    label.mesh.position.set(0, -0.18, 0.08);
    container.add(label.mesh);

    group.add(container);

    return {
      group: container,
      label,
      material,
      accentMaterial,
      from: container.position.clone(),
      to: new THREE.Vector3(
        (index - (sources.length - 1) / 2) * 0.86,
        1.15 + (index % 2) * 0.2,
        0.6,
      ),
      delay: index * 0.42,
      spin: (index % 2 === 0 ? 1 : -1) * (0.5 + index * 0.08),
    };
  });

  // The gathering glow behind the convergence point.
  const glowMaterial = new THREE.SpriteMaterial({
    map: createGlowTexture(),
    color: ACCENT,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const glow = new THREE.Sprite(glowMaterial);
  glow.scale.set(11, 7, 1);
  glow.position.set(0, 1.3, -0.6);
  group.add(glow);

  const temp = new THREE.Vector3();

  const update = (local: number, weight: number): void => {
    const visible = clamp01(weight);

    // Slabs arrive scattered, hold long enough to read, then converge.
    const converge = easeInOutCubic(progress(local, 4.4, 8.2));
    // 0 until the exit window opens, then ramping to 1. Negating this instead
    // would read as "leave immediately" and blank the whole chapter.
    const leave = easeOutCubic(progress(local, 8.2, 9.2));

    slabs.forEach((slab) => {
      const localArrive = smoothstep(progress(local, slab.delay, slab.delay + 1.5));

      temp.copy(slab.from).lerp(slab.to, converge);
      slab.group.position.copy(temp);

      // Idle float before convergence, so the scatter never looks frozen.
      if (converge < 0.999) {
        const float = Math.sin(local * 0.7 + slab.delay * 3) * 0.16;
        slab.group.position.x += float * slab.spin;
        slab.group.position.y += Math.cos(local * 0.55 + slab.delay * 2) * 0.1;
        slab.group.rotation.z = Math.sin(local * 0.4 + slab.delay) * 0.05 * slab.spin;
      } else {
        slab.group.rotation.z *= 0.9;
      }

      slab.group.position.y -= leave * 1.4;
      slab.group.scale.setScalar(1 - leave * 0.35);

      const opacity = localArrive * visible * (1 - leave);
      slab.material.opacity = 0.82 * opacity;
      slab.label.setOpacity(opacity * 0.95);
      // Accent bars pulse out of phase so the six slabs never blink together.
      slab.accentMaterial.opacity = opacity * (0.35 + 0.45 * (0.5 + 0.5 * Math.sin(local * 1.6 + slab.delay * 4)));
    });

    glowMaterial.opacity = converge * visible * 0.2;

    poseMoteField(motes, {
      time: local,
      spread: 0.1 * (1 - converge),
      swirl: 0.08 * (1 - converge),
      rise: 0.02,
      opacity: (0.1 + 0.14 * (1 - converge)) * visible * (1 - leave),
      size: 0.05,
    });
  };

  const dispose = (): void => {
    motes.dispose();
    slabs.forEach((slab) => {
      slab.group.children.forEach((child) => {
        if (child instanceof THREE.Mesh) child.geometry.dispose();
      });
      slab.material.dispose();
      slab.accentMaterial.dispose();
      slab.label.dispose();
    });
    glowMaterial.map?.dispose();
    glowMaterial.dispose();
  };

  return { group, update, dispose };
};