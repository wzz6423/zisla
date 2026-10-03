/**
 * Camera direction.
 *
 * A keyframe track is interpolated with Catmull-Rom on position and target, so
 * the camera never snaps at a chapter boundary and scrubbing produces exactly
 * the same path as playback.
 */
import * as THREE from 'three';

interface CameraKey {
  /** Timeline position, in seconds. */
  time: number;
  position: THREE.Vector3;
  target: THREE.Vector3;
  fov: number;
  roll: number;
}

const key = (
  time: number,
  position: [number, number, number],
  target: [number, number, number],
  fov = 38,
  roll = 0,
): CameraKey => ({
  time,
  position: new THREE.Vector3(...position),
  target: new THREE.Vector3(...target),
  fov,
  roll,
});

/**
 * Keys sit on chapter starts, with intermediate keys for the moves that need a
 * beat of their own (the push past the focus window, the orbit across the row).
 */
const TRACK: readonly CameraKey[] = [
  key(0, [0, 0.35, 15.5], [0, 0.2, 0], 34),
  key(3.4, [0, 0.5, 12.4], [0, 0.35, 0], 34),
  key(6.6, [0.4, 0.9, 11.2], [0, 0.5, 0], 36),
  key(9.2, [-3.6, 2.4, 12.8], [-0.4, 0.6, 0], 40),
  key(13.4, [3.2, 2.1, 12.2], [0.3, 0.5, 0], 40),
  key(16.6, [0, 1.1, 11.6], [0, 0.2, 0], 38),
  key(20.4, [-2.2, 0.4, 9.4], [0, -0.2, 0], 40),
  key(25.2, [2.6, 1.4, 9.6], [0.2, 0.1, 0], 40, -0.012),
  key(30.4, [-2.8, 0.8, 9.2], [-0.4, -0.1, 0], 42),
  key(34.8, [1.4, 2.6, 10.4], [0, 0.3, 0], 38),
  key(40.2, [-1.8, 1.2, 8.8], [0, 0.2, 0], 38, 0.01),
  key(44.6, [0, 0.9, 11.4], [0, 0.5, 0], 36),
  key(50, [0, 0.55, 12.6], [0, 0.6, 0], 34),
];

export interface CameraDirector {
  apply(camera: THREE.PerspectiveCamera, time: number, idle: number): void;
  /** Jumps the smoothing target, used when the viewer scrubs the timeline. */
  reset(camera: THREE.PerspectiveCamera, time: number): void;
}

const findSpan = (time: number): { from: number; to: number; ratio: number } => {
  const last = TRACK.length - 1;
  if (time <= TRACK[0].time) return { from: 0, to: 0, ratio: 0 };
  if (time >= TRACK[last].time) return { from: last, to: last, ratio: 0 };

  for (let index = 0; index < last; index += 1) {
    if (time >= TRACK[index].time && time <= TRACK[index + 1].time) {
      return { from: index, to: index + 1, ratio: (time - TRACK[index].time) / (TRACK[index + 1].time - TRACK[index].time) };
    }
  }
  return { from: last, to: last, ratio: 0 };
};

const samplePosition = new THREE.Vector3();
const sampleTarget = new THREE.Vector3();
const positionCurve = new THREE.CatmullRomCurve3([], false, 'catmullrom', 0.4);
const targetCurve = new THREE.CatmullRomCurve3([], false, 'catmullrom', 0.4);

/** Feeds the four Catmull-Rom control points around the current span. */
const setCurvePoints = (
  curve: THREE.CatmullRomCurve3,
  from: number,
  to: number,
  pick: (k: CameraKey) => THREE.Vector3,
): void => {
  const last = TRACK.length - 1;
  curve.points = [
    pick(TRACK[Math.max(0, from - 1)]),
    pick(TRACK[from]),
    pick(TRACK[to]),
    pick(TRACK[Math.min(last, to + 1)]),
  ];
  curve.updateArcLengths();
};

export const createCameraDirector = (): CameraDirector => {
  /**
   * The track is sampled with a linear parameter and Catmull-Rom interpolation,
   * which already yields continuous velocity through the keys. Applying an
   * ease-in-out on top would force the camera to a full stop at every keyframe,
   * so the span ratio is used as-is.
   */
  const apply = (camera: THREE.PerspectiveCamera, time: number, idle: number): void => {
    const span = findSpan(time);

    setCurvePoints(positionCurve, span.from, span.to, (k) => k.position);
    setCurvePoints(targetCurve, span.from, span.to, (k) => k.target);
    positionCurve.getPoint(span.ratio, samplePosition);
    targetCurve.getPoint(span.ratio, sampleTarget);

    // Breathing idle offset: enough to keep the frame alive, not enough to read
    // as drift. It is a pure function of `time`, so scrubbing stays exact, and
    // it is disabled for reduced motion, where `idle` is 0.
    const breath = idle * 0.12;
    camera.position.set(
      samplePosition.x + Math.sin(time * 0.21) * breath,
      samplePosition.y + Math.sin(time * 0.17 + 1.2) * breath * 0.6,
      samplePosition.z,
    );
    camera.lookAt(sampleTarget);

    // `fovBoost` is published by the stage: a portrait or narrow viewport needs
    // a wider lens or the island is cropped at the sides.
    const boost = (camera.userData.fovBoost as number | undefined) ?? 0;
    const fov = TRACK[span.from].fov + (TRACK[span.to].fov - TRACK[span.from].fov) * span.ratio + boost;
    if (Math.abs(camera.fov - fov) > 0.01) {
      camera.fov = fov;
      camera.updateProjectionMatrix();
    }
    camera.rotation.z = TRACK[span.from].roll + (TRACK[span.to].roll - TRACK[span.from].roll) * span.ratio;
  };

  return {
    apply,
    reset: (camera, time) => {
      // With the frame-rate-dependent smoothing gone, a scrub already lands on
      // the exact sampled pose. This keeps the interface meaningful for callers
      // that want to force a re-aim without advancing the clock.
      const span = findSpan(time);
      setCurvePoints(targetCurve, span.from, span.to, (k) => k.target);
      targetCurve.getPoint(span.ratio, sampleTarget);
      camera.lookAt(sampleTarget);
    },
  };
};