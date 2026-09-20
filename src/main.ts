import {vec3} from 'gl-matrix';
import Stats from 'stats-js';
import * as DAT from 'dat.gui';
import Icosphere from './geometry/Icosphere';
import Square from './geometry/Square';
import OpenGLRenderer from './rendering/gl/OpenGLRenderer';
import Camera from './Camera';
import {setGL} from './globals';
import ShaderProgram, {Shader} from './rendering/gl/ShaderProgram';

import fireballVertSource from './shaders/fireball-vert.glsl?raw';
import fireballFragSource from './shaders/fireball-frag.glsl?raw';
import backgroundVertSource from './shaders/background-vert.glsl?raw';
import backgroundFragSource from './shaders/background-frag.glsl?raw';

// ---------------------------------------------------------------- presets ---
// Each palette is three colours plus the shape constants that give that look
// its own character, so switching preset changes more than the hue.
const PALETTES: {[name: string]: any} = {
  'Classic Fire': {
    emberColor: [200, 46, 36],
    blazeColor: [255, 77, 0],
    coreColor: [255, 247, 31],
    cellScale: 2.6, tongueTaper: 0.45, surge: 0.25, tiers: 5, shred: 0.85,
  },
  'Blue Plasma': {
    emberColor: [12, 44, 180],
    blazeColor: [0, 150, 255],
    coreColor: [170, 245, 255],
    cellScale: 3.4, tongueTaper: 0.38, surge: 0.35, tiers: 8, shred: 0.90,
  },
  'Violet Rift': {
    emberColor: [70, 10, 130],
    blazeColor: [180, 40, 220],
    coreColor: [255, 190, 255],
    cellScale: 2.2, tongueTaper: 0.50, surge: 0.20, tiers: 5, shred: 0.80,
  },
  'Emerald Wisp': {
    emberColor: [6, 90, 40],
    blazeColor: [40, 210, 110],
    coreColor: [225, 255, 190],
    cellScale: 3.0, tongueTaper: 0.42, surge: 0.30, tiers: 7, shred: 0.95,
  },
};

const DEFAULTS = {
  tesselations: 6,
  streamSpeed: 120.0,
  detailOctaves: 5,
  surfaceChurn: 1,
  wakeReach: 0.75,
  shellCount: 4,
  palette: 'Blue Plasma',
  driftAngle: 28,          // wake direction, not exposed in the GUI
  ...PALETTES['Blue Plasma'],
};

const controls = {
  tesselations: DEFAULTS.tesselations,
  streamSpeed: DEFAULTS.streamSpeed,
  detailOctaves: DEFAULTS.detailOctaves,
  surfaceChurn: DEFAULTS.surfaceChurn,
  wakeReach: DEFAULTS.wakeReach,
  shellCount: DEFAULTS.shellCount,
  emberColor: DEFAULTS.emberColor.slice(),
  blazeColor: DEFAULTS.blazeColor.slice(),
  coreColor: DEFAULTS.coreColor.slice(),
  palette: DEFAULTS.palette,
  driftAngle: DEFAULTS.driftAngle,
  cellScale: DEFAULTS.cellScale,
  tongueTaper: DEFAULTS.tongueTaper,
  surge: DEFAULTS.surge,
  tiers: DEFAULTS.tiers,
  shred: DEFAULTS.shred,
  'Reset Defaults': resetDefaults,
  'Load Scene': loadScene,
};

let icosphere: Icosphere;
let square: Square;
let prevTesselations: number = DEFAULTS.tesselations;
let gui: DAT.GUI;

function refreshGUI() {
  if (!gui) return;
  for (const c of (gui as any).__controllers) {
    c.updateDisplay();
  }
}

function loadScene() {
  icosphere = new Icosphere(vec3.fromValues(0, 0, 0), 1, controls.tesselations);
  icosphere.create();
  square = new Square(vec3.fromValues(0, 0, 0));
  square.create();
}

// Apply a palette preset: the three colours plus the shape constants that
// give each preset its own personality.
function applyPalette(name: string) {
  const s = PALETTES[name];
  if (!s) return;
  controls.emberColor = s.emberColor.slice();
  controls.blazeColor = s.blazeColor.slice();
  controls.coreColor = s.coreColor.slice();
  controls.cellScale = s.cellScale;
  controls.tongueTaper = s.tongueTaper;
  controls.surge = s.surge;
  controls.tiers = s.tiers;
  controls.shred = s.shred;
  controls.palette = name;
  refreshGUI();
}

function resetDefaults() {
  controls.tesselations = DEFAULTS.tesselations;
  controls.streamSpeed = DEFAULTS.streamSpeed;
  controls.detailOctaves = DEFAULTS.detailOctaves;
  controls.surfaceChurn = DEFAULTS.surfaceChurn;
  controls.wakeReach = DEFAULTS.wakeReach;
  controls.shellCount = DEFAULTS.shellCount;
  controls.driftAngle = DEFAULTS.driftAngle;
  applyPalette(DEFAULTS.palette);
}

function main() {
  const stats = Stats();
  stats.setMode(0);
  stats.domElement.style.position = 'absolute';
  stats.domElement.style.left = '0px';
  stats.domElement.style.top = '0px';
  document.body.appendChild(stats.domElement);

  gui = new DAT.GUI();
  gui.add(controls, 'tesselations', 0, 7).step(1);
  gui.add(controls, 'streamSpeed', 0, 200).step(0.5);
  gui.add(controls, 'detailOctaves', 1, 8).step(1);
  gui.add(controls, 'surfaceChurn', 0, 5).step(0.1);
  gui.add(controls, 'wakeReach', 0, 3).step(0.05);
  gui.add(controls, 'shellCount', 1, 6).step(1);
  gui.addColor(controls, 'emberColor');
  gui.addColor(controls, 'blazeColor');
  gui.addColor(controls, 'coreColor');
  gui.add(controls, 'palette', Object.keys(PALETTES)).onChange(applyPalette);
  gui.add(controls, 'Reset Defaults');
  gui.add(controls, 'Load Scene');

  const canvas = <HTMLCanvasElement> document.getElementById('canvas');
  const gl = <WebGL2RenderingContext> canvas.getContext('webgl2');
  if (!gl) {
    alert('WebGL 2 not supported!');
  }
  setGL(gl);

  loadScene();

  const camera = new Camera(vec3.fromValues(0, 0, 6.5), vec3.fromValues(0, 0, 0));

  const renderer = new OpenGLRenderer(canvas);
  renderer.setClearColor(0.02, 0.025, 0.045, 1);
  gl.enable(gl.DEPTH_TEST);

  const fireball = new ShaderProgram([
    new Shader(gl.VERTEX_SHADER, fireballVertSource),
    new Shader(gl.FRAGMENT_SHADER, fireballFragSource),
  ]);

  const background = new ShaderProgram([
    new Shader(gl.VERTEX_SHADER, backgroundVertSource),
    new Shader(gl.FRAGMENT_SHADER, backgroundFragSource),
  ]);

  const startTime = Date.now();

  function tick() {
    const time = (Date.now() - startTime) / 1000.0;

    camera.update();
    stats.begin();
    gl.viewport(0, 0, window.innerWidth, window.innerHeight);
    renderer.clear();

    if (controls.tesselations != prevTesselations) {
      prevTesselations = controls.tesselations;
      icosphere = new Icosphere(vec3.fromValues(0, 0, 0), 1, prevTesselations);
      icosphere.create();
    }

    // starfield first, with depth writes off so it never occludes the fireball.
    // It also needs the palette, since the heat glow is tinted by emberColor.
    background.setTime(time);
    background.setDimensions(window.innerWidth, window.innerHeight);
    background.setFireballParams(controls);
    gl.depthMask(false);
    renderer.render(camera, background, [square]);
    gl.depthMask(true);

    fireball.setTime(time);
    fireball.setCamPos(camera.controls.eye);
    fireball.setFireballParams(controls);

    // One pass per shell. Depth testing sorts them for free: each shell is
    // opaque where it survives its own discard test, so the hot core simply
    // shows through the holes in the cooler shells outside it.
    // Guarded: Math.max(1, NaN) is NaN, not 1, so a bad control value would
    // silently skip the loop and draw nothing at all.
    let shells = Math.round(Number(controls.shellCount));
    if (!isFinite(shells) || shells < 1) shells = 4;
    shells = Math.min(shells, 6);

    for (let i = 0; i < shells; ++i) {
      fireball.setShell(shells === 1 ? 0 : i / (shells - 1));
      renderer.render(camera, fireball, [icosphere]);
    }

    stats.end();
    requestAnimationFrame(tick);
  }

  window.addEventListener('resize', function() {
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.setAspectRatio(window.innerWidth / window.innerHeight);
    camera.updateProjectionMatrix();
  }, false);

  renderer.setSize(window.innerWidth, window.innerHeight);
  camera.setAspectRatio(window.innerWidth / window.innerHeight);
  camera.updateProjectionMatrix();

  tick();
}

main();
