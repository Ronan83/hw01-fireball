#version 300 es
precision highp float;

//  src/shaders/background-frag.glsl
//
//  Starfield: three layers of jittered cells at different scales, each star
//  with its own twinkle phase and colour temperature, so the field reads as
//  scattered depth rather than a grid.
//
//  A radial heat glow tinted by the fireball's ember colour makes the ball
//  light the space around it. Stars are washed out inside the glow, which is
//  what sells it as a light source rather than a colour overlay.

uniform float u_Time;         // seconds since page load
uniform vec2  u_Dims;         // viewport size, used to correct the aspect ratio
uniform vec3  u_EmberColor;   // fireball's coolest tier, drives the glow tint

in vec2 fs_UV;
out vec4 out_Col;

// 2D hash returning a single pseudo-random float in [0, 1].
float hash21(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

// A hash returning two independent values, used to jitter a star
// away from the center of its cell.
vec2 hash22(vec2 p) {
    return fract(sin(vec2(
        dot(p, vec2(127.1, 311.7)),
        dot(p, vec2(269.5, 183.3))
    )) * 43758.5453);
}

// One layer of stars: divide the plane into cells, put at most one star
// in each, and keep only the cells whose hash clears the threshold.
// density < 1 leaves most cells empty, which is what makes it look scattered
// rather than gridded.
vec3 starLayer(vec2 uv, float cellSize, float density, float brightness) {
    vec2 grid = uv / cellSize;
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;

    float keep = hash21(cell);
    if (keep > density) return vec3(0.0);

    // Offset the star from the cell center so the grid isn't visible.
    vec2 jitter = (hash22(cell) - 0.5) * 0.7;
    float d = length(local - jitter);

    // Twinkle: each star gets its own phase so they don't pulse together.
    float phase = hash21(cell + 7.3) * 6.283;
    float twinkle = 0.65 + 0.35 * sin(u_Time * 3.0 + phase);

    // A tight falloff gives a small round core with a soft halo.
    float core = smoothstep(0.09, 0.0, d);
    float halo = smoothstep(0.30, 0.0, d) * 0.25;

    // Slight color variation: some stars lean blue, some warm.
    float temp = hash21(cell + 3.1);
    vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.78), temp);

    return tint * (core + halo) * twinkle * brightness;
}

void main() {
    // Correct for a non-square viewport so stars stay round.
    vec2 uv = fs_UV;
    uv.x *= u_Dims.x / u_Dims.y;

    // A very dark blue base rather than pure black, so the scene
    // doesn't look like a hole cut out of the page.
    vec3 col = vec3(0.02, 0.025, 0.045);

    // Three layers at different scales gives an impression of depth.
    vec3 stars = starLayer(uv, 0.055, 0.55, 1.0)
               + starLayer(uv, 0.028, 0.35, 0.6)
               + starLayer(uv, 0.015, 0.20, 0.35);

    // --- heat glow radiating from the fireball -----------------------------
    // Aspect-corrected distance from the centre of the frame, where the ball
    // sits. A high power keeps the falloff tight so it reads as a light
    // source rather than a flat wash over the whole screen.
    float d = length(vec2(fs_UV.x * u_Dims.x / u_Dims.y, fs_UV.y * 1.08));
    float glow = pow(smoothstep(1.35, 0.0, d), 2.8);

    // Slow breathing so the glow is animated like everything else.
    float breathe = 0.86 + 0.14 * sin(u_Time * 1.5);

    // Stars near a bright source wash out; that contrast is what makes the
    // glow read as light rather than as a coloured overlay.
    stars *= 1.0 - 0.75 * glow;
    col += stars;

    col += u_EmberColor * glow * 0.42 * breathe;

    // Faint outer halo, much wider and weaker, to soften the transition.
    float halo = pow(smoothstep(2.0, 0.0, d), 1.6);
    col += u_EmberColor * halo * 0.06;

    out_Col = vec4(col, 1.0);
}
