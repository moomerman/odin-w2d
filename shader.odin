package engine

// Load a custom shader from WGSL source.
// Custom shaders must declare the same group 0 bindings as the engine
// (projection, sampler, texture) and use group 1 for user uniforms.
load_shader :: proc(wgsl_source: string) -> Shader {
	return Shader{handle = ctx.renderer.load_shader(wgsl_source)}
}

// Set a uniform value by name on a custom shader.
set_shader_uniform :: proc(shader: ^Shader, name: string, value: any) {
	ctx.renderer.set_shader_uniform(shader.handle, name, value)
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
