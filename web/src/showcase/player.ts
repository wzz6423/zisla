/**
 * The showcase player.
 *
 * Owns the render loop, keeps a scene group per chapter in the timeline, and
 * routes transport state to the overlay UI. Chapters are all mounted up front
 * and posed every frame from the timeline position, which keeps scrubbing and
 * playback visually identical.
 */
import * as THREE from 'three';
import { chapters, sampleChapters, totalDuration, CHAPTER_OVERLAP } from './chapters';
import { createCameraDirector } from './director';
import { createStage } from './stage';
import type { Transport } from './transport';
import { createOpeningScene } from './scenes/opening';
import { createContextScene } from './scenes/context';
import { createFeaturesScene, type FeaturesScene } from './scenes/features';
import { createHighlightsScene } from './scenes/highlights';
import { createOutroScene } from './scenes/outro';
import type { ShowcaseCopy } from './script';

export interface Player {
  transport: Transport;
  play(): void;
  pause(): void;
  /** Drops camera smoothing so a scrub lands on the exact requested frame. */
  resetCamera(): void;
  /**
   * Read-only snapshot of the live scene, used by the verification script to
   * assert what is actually on screen rather than inferring it from pixels.
   */
  debugState(): DebugState;
  destroy(): void;
}

export interface DebugSceneEntry {
  name: string;
  visible: boolean;
  /** Objects inside the group whose material opacity is above the threshold. */
  opaqueObjects: number;
  totalObjects: number;
}

export interface DebugState {
  time: number;
  playing: boolean;
  activeChapter: string;
  cameraPosition: [number, number, number];
  cameraFov: number;
  fogDensity: number;
  scenes: DebugSceneEntry[];
}

export interface PlayerCallbacks {
  /** Fired every time the active chapter changes. */
  onChapterChange(id: string, index: number): void;
  /** Fired on any transport state change, for UI refresh. */
  onTransportChange(): void;
}

const prefersReducedMotion = (): boolean =>
  typeof window.matchMedia === 'function' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export const createPlayer = (
  container: HTMLElement,
  copy: ShowcaseCopy,
  transport: Transport,
  callbacks: PlayerCallbacks,
): Player => {
  const stage = createStage(container);
  const reducedMotion = prefersReducedMotion();

  const scenes = [
    createOpeningScene(),
    createContextScene(copy.contextSources),
    createFeaturesScene(copy.featureChips),
    createHighlightsScene(copy.highlightRows),
    createOutroScene(copy.endCard),
  ];

  const featuresScene = scenes[2] as FeaturesScene;
  const sceneGroups = new Map<string, THREE.Group>();
  scenes.forEach((scene, index) => {
    scene.group.visible = false;
    stage.scene.add(scene.group);
    sceneGroups.set(chapters[index].id, scene.group);
  });

  const director = createCameraDirector();

transport.onChange(() => callbacks.onTransportChange());

  let activeChapterId = '';
  let frame = 0;
  let lastTimestamp = 0;
  let running = true;

  const resize = (): void => {
    const rect = container.getBoundingClientRect();
    stage.setSize(rect.width, rect.height);
    // Scenes that reflow their content need the width, not just the camera.
    featuresScene.setLayout(rect.width);
  };

  const observer = new ResizeObserver(resize);
  observer.observe(container);
  resize();

  /** One authoritative pose of the whole timeline. */
  const pose = (time: number): void => {
    const states = sampleChapters(time);

    states.forEach((state, index) => {
      const group = sceneGroups.get(state.chapter.id);
      if (!group) return;
      // A chapter stays mounted through its crossfade, then unmounts so it
      // costs nothing for the rest of the film.
      group.visible = state.weight > 0.002;
      if (group.visible) scenes[index].update(state.local, state.weight);
    });

    // `idle` is the breathing-camera amplitude: 0 when reduced motion is on.
    director.apply(stage.camera, time, reducedMotion ? 0 : 1);

    // The problem chapter sits a touch deeper in fog; `scene.fog` is typed as
    // the `Fog | FogExp2` union, so narrow it before touching `density`.
    const fog = stage.scene.fog;
    if (fog instanceof THREE.FogExp2) {
      fog.density = 0.055 + (states[1]?.weight ?? 0) * 0.018;
    }

    // During a crossfade both chapters are equally weighted; prefer the later one
    // so the titles switch as the incoming chapter takes over.
    const active = states.reduce(
      (best, state) => (state.weight >= best.weight ? state : best),
      states[0],
    );
    if (active && active.chapter.id !== activeChapterId) {
      activeChapterId = active.chapter.id;
      callbacks.onChapterChange(activeChapterId, active.index);
    }
  };

  const tick = (timestamp: number): void => {
    if (!running) return;
    frame = requestAnimationFrame(tick);

    const delta = lastTimestamp === 0 ? 0 : (timestamp - lastTimestamp) / 1000;
    lastTimestamp = timestamp;

    transport.advance(delta);
    pose(transport.time);
    stage.render(timestamp / 1000);
  };

  // Prime the first frame before the loop so the poster image is correct even
  // if the viewer never presses play.
  pose(0);
  stage.render(0);
  frame = requestAnimationFrame(tick);

  const onVisibility = (): void => {
    // Returning to a hidden tab must not fast-forward the film.
    if (!document.hidden) lastTimestamp = 0;
  };
  document.addEventListener('visibilitychange', onVisibility);

  const debugState = (): DebugState => {
    const fog = stage.scene.fog;
    return {
      time: transport.time,
      playing: transport.playing,
      activeChapter: activeChapterId,
      cameraPosition: [
        Number(stage.camera.position.x.toFixed(3)),
        Number(stage.camera.position.y.toFixed(3)),
        Number(stage.camera.position.z.toFixed(3)),
      ],
      cameraFov: Number(stage.camera.fov.toFixed(2)),
      fogDensity: fog instanceof THREE.FogExp2 ? Number(fog.density.toFixed(4)) : -1,
      scenes: chapters.map((chapter) => {
        const group = sceneGroups.get(chapter.id);
        let opaqueObjects = 0;
        let totalObjects = 0;
        group?.traverse((child) => {
          if (!(child instanceof THREE.Mesh)) return;
          totalObjects += 1;
          const material = child.material as THREE.Material & { opacity?: number };
          const opacity = Array.isArray(child.material) ? 1 : (material.opacity ?? 1);
          if (opacity > 0.02) opaqueObjects += 1;
        });
        return { name: chapter.id, visible: group?.visible ?? false, opaqueObjects, totalObjects };
      }),
    };
  };

  return {
    transport,
    play: () => transport.play(),
    pause: () => transport.pause(),
    resetCamera: () => director.reset(stage.camera, transport.time),
    debugState,
    destroy: () => {
      running = false;
      cancelAnimationFrame(frame);
      observer.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
      scenes.forEach((scene) => scene.dispose());
      transport.dispose();
      stage.dispose();
    },
  };
};

export { totalDuration, chapters, CHAPTER_OVERLAP };