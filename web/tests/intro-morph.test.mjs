import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';
import * as THREE from 'three';
import { en } from '../src/intro/copy/en.ts';

const source = readFileSync(new URL('../src/intro/main.ts', import.meta.url), 'utf8');
const introSource = stripTypeScriptTypes(source.replace(/^import .*;$/gm, ''));

function createIntroPage() {
  const geometries = [];
  const materials = [];
  const meshes = [];
  const disposals = new Map();
  const renders = [];
  const frames = [];
  const track = (resource, collection) => {
    collection.push(resource);
    resource.addEventListener('dispose', () => {
      disposals.set(resource, (disposals.get(resource) ?? 0) + 1);
    });
  };
  const node = () => ({
    classList: { add() {}, remove() {}, toggle() {} },
    dataset: {},
    appendChild() {},
    addEventListener() {},
    querySelector: () => null,
    querySelectorAll: () => [],
  });
  const context = vm.createContext({
    THREE: {
      ...THREE,
      ExtrudeGeometry: class extends THREE.ExtrudeGeometry {
        constructor(...args) {
          super(...args);
          track(this, geometries);
        }
      },
      MeshStandardMaterial: class extends THREE.MeshStandardMaterial {
        constructor(...args) {
          super(...args);
          track(this, materials);
        }
      },
      Mesh: class extends THREE.Mesh {
        constructor(...args) {
          super(...args);
          meshes.push(this);
        }
      },
      WebGLRenderer: class {
        domElement = node();
        setSize() {}
        setPixelRatio() {}
        render(scene, camera) { renders.push({ scene, camera }); }
      },
    },
    en,
    window: { innerWidth: 1280, innerHeight: 800, devicePixelRatio: 1, addEventListener() {} },
    document: { getElementById: node, createElement: node },
    performance: { now: () => 0 },
    requestAnimationFrame: (callback) => frames.push(callback),
  });
  vm.runInContext(introSource, context);
  const page = vm.runInContext('({ scene, camera, island, modules, state, animate, updateIslandMorph })', context);
  return { ...page, geometries, materials, meshes, disposals, renders, frames };
}

function shapeHeight(geometry) {
  const points = geometry.parameters.shapes.getPoints();
  return Math.max(...points.map(({ y }) => y)) - Math.min(...points.map(({ y }) => y));
}

test('the introduction renders its first frame with the original scene mesh', () => {
  const { scene, camera, island, modules, geometries, materials, meshes, renders, frames, animate } = createIntroPage();
  assert.equal(renders.length, 1);
  assert.equal(renders[0].scene, scene);
  assert.equal(renders[0].camera, camera);
  assert.equal(scene.children.filter((child) => child.isMesh).length, 5);
  assert.equal(geometries.length, 5);
  assert.equal(materials.length, 5);
  assert.equal(meshes.length, 5);
  assert.equal(island.parent, scene);
  assert.ok(scene.children.includes(island));
  assert.ok(modules.every((module) => !module.visible));
  assert.equal(shapeHeight(island.geometry), 34);
  assert.ok(frames.includes(animate));
});

test('morphing reuses the scene mesh and material and disposes each replaced geometry once', () => {
  const { scene, island, modules, state, updateIslandMorph, geometries, materials, meshes, disposals } = createIntroPage();
  const originalGeometry = island.geometry;
  const originalMaterial = island.material;
  island.position.set(7, 11, 13);
  island.rotation.set(0.1, 0.2, 0.3);
  const position = island.position.clone();
  const rotation = island.rotation.clone();

  state.phase = 1;
  updateIslandMorph(0.1);
  const intermediateGeometry = island.geometry;
  assert.notEqual(intermediateGeometry, originalGeometry);
  assert.ok(Math.abs(shapeHeight(intermediateGeometry) - 95.2) < 1e-8);
  assert.equal(disposals.get(originalGeometry), 1);
  assert.ok(modules.every((module) => module.visible));

  updateIslandMorph(0.5);
  const expandedGeometry = island.geometry;
  assert.equal(shapeHeight(expandedGeometry), 340);
  assert.equal(disposals.get(intermediateGeometry), 1);

  state.phase = 'outro';
  updateIslandMorph(0);
  assert.equal(shapeHeight(island.geometry), 34);
  assert.equal(disposals.get(expandedGeometry), 1);
  assert.ok(modules.every((module) => !module.visible));
  assert.equal(island.parent, scene);
  assert.ok(scene.children.includes(island));
  assert.ok(island.position.equals(position));
  assert.ok(island.rotation.equals(rotation));
  assert.equal(island.material, originalMaterial);
  assert.equal(meshes.length, 5);
  assert.equal(materials.length, 5);
  assert.ok(materials.every((material) => !disposals.has(material)));
  assert.equal(geometries.filter((geometry) => !disposals.has(geometry)).length, 5);
  assert.ok([...disposals.values()].every((count) => count === 1));
});

test('unchanged collapsed and expanded heights allocate no resources over repeated frames', () => {
  const { scene, island, state, updateIslandMorph, geometries, materials, meshes } = createIntroPage();
  const collapsedGeometry = island.geometry;
  for (let frame = 0; frame < 60; frame++) updateIslandMorph(frame / 60);
  assert.ok(island.geometry === collapsedGeometry, 'collapsed frames retain the same geometry');
  assert.equal(geometries.length, 5);

  state.phase = 1;
  updateIslandMorph(0.5);
  const expandedGeometry = island.geometry;
  const geometryCount = geometries.length;
  for (let frame = 0; frame < 60; frame++) updateIslandMorph(0.5 + frame / 120);
  state.phase = 2;
  updateIslandMorph(1);
  assert.ok(island.geometry === expandedGeometry, 'expanded frames retain the same geometry');
  assert.equal(geometries.length, geometryCount);
  assert.equal(materials.length, 5);
  assert.equal(meshes.length, 5);
  assert.equal(scene.children.filter((child) => child.isMesh).length, 5);
});

test('live frames keep module visibility and rotation on the rendered island through playback changes', () => {
  const { scene, island, modules, state, animate, renders } = createIntroPage();
  state.phase = 1;
  state.progress = 0;
  animate(150);
  assert.ok(modules.every((module) => !module.visible));
  animate(300);
  assert.ok(modules.every((module) => module.visible));
  animate(1500);
  assert.equal(shapeHeight(island.geometry), 340);
  assert.equal(island.rotation.x, Math.sin(1500 * 0.0003) * 0.05);
  assert.equal(island.rotation.y, Math.cos(1500 * 0.0002) * 0.1);

  state.isPlaying = false;
  const pausedGeometry = island.geometry;
  const pausedProgress = state.progress;
  animate(1800);
  assert.equal(state.progress, pausedProgress);
  assert.equal(island.geometry, pausedGeometry);
  assert.equal(island.rotation.x, Math.sin(1800 * 0.0003) * 0.05);
  assert.ok(modules.every((module) => module.visible));

  state.isPlaying = true;
  state.phase = 'outro';
  state.progress = 0;
  animate(2100);
  assert.equal(shapeHeight(island.geometry), 34);
  assert.ok(modules.every((module) => !module.visible));
  assert.equal(renders.length, 6);
  assert.ok(renders.every(({ scene: renderedScene }) => renderedScene === scene));
  assert.equal(scene.getObjectById(island.id), island);
  assert.equal(island.rotation.y, Math.cos(2100 * 0.0002) * 0.1);
});
