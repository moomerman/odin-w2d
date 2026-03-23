// Aurora background shader.
// Animated color waves with a mouse-following glow and subtle vignette.
// Uses the same vertex format and group 0 bindings as the default engine shader.
// Group 1 contains custom uniforms (time, mouse position, intensity).

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
    mouse_x: f32,
    mouse_y: f32,
    intensity: f32,
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
    let uv = in.texcoord;
    let t = params.time;

    // Layered sine waves create undulating color bands
    let wave1 = sin(uv.x * 6.283 + t * 0.5) * cos(uv.y * 3.14 + t * 0.3);
    let wave2 = sin(uv.y * 5.0 + t * 0.7 + 1.0) * cos(uv.x * 4.0 - t * 0.4);
    let wave3 = sin((uv.x + uv.y) * 3.5 + t * 0.6 + 2.0);

    let r = wave1 * 0.5 + 0.5;
    let g = wave2 * 0.5 + 0.5;
    let b = wave3 * 0.5 + 0.5;

    // Soft glow that follows the mouse cursor
    let mouse = vec2<f32>(params.mouse_x, params.mouse_y);
    let d = distance(uv, mouse);
    let glow = exp(-d * d * 10.0) * params.intensity;

    // Subtle vignette: darken edges for depth
    let vignette = 1.0 - length(uv - 0.5) * 0.6;

    // Dark atmospheric background with color hints + bright mouse glow
    let color = vec3<f32>(
        r * 0.06 + glow * 0.25,
        g * 0.04 + glow * 0.15,
        b * 0.10 + glow * 0.35,
    ) * vignette;

    return vec4<f32>(color, 1.0) * tex_color * in.color;
}
