#version 300 es

//  src/shaders/fireball-frag.glsl
//
//  Flat-shaded cellular fire, one shell per pass.
//
//  Design rules, in order of importance:
//    1. NO lighting. Nothing multiplies the colour by less than one. Fire
//       emits light, it does not receive it.
//    2. Colour is SELECTED, not interpolated: five flat palette entries.
//    3. Outer shells sit lower on the palette and are shredded far more, so
//       the hot core shows through their gaps. That hole-through-hole
//       layering is where the sense of depth comes from -- not from alpha
//       blending, which just muddies flat colours.
//    4. Erosion removes WHOLE CELLS, so every edge is clean.

precision highp float;

uniform float u_Time;
uniform float u_ShellT;        // 0 = innermost core ... 1 = outermost shell
uniform vec3  u_WakeAxis;
uniform float u_StreamSpeed;

uniform vec3  u_EmberColor;    // coolest tier   [GUI]
uniform vec3  u_BlazeColor;    // middle tier    [GUI]
uniform vec3  u_CoreColor;     // hottest tier   [GUI]

uniform float u_Tiers;         // how many flat steps, 3 - 6
uniform float u_Shred;         // how much of the wake breaks away
uniform float u_CellScale;     // Voronoi cell density

in vec3  fs_Pos;
in vec3  fs_Nor;
in float fs_Wake;
in float fs_Crest;
in float fs_Axial;

out vec4 out_Col;

// Toolbox: Bias / Gain, shaping the heat gradient before it is tiered
float bias(float b, float t) { return pow(t, log(b) / log(0.5)); }
float gain(float g, float t) {
    if (t < 0.5) return bias(1.0 - g, 2.0 * t) * 0.5;
    return 1.0 - bias(1.0 - g, 2.0 - 2.0 * t) * 0.5;
}

vec3 hash33(vec3 p) {
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6)));
    return fract(sin(p) * 43758.5453123);
}

// 3D Voronoi. Returns F1 distance and the winning cell's random value, which
// is constant across the cell -- that is what makes the blocks flat.
float voronoi3(vec3 p, out float cellRand) {
    vec3 ip = floor(p);
    vec3 fp = fract(p);

    float best = 8.0;
    vec3  bestCell = ip;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            for (int z = -1; z <= 1; ++z) {
                vec3 g = vec3(float(x), float(y), float(z));
                vec3 o = hash33(ip + g);
                vec3 d = g + o - fp;
                float dist = dot(d, d);
                if (dist < best) {
                    best = dist;
                    bestCell = ip + g;
                }
            }
        }
    }

    cellRand = hash33(bestCell + 19.3).x;
    return sqrt(best);
}

vec3 palette(int i) {
    if (i <= 0) return u_EmberColor;
    if (i == 1) return mix(u_EmberColor, u_BlazeColor, 0.5);
    if (i == 2) return u_BlazeColor;
    if (i == 3) return u_CoreColor;
    return mix(u_CoreColor, vec3(1.0), 0.55);
}

void main() {
    vec3 W = normalize(u_WakeAxis);
    float seed = u_ShellT * 23.7;

    vec3 cp = fs_Pos * max(u_CellScale * 1.7, 1.0)
            - W * (u_Time * u_StreamSpeed * 1.3) + seed;
    float cellRand;
    float f1 = voronoi3(cp, cellRand);

    float coarseRand;
    voronoi3(fs_Pos * 1.6 - W * (u_Time * u_StreamSpeed * 0.55) + 31.7 + seed, coarseRand);

    // ---- shred: outer shells are mostly holes, the core is nearly solid ---
    float shred = mix(0.10, 0.66, u_ShellT) * u_Shred;
    shred += 0.30 * smoothstep(0.30, 1.0, fs_Wake) * u_Shred;
    if (cellRand < shred) discard;

    // ---- heat: ordered gradient first, cell jitter second -----------------
    float lead = smoothstep(0.65, -1.0, fs_Axial);
    float heat = mix(0.20, 1.00, gain(0.50, lead));
    heat -= u_ShellT * 0.42;                // outer shells are cooler
    heat += (cellRand   - 0.5) * 0.22;
    heat += (coarseRand - 0.5) * 0.14;
    heat += 0.30 * fs_Crest;                // displacement drives colour
    heat -= 0.18 * fs_Wake;
    heat = clamp(heat, 0.0, 1.0);

    // ---- pick one flat colour, no blending --------------------------------
    int n = int(clamp(u_Tiers, 3.0, 6.0));
    int tier = int(floor(heat * float(n)));
    tier = clamp(tier, 0, n - 1);

    int pi = int(floor(float(tier) / float(max(n - 1, 1)) * 4.0 + 0.5));
    vec3 col = palette(clamp(pi, 0, 4));

    // Glowing seams along cell boundaries, inside already-hot zones only.
    if (f1 < 0.07 && heat > 0.62) {
        col = palette(4);
    }

    out_Col = vec4(col, 1.0);
}
