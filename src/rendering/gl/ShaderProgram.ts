import {vec3, vec4, mat4} from 'gl-matrix';
import Drawable from './Drawable';
import {gl} from '../../globals';

var activeProgram: WebGLProgram = null;

export class Shader {
  shader: WebGLShader;

  constructor(type: number, source: string) {
    this.shader = gl.createShader(type);
    gl.shaderSource(this.shader, source);
    gl.compileShader(this.shader);

    if (!gl.getShaderParameter(this.shader, gl.COMPILE_STATUS)) {
      throw gl.getShaderInfoLog(this.shader);
    }
  }
};

// Everything the fireball shaders read. The first group is the GUI sliders,
// then the three colour pickers, then the art-directed constants that the
// palette presets set.
export interface FireballParams {
  streamSpeed: number;       // 0 - 20, scaled down before it reaches the shader
  detailOctaves: number;
  surfaceChurn: number;
  wakeReach: number;
  emberColor: number[];      // [r, g, b] in 0 - 255, as dat.GUI stores it
  blazeColor: number[];
  coreColor: number[];
  cellScale: number;
  tongueTaper: number;
  surge: number;
  tiers: number;
  shred: number;
  driftAngle: number;        // degrees; 0 = wake straight up
}

class ShaderProgram {
  prog: WebGLProgram;

  attrPos: number;
  attrNor: number;
  attrCol: number;

  unifModel: WebGLUniformLocation;
  unifModelInvTr: WebGLUniformLocation;
  unifViewProj: WebGLUniformLocation;
  unifColor: WebGLUniformLocation;

  unifTime: WebGLUniformLocation;
  unifShellT: WebGLUniformLocation;
  unifDims: WebGLUniformLocation;
  unifCamPos: WebGLUniformLocation;
  unifWakeAxis: WebGLUniformLocation;
  unifChurn: WebGLUniformLocation;
  unifStreamSpeed: WebGLUniformLocation;
  unifWakeReach: WebGLUniformLocation;
  unifOctaves: WebGLUniformLocation;
  unifCellScale: WebGLUniformLocation;
  unifTongueTaper: WebGLUniformLocation;
  unifSurge: WebGLUniformLocation;
  unifTiers: WebGLUniformLocation;
  unifShred: WebGLUniformLocation;
  unifEmberColor: WebGLUniformLocation;
  unifBlazeColor: WebGLUniformLocation;
  unifCoreColor: WebGLUniformLocation;

  constructor(shaders: Array<Shader>) {
    this.prog = gl.createProgram();

    for (let shader of shaders) {
      gl.attachShader(this.prog, shader.shader);
    }
    gl.linkProgram(this.prog);
    if (!gl.getProgramParameter(this.prog, gl.LINK_STATUS)) {
      throw gl.getProgramInfoLog(this.prog);
    }

    this.attrPos = gl.getAttribLocation(this.prog, "vs_Pos");
    this.attrNor = gl.getAttribLocation(this.prog, "vs_Nor");
    this.attrCol = gl.getAttribLocation(this.prog, "vs_Col");

    this.unifModel        = gl.getUniformLocation(this.prog, "u_Model");
    this.unifModelInvTr   = gl.getUniformLocation(this.prog, "u_ModelInvTr");
    this.unifViewProj     = gl.getUniformLocation(this.prog, "u_ViewProj");
    this.unifColor        = gl.getUniformLocation(this.prog, "u_Color");

    this.unifTime         = gl.getUniformLocation(this.prog, "u_Time");
    this.unifShellT       = gl.getUniformLocation(this.prog, "u_ShellT");
    this.unifDims         = gl.getUniformLocation(this.prog, "u_Dims");
    this.unifCamPos       = gl.getUniformLocation(this.prog, "u_CamPos");
    this.unifWakeAxis     = gl.getUniformLocation(this.prog, "u_WakeAxis");
    this.unifChurn        = gl.getUniformLocation(this.prog, "u_Churn");
    this.unifStreamSpeed  = gl.getUniformLocation(this.prog, "u_StreamSpeed");
    this.unifWakeReach    = gl.getUniformLocation(this.prog, "u_WakeReach");
    this.unifOctaves      = gl.getUniformLocation(this.prog, "u_Octaves");
    this.unifCellScale    = gl.getUniformLocation(this.prog, "u_CellScale");
    this.unifTongueTaper  = gl.getUniformLocation(this.prog, "u_TongueTaper");
    this.unifSurge        = gl.getUniformLocation(this.prog, "u_Surge");
    this.unifTiers        = gl.getUniformLocation(this.prog, "u_Tiers");
    this.unifShred        = gl.getUniformLocation(this.prog, "u_Shred");
    this.unifEmberColor   = gl.getUniformLocation(this.prog, "u_EmberColor");
    this.unifBlazeColor   = gl.getUniformLocation(this.prog, "u_BlazeColor");
    this.unifCoreColor    = gl.getUniformLocation(this.prog, "u_CoreColor");
  }

  use() {
    if (activeProgram !== this.prog) {
      gl.useProgram(this.prog);
      activeProgram = this.prog;
    }
  }

  setModelMatrix(model: mat4) {
    this.use();
    if (this.unifModel !== -1) {
      gl.uniformMatrix4fv(this.unifModel, false, model);
    }

    if (this.unifModelInvTr !== -1) {
      let modelinvtr: mat4 = mat4.create();
      mat4.transpose(modelinvtr, model);
      mat4.invert(modelinvtr, modelinvtr);
      gl.uniformMatrix4fv(this.unifModelInvTr, false, modelinvtr);
    }
  }

  setViewProjMatrix(vp: mat4) {
    this.use();
    if (this.unifViewProj !== -1) {
      gl.uniformMatrix4fv(this.unifViewProj, false, vp);
    }
  }

  setGeometryColor(color: vec4) {
    this.use();
    if (this.unifColor !== -1) {
      gl.uniform4fv(this.unifColor, color);
    }
  }

  setTime(t: number) {
    this.use();
    gl.uniform1f(this.unifTime, t);
  }

  // 0 = innermost (hot core) shell, 1 = outermost (cool wisp) shell
  setShell(v: number) {
    this.use();
    gl.uniform1f(this.unifShellT, v);
  }

  setDimensions(width: number, height: number) {
    this.use();
    gl.uniform2f(this.unifDims, width, height);
  }

  setCamPos(pos: vec3 | Float32Array | number[]) {
    this.use();
    gl.uniform3f(this.unifCamPos, pos[0], pos[1], pos[2]);
  }

  setFireballParams(p: FireballParams) {
    this.use();

    // wake axis lives in the XY plane; 0 deg points straight up
    const a = p.driftAngle * Math.PI / 180.0;
    gl.uniform3f(this.unifWakeAxis, Math.sin(a), Math.cos(a), 0.0);

    gl.uniform1f(this.unifChurn,       p.surfaceChurn);
    gl.uniform1f(this.unifStreamSpeed, p.streamSpeed * 0.1);   // GUI 0-20 -> 0-2
    gl.uniform1f(this.unifWakeReach,   p.wakeReach);
    gl.uniform1i(this.unifOctaves,     Math.round(p.detailOctaves));
    gl.uniform1f(this.unifCellScale,   p.cellScale);
    gl.uniform1f(this.unifTongueTaper, p.tongueTaper);
    gl.uniform1f(this.unifSurge,       p.surge);
    gl.uniform1f(this.unifTiers,       p.tiers);
    gl.uniform1f(this.unifShred,       p.shred);

    gl.uniform3f(this.unifEmberColor, p.emberColor[0] / 255, p.emberColor[1] / 255, p.emberColor[2] / 255);
    gl.uniform3f(this.unifBlazeColor, p.blazeColor[0] / 255, p.blazeColor[1] / 255, p.blazeColor[2] / 255);
    gl.uniform3f(this.unifCoreColor,  p.coreColor[0]  / 255, p.coreColor[1]  / 255, p.coreColor[2]  / 255);
  }

  draw(d: Drawable) {
    this.use();

    if (this.attrPos != -1 && d.bindPos()) {
      gl.enableVertexAttribArray(this.attrPos);
      gl.vertexAttribPointer(this.attrPos, 4, gl.FLOAT, false, 0, 0);
    }

    if (this.attrNor != -1 && d.bindNor()) {
      gl.enableVertexAttribArray(this.attrNor);
      gl.vertexAttribPointer(this.attrNor, 4, gl.FLOAT, false, 0, 0);
    }

    d.bindIdx();
    gl.drawElements(d.drawMode(), d.elemCount(), gl.UNSIGNED_INT, 0);

    if (this.attrPos != -1) gl.disableVertexAttribArray(this.attrPos);
    if (this.attrNor != -1) gl.disableVertexAttribArray(this.attrNor);
  }
};

export default ShaderProgram;
