package core

import "vendor:wgpu"

// Texture is backend-agnostic. The handle is an opaque ID managed by
// the active Render_Backend; width and height are cached for convenience.
Texture :: struct {
	handle: Texture_Handle,
	width:  int,
	height: int,
}

// WGSL type tag for uniform metadata.
Shader_Uniform_Type :: enum {
	F32,
	I32,
	U32,
	Vec2F32,
	Vec3F32,
	Vec4F32,
	Mat4x4F32,
}

// Metadata for a single uniform field within a shader's uniform buffer.
Shader_Uniform :: struct {
	offset: int,
	size:   int,
	type:   Shader_Uniform_Type,
}

// A loaded custom shader with its GPU resources and uniform metadata.
Shader :: struct {
	// WGPU resources
	module:            wgpu.ShaderModule,
	pipeline:          wgpu.RenderPipeline,
	pipeline_layout:   wgpu.PipelineLayout,
	bind_group_layout: wgpu.BindGroupLayout, // group 1 layout
	bind_group:        wgpu.BindGroup, // group 1 bind group

	// Uniform buffer
	uniform_buffer:    wgpu.Buffer,
	uniform_data:      []u8, // CPU staging buffer
	uniform_dirty:     bool,
	uniform_size:      int,

	// Uniform metadata (from parser)
	uniforms:          map[string]Shader_Uniform, // name -> offset/size/type

	// Entry points
	vertex_entry:      string,
	fragment_entry:    string,
}

// Render_Backend abstracts over different rendering implementations.
// Currently the only backend is wgpu (render/wgpu package).
Render_Backend :: struct {
	// Initialize the renderer with the given window backend.
	// on_initialized is called once the GPU device is ready (synchronous on desktop,
	// async on web) — the engine uses this to fire the user's init callback.
	init:                 proc(window: ^Window_Backend, on_initialized: proc()),

	// Shut down the renderer and release all GPU resources.
	shutdown:             proc(),

	// Handle a window resize — reconfigure the swapchain and projection.
	resize:               proc(),

	// Returns true once the GPU device is ready and rendering can begin.
	is_initialized:       proc() -> bool,

	// Begin a new frame, clearing the screen with the given color.
	// Returns false if the surface is unavailable (e.g. minimized).
	begin_frame:          proc(color: Color) -> bool,

	// Submit the current frame to the GPU and present it.
	present:              proc(),

	// Flush all batched vertices to the GPU.
	flush:                proc(),

	// Push a textured quad into the current batch.
	push_quad:            proc(dst: Rect, src_uv: [4][2]f32, tex: Texture_Handle, color: Color),

	// Push a textured quad with explicit vertex positions (for rotated/arbitrary quads).
	push_quad_ex:         proc(
		positions: [4]Vec2,
		src_uv: [4][2]f32,
		tex: Texture_Handle,
		color: Color,
	),

	// Create a texture from raw RGBA8 pixel data. Returns an opaque handle.
	create_texture:       proc(data: []u8, width, height: int) -> Texture_Handle,

	// Create an empty texture (no initial pixel data). Used for atlases filled on demand.
	create_texture_empty: proc(width, height: int) -> Texture_Handle,

	// Update a sub-region of an existing texture with new RGBA8 pixel data.
	update_texture:       proc(handle: Texture_Handle, data: []u8, x, y, width, height: int),

	// Destroy a texture and free its GPU resources.
	destroy_texture:      proc(handle: Texture_Handle),

	// Get the built-in 1x1 white texture used for solid color drawing.
	get_white_texture:    proc() -> Texture_Handle,

	// Get rendering statistics for the most recently completed frame.
	get_stats:            proc(frame_time: f32) -> Stats,

	// Load a custom shader from WGSL source. Returns a Shader with GPU resources.
	load_shader:          proc(wgsl_source: string) -> Shader,

	// Set a uniform value by name on a custom shader.
	set_shader_uniform:   proc(shader: ^Shader, name: string, value: any),

	// Activate a custom shader for subsequent draw calls.
	set_shader:           proc(shader: ^Shader),

	// Reset to the default engine shader.
	reset_shader:         proc(),

	// Destroy a custom shader and free its GPU resources.
	destroy_shader:       proc(shader: ^Shader),
}
