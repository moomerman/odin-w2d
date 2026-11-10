// Scanline post-processing shader, fragment-only (load_fragment_shader): the
// engine supplies VertexOutput, tex, tex_sampler and the vertex stage.
// Group 1 contains custom uniforms (time, intensity, line spacing).

struct Params {
    time: f32,
    intensity: f32,
    line_spacing: f32,
};

// User uniforms (group 1)
@group(1) @binding(0) var<uniform> params: Params;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let tex_color = textureSample(tex, tex_sampler, in.texcoord);
    let base = tex_color * in.color;

    // Scanline effect: darken every Nth pixel row with a time-based scroll
    let y = in.position.y + params.time * 30.0;
    let line = sin(y * 3.14159 / params.line_spacing) * 0.5 + 0.5;
    let scanline = 1.0 - params.intensity * (1.0 - line);

    return vec4<f32>(base.rgb * scanline, base.a);
}
