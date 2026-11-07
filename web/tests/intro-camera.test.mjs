import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import * as THREE from 'three';

const source = readFileSync(new URL('../src/intro/main.ts', import.meta.url), 'utf8');
// Isolate rendering and animation while retaining the real scene, geometry, camera, and resize code.
const sceneSource = stripTypeScriptTypes(
  source.slice(source.indexOf('// Constants'), source.indexOf('// Animation state'))
  + source.slice(source.indexOf('// Handle resize'), source.indexOf('// Start'))
);

const createScene = (height, t) => {
  let onResize;
  const window = {
    innerWidth: 1440, innerHeight: 900, devicePixelRatio: 1,
    addEventListener: (_type, callback) => { onResize = callback; },
  };
  const context = vm.createContext({
    THREE: {
      ...THREE,
      WebGLRenderer: class {
        domElement = {};
        setSize() {}
        setPixelRatio() {}
      },
    },
    window,
    document: { getElementById: () => ({ appendChild() {} }) },
  });
  // Exercise both heights through the production factory without invoking the morph lifecycle.
  vm.runInContext(sceneSource.replace('ISLAND_WIDTH, ISLAND_HEIGHT_COLLAPSED', `ISLAND_WIDTH, ${height}`), context);
  const scene = vm.runInContext('({ scene, camera, island, modules })', context);
  t.after(() => scene.scene.traverse((object) => {
    if (object.isMesh) {
      object.geometry.dispose();
      object.material.dispose();
    }
  }));
  return {
    ...scene,
    resize(width, height) {
      window.innerWidth = width;
      window.innerHeight = height;
      onResize();
    },
  };
};

const clipVolume = new THREE.Box3(new THREE.Vector3(-1, -1, -1), new THREE.Vector3(1, 1, 1));
const projectGeometry = (mesh, camera) => {
  mesh.updateMatrixWorld(true);
  camera.updateMatrixWorld(true);
  const positions = mesh.geometry.getAttribute('position');
  const vertices = Array.from({ length: positions.count }, (_, index) => new THREE.Vector3()
    .fromBufferAttribute(positions, index).applyMatrix4(mesh.matrixWorld).project(camera));
  let intersects = false;
  for (let index = 0; index < vertices.length && !intersects; index += 3) {
    intersects = clipVolume.intersectsTriangle(new THREE.Triangle(...vertices.slice(index, index + 3)));
  }
  return {
    minDepth: Math.min(...vertices.map(({ z }) => z)),
    maxDepth: Math.max(...vertices.map(({ z }) => z)),
    intersects,
  };
};

const heights = ['ISLAND_HEIGHT_COLLAPSED', 'ISLAND_HEIGHT_EXPANDED'];
const rotations = [-0.05, 0, 0.05].flatMap((x) => [-0.1, 0, 0.1].map((y) => [x, y]));

test('legacy far plane clips the real island and every module', (t) => {
  const { camera, island, modules } = createScene(heights[0], t);
  camera.far = 1000;
  camera.updateProjectionMatrix();
  for (const [index, mesh] of [island, ...modules].entries()) {
    const projection = projectGeometry(mesh, camera);
    assert.ok(projection.minDepth > 1, `mesh ${index}: every vertex must lie past the legacy far plane`);
    assert.equal(projection.intersects, false, `mesh ${index}: legacy camera must clip every triangle`);
  }
});

test('camera depth covers both island heights, rotation limits, and every module', (t) => {
  for (const height of heights) {
    const { camera, island, modules } = createScene(height, t);
    for (const [x, y] of rotations) {
      island.rotation.set(x, y, 0);
      for (const [index, mesh] of [island, ...modules].entries()) {
        const { minDepth, maxDepth } = projectGeometry(mesh, camera);
        assert.ok(minDepth >= -1 && maxDepth <= 1,
          `${height}, rotation ${x}/${y}, mesh ${index}: projected depth ${minDepth}..${maxDepth} must stay inside [-1, 1]`);
      }
    }
  }
});

test('source resize keeps real geometry in the frustum on wide and portrait viewports', (t) => {
  for (const height of heights) {
    const { camera, island, modules, resize } = createScene(height, t);
    for (const [width, viewportHeight] of [[1440, 900], [390, 844], [2560, 1440]]) {
      resize(width, viewportHeight);
      for (const [x, y] of rotations) {
        island.rotation.set(x, y, 0);
        for (const [index, mesh] of [island, ...modules].entries()) {
          assert.equal(projectGeometry(mesh, camera).intersects, true,
            `${height}, ${width}x${viewportHeight}, rotation ${x}/${y}, mesh ${index}: a real triangle must intersect the clip volume`);
        }
      }
    }
  }
});
