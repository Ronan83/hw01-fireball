#version 300 es

//  src/shaders/fireball-vert.glsl
//
//  A falling fireball drawn as a set of nested shells. The same sphere is
//  submitted once per shell; u_ShellT (0 = hot core, 1 = outermost wisp) is
//  the only thing that changes between passes, and every per-shell property
//  is derived from it here rather than being passed in separately.
//
//  Within a shell:
//    - the sphere STAYS a sphere; only ridged-fBm crests shoot backward
//      along the wake axis W, so tongues separate instead of forming a cone
//    - Layer 1 = low-frequency / high-amplitude sinusoids
//    - Layer 2 = high-frequency / low-amplitude fBm

precision highp float;

uniform mat4  u_Model;
uniform mat4  u_ModelInvTr;
uniform mat4  u_ViewProj;

uniform float u_Time;
uniform float u_ShellT;        // 0 = innermost core ... 1 = outermost shell
uniform vec3  u_WakeAxis;      // unit axis the flame streams toward
uniform float u_Churn;         // amplitude of both noise layers   [GUI]
uniform float u_StreamSpeed;   // how fast the flame streams back  [GUI]
uniform float u_WakeReach;     // how far the tongues reach        [GUI]
uniform int   u_Octaves;       // fBm octaves                      [GUI]
uniform float u_CellScale;
uniform float u_TongueTaper;
uniform float u_Surge;

in vec4 vs_Pos;
in vec4 vs_Nor;
in vec4 vs_Col;

out vec3  fs_Pos;
out vec3  fs_Nor;
out float fs_Wake;     // 0 on the head, 1 at the far end of the tongues
out float fs_Crest;    // tongue crest intensity
out float fs_Axial;    // dot(dir, W): -1 leading tip, +1 trailing tip

// ---------------------------------------------------------------- toolbox ---
// Toolbox #1: Bias — sharpens the ridged noise into distinct tongues
float bias(float b, float t) {
    return pow(t, log(b) / log(0.5));
}

// Toolbox #2: Gain — contrast on the head/wake blend
float gain(float g, float t) {
    if (t < 0.5) return bias(1.0 - g, 2.0 * t) * 0.5;
    return 1.0 - bias(1.0 - g, 2.0 - 2.0 * t) * 0.5;
}

// Toolbox #3: Sawtooth wave — drives the repeating surge cycle
float sawtooth(float x, float freq, float amp) {
    return fract(x * freq) * amp;
}

// Toolbox #4: Impulse — fast rise, slow decay, the surge itself
float impulse(float k, float x) {
    float h = k * x;
    return h * exp(1.0 - h);
}

// Toolbox #5: Ease in/out quadratic — softens the leading-face compression
float easeInOutQuad(float t) {
    if (t < 0.5) return 2.0 * t * t;
    return -1.0 + (4.0 - 2.0 * t) * t;
}

// ------------------------------------------------------------------ noise ---
float hash31(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    return mix(mix(mix(hash31(i + vec3(0, 0, 0)), hash31(i + vec3(1, 0, 0)), f.x),
                   mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
                   mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p, int octaves) {
    float sum = 0.0, amp = 0.5, freq = 1.0, norm = 0.0;
    for (int i = 0; i < 8; ++i) {
        if (i >= octaves) break;
        sum  += amp * noise3(p * freq);
        norm += amp;
        freq *= 2.02;
        amp  *= 0.5;
    }
    return sum / max(norm, 0.0001);
}

// ------------------------------------------------------------------ shape ---
vec3 shapePoint(vec3 dir, float t, out float wakeOut, out float crestOut, out float axialOut) {
    vec3 W = normalize(u_WakeAxis);

    vec3 ref = abs(W.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 A = normalize(cross(ref, W));
    vec3 B = cross(W, A);

    float s = dot(dir, W);
    float u = dot(dir, A);
    float v = dot(dir, B);

    // Each shell samples the noise at its own offset, so the shells are not
    // scaled copies of one another -- their tongues cross and interleave.
    float seed = u_ShellT * 17.31;

    vec3 q = vec3(u * u_CellScale, v * u_CellScale,
                  s * 1.1 - t * u_StreamSpeed * 1.6) + seed;
    float n = fbm(q, u_Octaves);
    float ridge = 1.0 - abs(2.0 * n - 1.0);
    ridge = bias(0.35, clamp(ridge, 0.0, 1.0));

    float crest = pow(ridge, 1.6);
    float lick  = pow(smoothstep(-0.05, 1.0, s), 1.2);
    float head  = smoothstep(0.2, -1.0, s);

    // Layer 1: low-frequency, high-amplitude sinusoids, f(x,y,z) = h
    float low = 0.10 * sin(2.6 * dir.x + 1.20 * t + seed)
              + 0.08 * sin(2.1 * dir.y - 0.90 * t + seed)
              + 0.07 * sin(2.9 * dir.z + 1.50 * t + seed);
    low *= u_Churn;

    // Layer 2: high-frequency, low-amplitude fBm detail
    float bump = fbm(dir * (u_CellScale * 1.7) + vec3(0.0, 0.0, -t * u_StreamSpeed) + seed,
                     u_Octaves) * 2.0 - 1.0;
    float detail = bump * 0.07 * u_Churn;

    float squash = 0.10 * easeInOutQuad(head);

    float r = 1.0 + low * (0.45 + 0.55 * head) + detail - squash;
    vec3 p = dir * r;

    float phase = sawtooth(t, 0.35, 1.0);
    float surge = impulse(4.0, clamp(phase - 0.15 * s, 0.0, 1.0)) * u_Surge;

    // Outer shells trail further back, which is what gives the wake depth.
    float ext = u_WakeReach * (1.0 + u_ShellT * 0.85) * lick * crest * (1.0 + 0.9 * surge);
    p += W * ext;

    vec3 perp = p - W * dot(p, W);
    p -= perp * (0.6 * u_TongueTaper * lick * crest);

    // Shell spacing. Applied last so the whole shape, tongues included, grows.
    p *= 1.0 + u_ShellT * 0.30;

    wakeOut  = clamp(lick * (0.35 + 0.65 * crest), 0.0, 1.0);
    crestOut = crest;
    axialOut = s;
    return p;
}

void main() {
    vec3 dir = normalize(vs_Pos.xyz);
    float t = u_Time;

    float wake, crest, axial;
    vec3 p = shapePoint(dir, t, wake, crest, axial);

    vec3 ref = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 t1 = normalize(cross(ref, dir));
    vec3 t2 = cross(dir, t1);
    float eps = 0.02;
    float d0, d1, d2, d3, d4, d5;
    vec3 pa = shapePoint(normalize(dir + t1 * eps), t, d0, d1, d2);
    vec3 pb = shapePoint(normalize(dir + t2 * eps), t, d3, d4, d5);
    vec3 nor = normalize(cross(pa - p, pb - p));

    fs_Pos   = p;
    fs_Nor   = normalize(mat3(u_ModelInvTr) * nor);
    fs_Wake  = wake;
    fs_Crest = crest;
    fs_Axial = axial;

    gl_Position = u_ViewProj * u_Model * vec4(p, 1.0);
}
