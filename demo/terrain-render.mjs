import { meshNormals, eyeDistance } from "./terrain-scene.mjs";
// WebGL resources shared by ground and optional scenery. Heights are in yards.
export const vertexSource = `#version 300 es
precision highp float;
layout(location=0) in vec3 position;
layout(location=1) in vec3 normal;
layout(location=2) in vec3 placement;
layout(location=3) in vec3 rotationScale;
uniform vec2 center;
uniform vec2 viewport;
uniform float zoom;
uniform float yaw;
uniform float tilt;
uniform float focus;
uniform float eye;
uniform bool instanced;
uniform vec2 tileOrigin;
uniform vec2 textureScale;
out vec2 uv;
out vec2 worldTile;
out float altitude;
out float slope;
out float light;
out float haze;
void main() {
 vec3 p=position, n=normal;
 if(instanced) {
  float co=cos(rotationScale.x), si=sin(rotationScale.x), s=rotationScale.y;
  p=vec3((p.x*co-p.y*si)*s/533.333333,(p.x*si+p.y*co)*s/533.333333,p.z*s)+placement;
  n=vec3(n.x*co-n.y*si,n.x*si+n.y*co,n.z);
 }
 vec2 d=p.xy-center;
 float a=cos(yaw)*d.x-sin(yaw)*d.y;
 float b=sin(yaw)*d.x+cos(yaw)*d.y;
 float z=(p.z-focus)/533.333333;
 // Perspective (terrain-scene.mjs project): w, 1 at the focus, divides; depth is 1 - 2 NEAR / w.
 float depth=b*sin(tilt)+z*cos(tilt), w=1.0-depth/eye;
 vec2 screen=vec2(a,b*cos(tilt)-z*sin(tilt))*zoom;
 gl_Position=vec4(screen.x*2.0/viewport.x,-screen.y*2.0/viewport.y,w-0.04,w);
 haze=smoothstep(1.25,2.6,w);
 uv=(position.xy-tileOrigin)*textureScale; worldTile=position.xy; altitude=p.z;
 slope=degrees(acos(clamp(abs(n.z),0.0,1.0)));
 light=0.68+0.32*max(0.0,dot(normalize(n),normalize(vec3(-0.4,-0.6,1.0))));
}`;
export const fragmentSource = `#version 300 es
precision highp float;
in vec2 uv;
in vec2 worldTile;
in float altitude;
in float slope;
in float light;
in float haze;
uniform sampler2D image;
uniform bool textured;
uniform sampler2D previousImage;
uniform bool previousTextured;
uniform vec2 previousOrigin;
uniform vec2 previousScale;
uniform float textureBlend;
uniform int analysis;
uniform bool contours;
uniform vec3 tint;
uniform vec2 tileOrigin;

out vec4 color;
void main() {
 vec3 base=textured?texture(image,uv).rgb:tint;
 if(textureBlend<1.0) {
  vec3 before=previousTextured?texture(previousImage,(worldTile-previousOrigin)*previousScale).rgb:tint;
  base=mix(before,base,smoothstep(0.0,1.0,textureBlend));
 }
 if(analysis==1) base=mix(vec3(0.05,0.3,0.44),vec3(0.96,0.79,0.37),clamp((altitude+100.0)/1800.0,0.0,1.0));
 if(analysis==2) base=mix(vec3(0.2,0.65,0.42),vec3(0.95,0.18,0.1),clamp(slope/60.0,0.0,1.0));
 float line=abs(fract(altitude/25.0-0.5)-0.5)/max(fwidth(altitude/25.0),0.0001);
 if(contours) base=mix(base,vec3(0.08,0.05,0.02),1.0-smoothstep(0.0,1.2,line));
 // Far ground goes a little hazy, as air does: depth you can read at a glance.
 color=vec4(mix(base*light,vec3(0.11,0.15,0.19),haze*0.45),1.0);
}`;
export function program(gl) {
  const compile = (type, source) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const message = gl.getShaderInfoLog(shader);
      gl.deleteShader(shader);
      throw Error(message);
    }
    return shader;
  };
  const vs = compile(gl.VERTEX_SHADER, vertexSource),
    fs = compile(gl.FRAGMENT_SHADER, fragmentSource),
    p = gl.createProgram();
  gl.attachShader(p, vs);
  gl.attachShader(p, fs);
  gl.linkProgram(p);
  gl.deleteShader(vs);
  gl.deleteShader(fs);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
    const message = gl.getProgramInfoLog(p);
    gl.deleteProgram(p);
    throw Error(message);
  }
  return p;
}
export function upload(gl, mesh, local = false) {
  const p = mesh.positions,
    indices = mesh.indices,
    normals = mesh.normals || meshNormals(mesh, local);
  const vao = gl.createVertexArray(),
    buffers = [];
  gl.bindVertexArray(vao);
  for (const [loc, data] of [
    [0, p],
    [1, normals],
  ]) {
    const b = gl.createBuffer();
    buffers.push(b);
    gl.bindBuffer(gl.ARRAY_BUFFER, b);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 3, gl.FLOAT, false, 0, 0);
  }
  const b = gl.createBuffer();
  buffers.push(b);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, b);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  gl.bindVertexArray(null);
  return {
    vao,
    buffers,
    count: indices.length,
    bytes: p.byteLength + normals.byteLength + indices.byteLength,
  };
}
export function dispose(gl, gpu) {
  if (!gpu) return;
  gl.deleteVertexArray(gpu.vao);
  gpu.buffers.forEach((b) => gl.deleteBuffer(b));
  if (gpu.texture) gl.deleteTexture(gpu.texture);
}
const uniformLocations = new WeakMap();
export function uniforms(gl, p, camera, w, h, yaw, tilt, focus) {
  gl.useProgram(p);
  if (!uniformLocations.has(p)) uniformLocations.set(p, new Map());
  const locations = uniformLocations.get(p);
  const at = (n) => {
    if (!locations.has(n)) locations.set(n, gl.getUniformLocation(p, n));
    return locations.get(n);
  };
  gl.uniform2f(at("center"), camera.cx, camera.cy);
  gl.uniform2f(at("viewport"), w, h);
  gl.uniform1f(at("zoom"), camera.zoom);
  gl.uniform1f(at("yaw"), yaw);
  gl.uniform1f(at("tilt"), (tilt * Math.PI) / 180);
  gl.uniform1f(at("focus"), focus);
  gl.uniform1f(at("eye"), eyeDistance(camera, h));
  gl.uniform2f(at("textureScale"), 1, 1);
  gl.uniform1f(at("textureBlend"), 1);
  gl.uniform1i(at("previousImage"), 1);
  return at;
}
