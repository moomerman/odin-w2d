// Engine shader prelude: the vertex format, the group 0 bindings and the
// vertex stage that every fragment-only shader (load_fragment_shader) and
// the engine's default shader (shader.wgsl) share. It is appended after the
// fragment source, not prepended, so line numbers in compile errors match
// the source you wrote (WGSL module-scope declarations may come in any
// order). Everything declared here is a reserved name in a fragment-only
// shader.

struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
};

// What the fragment stage receives. position is the fragment's framebuffer
// position in pixels; texcoord the texture coordinate (0..1 across the
// texture, beyond it for an oversized source rect); color the vertex colour,
// premultiplied by alpha.
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) texcoord: vec2<f32>,
    @location(1) color: vec4<f32>,
};

// Group 0 is the engine's: the projection, and the drawn texture with its
// sampler (the texture's own filter and wrap mode). Samples are
// premultiplied by alpha.
@group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
@group(0) @binding(1) var tex_sampler: sampler;
@group(0) @binding(2) var tex: texture_2d<f32>;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = projection * vec4<f32>(in.position, 0.0, 1.0);
    out.texcoord = in.texcoord;
    out.color = in.color;
    return out;
}
