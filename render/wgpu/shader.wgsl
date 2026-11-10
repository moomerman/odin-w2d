// The engine's default shader: a fragment-only shader, completed by
// prelude.wgsl exactly as load_fragment_shader completes a game's.

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(tex, tex_sampler, in.texcoord) * in.color;
}
