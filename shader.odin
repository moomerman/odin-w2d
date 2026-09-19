package engine

// Load a custom shader from WGSL source.
// Custom shaders must declare the same group 0 bindings as the engine
// (projection, sampler, texture) and use group 1 for user uniforms.
// If compilation fails the error is logged and ok is false, but the shader
// is still usable: draws with it fall back to the default shader, and a
// later hot-reload of fixed source brings it to life.
load_shader :: proc(wgsl_source: string) -> (shader: Shader, ok: bool) #optional_ok {
	shader.handle, ok = ctx.renderer.load_shader(wgsl_source)
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
