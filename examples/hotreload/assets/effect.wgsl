// Scanline post-processing shader.
// Uses the same vertex format and group 0 bindings as the default engine shader.
// Group 1 contains custom uniforms (time, intensity, line spacing).

struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) texcoord: vec2<f32>,
    @location(1) color: vec4<f32>,
};

struct Params {
    time: f32,
    intensity: f32,
    line_spacing: f32,
};

// Engine-managed bindings (group 0) — must match default shader
@group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
@group(0) @binding(1) var tex_sampler: sampler;
@group(0) @binding(2) var tex: texture_2d<f32>;

// User uniforms (group 1)
@group(1) @binding(0) var<uniform> params: Params;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = projection * vec4<f32>(in.position, 0.0, 1.0);
    out.texcoord = in.texcoord;
    out.color = in.color;
    return out;
}

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
