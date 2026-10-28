import './styles.css';
import * as THREE from 'three';
import type { ChapterId } from './copy/copy';
import { en } from './copy/en';

// Types
type Phase = 'intro' | ChapterId | 'outro';

interface AnimationState {
  phase: Phase;
  progress: number;
  isPlaying: boolean;
}

// Constants
const ISLAND_WIDTH = 776;
const ISLAND_HEIGHT_COLLAPSED = 34;
const ISLAND_HEIGHT_EXPANDED = 340;
const ISLAND_RADIUS_BOTTOM = 34;
const MODULE_INSET = 12;
const MODULE_RADIUS = 8;

const PHASE_DURATION = 3000; // ms per phase

const MODULE_COLORS: Record<ChapterId, string> = {
  1: '#c8cf3a', // Home (accent)
  2: '#60a5fa', // AI Monitor (blue)
  3: '#f472b6', // File Shelf (pink)
  4: '#a78bfa', // System (purple)
};

// Scene setup
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x09090b);

const camera = new THREE.PerspectiveCamera(
  45,
  window.innerWidth / window.innerHeight,
  0.1,
  1000
);
camera.position.z = 1200;

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
document.getElementById('app')!.appendChild(renderer.domElement);

// Lights
const ambientLight = new THREE.AmbientLight(0xffffff, 0.4);
scene.add(ambientLight);

const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
directionalLight.position.set(5, 5, 5);
scene.add(directionalLight);

// Island mesh
function createIslandMesh(width: number, height: number): THREE.Mesh {
  const shape = new THREE.Shape();
  const w = width / 2;
  const h = height / 2;
  const r = Math.min(ISLAND_RADIUS_BOTTOM, height / 2);

  shape.moveTo(-w + r, -h);
  shape.lineTo(w - r, -h);
  shape.quadraticCurveTo(w, -h, w, -h + r);
  shape.lineTo(w, h - r);
  shape.quadraticCurveTo(w, h, w - r, h);
  shape.lineTo(-w + r, h);
  shape.quadraticCurveTo(-w, h, -w, h - r);
  shape.lineTo(-w, -h + r);
  shape.quadraticCurveTo(-w, -h, -w + r, -h);

  const geometry = new THREE.ExtrudeGeometry(shape, {
    depth: 10,
    bevelEnabled: true,
    bevelThickness: 2,
    bevelSize: 2,
    bevelSegments: 3,
  });

  const material = new THREE.MeshStandardMaterial({
    color: 0x18181b,
    metalness: 0.3,
    roughness: 0.7,
  });

  return new THREE.Mesh(geometry, material);
}

const island = createIslandMesh(ISLAND_WIDTH, ISLAND_HEIGHT_COLLAPSED);
scene.add(island);

// Module cards (4 quadrants when expanded)
const modules: THREE.Mesh[] = [];
const moduleWidth = (ISLAND_WIDTH - MODULE_INSET * 3) / 2;
const moduleHeight = (ISLAND_HEIGHT_EXPANDED - MODULE_INSET * 3) / 2;

for (let i = 0; i < 4; i++) {
  const shape = new THREE.Shape();
  const w = moduleWidth / 2;
  const h = moduleHeight / 2;
  const r = MODULE_RADIUS;

  shape.moveTo(-w + r, -h);
  shape.lineTo(w - r, -h);
  shape.quadraticCurveTo(w, -h, w, -h + r);
  shape.lineTo(w, h - r);
  shape.quadraticCurveTo(w, h, w - r, h);
  shape.lineTo(-w + r, h);
  shape.quadraticCurveTo(-w, h, -w, h - r);
  shape.lineTo(-w, -h + r);
  shape.quadraticCurveTo(-w, -h, -w + r, -h);

  const geometry = new THREE.ExtrudeGeometry(shape, {
    depth: 5,
    bevelEnabled: false,
  });

  const material = new THREE.MeshStandardMaterial({
    color: 0x27272a,
    metalness: 0.2,
    roughness: 0.8,
    emissive: 0x000000,
    emissiveIntensity: 0,
  });

  const module = new THREE.Mesh(geometry, material);
  module.visible = false;

  const col = i % 2;
  const row = Math.floor(i / 2);
  const offsetX = (col - 0.5) * (moduleWidth + MODULE_INSET);
  const offsetY = (0.5 - row) * (moduleHeight + MODULE_INSET);
  module.position.set(offsetX, offsetY, 10);

  scene.add(module);
  modules.push(module);
}

// Animation state
const state: AnimationState = {
  phase: 'intro',
  progress: 0,
  isPlaying: true,
};

let lastTime = performance.now();
const phaseTimings: Record<Phase, number> = {
  intro: PHASE_DURATION,
  1: PHASE_DURATION,
  2: PHASE_DURATION,
  3: PHASE_DURATION,
  4: PHASE_DURATION,
  outro: PHASE_DURATION,
};

// UI elements
const overlay = document.createElement('div');
overlay.className = 'overlay';
document.getElementById('app')!.appendChild(overlay);

const chapterText = document.createElement('div');
chapterText.className = 'chapter-text';
overlay.appendChild(chapterText);

const controls = document.createElement('div');
controls.className = 'controls';
overlay.appendChild(controls);

const playPauseBtn = document.createElement('button');
playPauseBtn.className = 'btn';
playPauseBtn.innerHTML = `<span class="sr-only">Pause</span>⏸`;
playPauseBtn.addEventListener('click', () => {
  state.isPlaying = !state.isPlaying;
  playPauseBtn.innerHTML = state.isPlaying
    ? `<span class="sr-only">Pause</span>⏸`
    : `<span class="sr-only">Play</span>▶`;
});
controls.appendChild(playPauseBtn);

const chapterDots = document.createElement('div');
chapterDots.className = 'chapter-dots';
for (let i = 1; i <= 4; i++) {
  const dot = document.createElement('div');
  dot.className = 'dot';
  dot.dataset.chapter = String(i);
  chapterDots.appendChild(dot);
}
controls.appendChild(chapterDots);

// Update chapter text
function updateChapterText(phase: Phase) {
  const kicker = chapterText.querySelector('.kicker') || document.createElement('div');
  const title = chapterText.querySelector('.title') || document.createElement('div');
  const body = chapterText.querySelector('.body') || document.createElement('div');

  kicker.className = 'kicker';
  title.className = 'title';
  body.className = 'body';

  if (phase === 'intro') {
    kicker.textContent = en.kicker;
    title.innerHTML = en.headline;
    body.textContent = en.lede;
  } else if (phase === 'outro') {
    kicker.textContent = en.outro.kicker;
    title.innerHTML = en.outro.title;
    body.textContent = en.outro.body;
  } else {
    const chapter = en.chapters[phase as ChapterId];
    kicker.textContent = chapter.kicker;
    title.textContent = chapter.title;
    body.textContent = chapter.body;
  }

  chapterText.innerHTML = '';
  chapterText.appendChild(kicker);
  chapterText.appendChild(title);
  chapterText.appendChild(body);

  // Fade in
  chapterText.classList.remove('visible');
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      chapterText.classList.add('visible');
    });
  });

  // Update dots
  chapterDots.querySelectorAll('.dot').forEach((dot) => {
    const dotChapter = Number(dot.getAttribute('data-chapter'));
    dot.classList.toggle('active', typeof phase === 'number' && dotChapter === phase);
  });
}

// Animate island morph
function updateIslandMorph(progress: number) {
  const targetHeight =
    state.phase === 'intro' || state.phase === 'outro'
      ? ISLAND_HEIGHT_COLLAPSED
      : ISLAND_HEIGHT_EXPANDED;

  const currentHeight = THREE.MathUtils.lerp(
    ISLAND_HEIGHT_COLLAPSED,
    targetHeight,
    Math.min(progress * 2, 1)
  );

  scene.remove(island);
  const newIsland = createIslandMesh(ISLAND_WIDTH, currentHeight);
  newIsland.position.copy(island.position);
  newIsland.rotation.copy(island.rotation);
  scene.add(newIsland);
  island.geometry.dispose();
  Object.assign(island, newIsland);

  const isExpanded = currentHeight > ISLAND_HEIGHT_COLLAPSED + 50;
  modules.forEach((mod) => {
    mod.visible = isExpanded;
  });
}

// Highlight module
function highlightModule(chapterId: ChapterId | null) {
  modules.forEach((mod, i) => {
    const mat = mod.material as THREE.MeshStandardMaterial;
    if (chapterId !== null && i === chapterId - 1) {
      mat.emissive.set(MODULE_COLORS[chapterId]);
      mat.emissiveIntensity = 0.6;
    } else {
      mat.emissive.set(0x000000);
      mat.emissiveIntensity = 0;
    }
  });
}

// Advance phase
function advancePhase() {
  const sequence: Phase[] = ['intro', 1, 2, 3, 4, 'outro'];
  const currentIndex = sequence.indexOf(state.phase);
  const nextIndex = (currentIndex + 1) % sequence.length;
  state.phase = sequence[nextIndex];
  state.progress = 0;
  updateChapterText(state.phase);
}

// Animation loop
function animate(time: number) {
  requestAnimationFrame(animate);

  if (state.isPlaying) {
    const delta = time - lastTime;
    state.progress += delta / phaseTimings[state.phase];

    if (state.progress >= 1) {
      advancePhase();
    }

    updateIslandMorph(state.progress);

    if (typeof state.phase === 'number') {
      highlightModule(state.phase);
    } else {
      highlightModule(null);
    }
  }

  lastTime = time;

  // Gentle rotation
  island.rotation.x = Math.sin(time * 0.0003) * 0.05;
  island.rotation.y = Math.cos(time * 0.0002) * 0.1;

  renderer.render(scene, camera);
}

// Handle resize
window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// Start
updateChapterText('intro');
animate(performance.now());
