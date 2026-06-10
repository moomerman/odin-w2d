// Color LUT (lookup table) shader.
// Maps the luminance of each pixel through a 256x1 gradient texture bound
// via set_shader_texture. The LUT uses textureLoad for exact texel reads,
// so no extra sampler is needed.

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
    mix_amount: f32,
};

// Engine-managed bindings (group 0) — must match default shader
@group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
@group(0) @binding(1) var tex_sampler: sampler;
@group(0) @binding(2) var tex: texture_2d<f32>;

// User bindings (group 1)
@group(1) @binding(0) var<uniform> params: Params;
@group(1) @binding(1) var lut: texture_2d<f32>;

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
    let base = textureSample(tex, tex_sampler, in.texcoord) * in.color;

    // Remap luminance through the 256x1 LUT
    let luma = dot(base.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let idx = i32(clamp(luma, 0.0, 1.0) * 255.0);
    let mapped = textureLoad(lut, vec2<i32>(idx, 0), 0);

    return vec4<f32>(mix(base.rgb, mapped.rgb, params.mix_amount), base.a);
}
