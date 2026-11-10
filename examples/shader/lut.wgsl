// Color LUT (lookup table) shader, fragment-only (load_fragment_shader): the
// engine supplies VertexOutput, tex, tex_sampler and the vertex stage.
// Maps the luminance of each pixel through a 256x1 gradient texture bound
// via set_shader_texture. The LUT uses textureLoad for exact texel reads,
// so no extra sampler is needed.

struct Params {
    mix_amount: f32,
};

// User bindings (group 1)
@group(1) @binding(0) var<uniform> params: Params;
@group(1) @binding(1) var lut: texture_2d<f32>;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // Colour arrives premultiplied by alpha; recover the true colour before
    // grading it, and premultiply the result again.
    let base = textureSample(tex, tex_sampler, in.texcoord) * in.color;
    let rgb = base.rgb / max(base.a, 0.0001);

    // Remap luminance through the 256x1 LUT
    let luma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let idx = i32(clamp(luma, 0.0, 1.0) * 255.0);
    let mapped = textureLoad(lut, vec2<i32>(idx, 0), 0);

    return vec4<f32>(mix(rgb, mapped.rgb, params.mix_amount) * base.a, base.a);
}
