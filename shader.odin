package engine

// Custom shaders are WGSL. There are two forms:
//
// Fragment-only (load_fragment_shader) — the usual one. Write the fragment
// stage and your own uniforms and textures; the engine appends its prelude
// (render/wgpu/prelude.wgsl, the same one the default shader uses), which
// declares, and so reserves, these names:
//
//   struct VertexInput   vertex attributes (position, texcoord, color)
//   struct VertexOutput  what the fragment stage receives:
//     @builtin(position) position: vec4<f32>  framebuffer position, in pixels
//     @location(0) texcoord: vec2<f32>         texture coordinate
//     @location(1) color: vec4<f32>            vertex colour (premultiplied)
//   @group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
//   @group(0) @binding(1) var tex_sampler: sampler;  // the texture's filter/wrap
//   @group(0) @binding(2) var tex: texture_2d<f32>;  // the texture being drawn
//   @vertex fn vs_main
//
// A complete fragment-only shader:
//
//   struct Params { time: f32 };
//   @group(1) @binding(0) var<uniform> params: Params;
//
//   @fragment
//   fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
//       return textureSample(tex, tex_sampler, in.texcoord) * in.color;
//   }
//
// The prelude goes after your source, so line numbers in compile errors are
// those of the source you wrote.
//
// Full (load_shader) — for a custom vertex stage. The source must declare the
// same vertex input locations and group 0 bindings as the prelude, and its
// own vertex and fragment entry points.
//
// In both forms, group 1 is yours: at most one var<uniform> struct (set its
// fields with set_shader_uniform) and any number of texture_2d bindings
// (set_shader_texture). Group-1 samplers are not supported; sample with
// tex_sampler or read texels exactly with textureLoad.
//
// Colour is premultiplied by alpha throughout: the vertex colour and every
// texture sample arrive with RGB already scaled by A, and the fragment
// shader must return premultiplied colour too. `tex * in.color` and scaling
// the whole vec4 are already correct; to work on the true colour (a LUT, a
// hue shift) divide rgb by a first and multiply back afterwards.
//
// If compilation fails the error is logged and ok is false, but the shader
// is still usable: draws with it fall back to the default shader, and a
// later hot-reload of fixed source brings it to life.

// Load a fragment-only shader: the fragment stage and its group 1 bindings,
// completed by the engine's prelude (see above).
load_fragment_shader :: proc(wgsl_source: string) -> (shader: Shader, ok: bool) #optional_ok {
	shader.handle, ok = ctx.renderer.load_shader(wgsl_source, true)
	return
}

// Load a full shader, vertex stage included (see above).
load_shader :: proc(wgsl_source: string) -> (shader: Shader, ok: bool) #optional_ok {
	shader.handle, ok = ctx.renderer.load_shader(wgsl_source, false)
	return
}

// Set a uniform value by name on a custom shader. Array uniforms
// (array<T, N>) take a fixed array or slice of matching elements, e.g.
//   lights: [16][4]f32
//   w.set_shader_uniform(&shader, "lights", lights)
// Elements are copied into the WGSL array stride, so [N][3]f32 fills an
// array<vec3f, N> correctly. Extra elements are ignored.
set_shader_uniform :: proc(shader: ^Shader, name: string, value: any) {
	ctx.renderer.set_shader_uniform(shader.handle, name, value)
}

// Bind a texture to a named texture binding on a custom shader.
// The shader declares the binding in group 1, e.g.
//   @group(1) @binding(1) var lut: texture_2d<f32>;
// Until assigned, texture bindings read an engine-owned 1x1 white texture.
set_shader_texture :: proc(shader: ^Shader, name: string, texture: Texture) {
	ctx.renderer.set_shader_texture(shader.handle, name, texture.handle)
}

// Activate a custom shader for subsequent draw calls.
// Flushes the current batch if a different shader is active.
set_shader :: proc(shader: ^Shader) {
	ctx.renderer.set_shader(shader.handle)
}

// Reset to the default engine shader.
// Flushes the current batch if a custom shader is active.
reset_shader :: proc() {
	ctx.renderer.reset_shader()
}

// Destroy a custom shader and free its GPU resources.
destroy_shader :: proc(shader: ^Shader) {
	ctx.renderer.destroy_shader(shader.handle)
	shader.handle = {}
}
