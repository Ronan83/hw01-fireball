#version 300 es

// Full-screen background quad.
// The square's vertices already span [-1, 1], which is exactly clip space,
// so we skip every matrix and write the position straight to gl_Position.
// z = 0.999 pushes it behind everything else in the depth buffer.

in vec4 vs_Pos;

out vec2 fs_UV;

void main() {
    fs_UV = vs_Pos.xy;
    gl_Position = vec4(vs_Pos.xy, 0.999, 1.0);
}
