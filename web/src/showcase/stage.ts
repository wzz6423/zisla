/**
 * Renderer, camera, lighting rig and post-processing chain.
 *
 * The stage owns everything that is not chapter-specific, so scenes can be
 * written as pure "given a local time, pose my objects" modules.
 */
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { ACCENT, BACKGROUND } from './textures';

export interface Stage {
  renderer: THREE.WebGLRenderer;
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  composer: EffectComposer;
  bloom: UnrealBloomPass;
  container: HTMLElement;
  canvas: HTMLCanvasElement;
  setSize(width: number, height: number): void;
  render(elapsed: number): void;
  dispose(): void;
}

export const BASE_FOV = 38;

export const createStage = (container: HTMLElement): Stage => {
  const canvas = document.createElement('canvas');
  canvas.className = 'showcase-canvas';
  container.append(canvas);

  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    powerPreference: 'high-performance',
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(BACKGROUND);
  // A shallow fog keeps the far chapter props from competing with the island.
  scene.fog = new THREE.FogExp2(BACKGROUND, 0.055);

  const camera = new THREE.PerspectiveCamera(BASE_FOV, 1, 0.1, 120);
  camera.position.set(0, 0.6, 12);

  // An environment map gives the glass and metal something to reflect; without
  // it, MeshPhysicalMaterial reads as flat grey under a single light.
  const pmrem = new THREE.PMREMGenerator(renderer);
  const environmentScene = new RoomEnvironment();
  const environment = pmrem.fromScene(environmentScene, 0.04);
  scene.environment = environment.texture;
  scene.environmentIntensity = 0.35;
  environmentScene.dispose?.();
  pmrem.dispose();

  // Three-point rig: a soft key from the front-left, a cool rim from behind,
  // and a dim accent bounce that ties the scene to the brand colour.
  const key = new THREE.DirectionalLight(0xfff4e0, 2.1);
  key.position.set(-4, 6, 7);
  scene.add(key);

  const rim = new THREE.DirectionalLight(0x9fb4ff, 1.5);
  rim.position.set(5, 2, -6);
  scene.add(rim);

  // A dim accent bounce that ties the scene to the brand colour. Kept off-centre
  // and low: on the optical axis it reads as a lens flare across the island.
  const accentLight = new THREE.PointLight(ACCENT, 7, 16, 2);
  accentLight.position.set(-2.6, -2.6, 2.4);
  scene.add(accentLight);

  scene.add(new THREE.AmbientLight(0x2a2c3a, 0.9));

  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));

  const bloom = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.62, 0.72, 0.82);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());

  const setSize = (width: number, height: number): void => {
    const safeWidth = Math.max(1, Math.floor(width));
    const safeHeight = Math.max(1, Math.floor(height));
    const aspect = safeWidth / safeHeight;
    camera.aspect = aspect;

    // A portrait or very narrow viewport would crop the island horizontally.
    // The camera director owns `fov` frame by frame, so the correction is
    // published as a boost it adds to its own keyframed values.
    camera.userData.fovBoost = aspect < 1 ? 14 : aspect < 1.4 ? 6 : 0;
    camera.fov = BASE_FOV + camera.userData.fovBoost;
    camera.updateProjectionMatrix();

    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(safeWidth, safeHeight, false);
    composer.setSize(safeWidth, safeHeight);
    bloom.resolution.set(safeWidth, safeHeight);
  };

  const render = (elapsed: number): void => {
    composer.render();
    void elapsed;
  };

  const dispose = (): void => {
    composer.dispose();
    renderer.dispose();
    environment.texture.dispose();
    canvas.remove();
  };

  return {
    renderer,
    scene,
    camera,
    composer,
    bloom,
    container,
    canvas,
    setSize,
    render,
    dispose,
  };
};