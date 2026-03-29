package core

// Texture is backend-agnostic. The handle is an opaque ID managed by
// the active Render_Backend; width and height are cached for convenience.
Texture :: struct {
	handle: Texture_Handle,
	width:  int,
	height: int,
}

// Shader is backend-agnostic. The handle is an opaque ID managed by
// the active Render_Backend; all GPU resources are internal to the backend.
Shader :: struct {
	handle: Shader_Handle,
}

// Render_Backend abstracts over different rendering implementations.
// Currently the only backend is wgpu (render/wgpu package).
Render_Backend :: struct {
	// Initialize the renderer with the given window backend.
	// on_initialized is called once the GPU device is ready (synchronous on desktop,
	// async on web) — the engine uses this to fire the user's init callback.
	init:                     proc(window: ^Window_Backend, on_initialized: proc()),

	// Shut down the renderer and release all GPU resources.
	shutdown:                 proc(),

	// Handle a window resize — reconfigure the swapchain and projection.
	resize:                   proc(),

	// Returns true once the GPU device is ready and rendering can begin.
	is_initialized:           proc() -> bool,

	// Begin a new frame, clearing the screen with the given color.
	// Returns false if the surface is unavailable (e.g. minimized).
	begin_frame:              proc(color: Color) -> bool,

	// Submit the current frame to the GPU and present it.
	present:                  proc(),

	// Flush all batched vertices to the GPU.
	flush:                    proc(),

	// Push a textured quad into the current batch.
	push_quad:                proc(
		dst: Rect,
		src_uv: [4][2]f32,
		tex: Texture_Handle,
		color: Color,
	),

	// Push a textured quad with explicit vertex positions (for rotated/arbitrary quads).
	push_quad_ex:             proc(
		positions: [4]Vec2,
		src_uv: [4][2]f32,
		tex: Texture_Handle,
		color: Color,
	),

	// Create a texture from raw RGBA8 pixel data. Returns an opaque handle.
	create_texture:           proc(data: []u8, width, height: int) -> Texture_Handle,

	// Create an empty texture (no initial pixel data). Used for atlases filled on demand.
	create_texture_empty:     proc(width, height: int) -> Texture_Handle,

	// Update a sub-region of an existing texture with new RGBA8 pixel data.
	update_texture:           proc(handle: Texture_Handle, data: []u8, x, y, width, height: int),

	// Destroy a texture and free its GPU resources.
	destroy_texture:          proc(handle: Texture_Handle),

	// Get the built-in 1x1 white texture used for solid color drawing.
	get_white_texture:        proc() -> Texture_Handle,

	// Get rendering statistics for the most recently completed frame.
	get_stats:                proc(frame_time: f32) -> Stats,

	// Load a custom shader from WGSL source. Returns an opaque handle.
	load_shader:              proc(wgsl_source: string) -> Shader_Handle,

	// Set a uniform value by name on a custom shader.
	set_shader_uniform:       proc(handle: Shader_Handle, name: string, value: any),

	// Activate a custom shader for subsequent draw calls.
	set_shader:               proc(handle: Shader_Handle),

	// Reset to the default engine shader.
	reset_shader:             proc(),

	// Destroy a custom shader and free its GPU resources.
	destroy_shader:           proc(handle: Shader_Handle),

	// Return the underlying GPU device handle as a raw pointer.
	// For the wgpu backend this is a wgpu.Device.
	get_gpu_device:           proc() -> rawptr,

	// Return the underlying GPU queue handle as a raw pointer.
	// For the wgpu backend this is a wgpu.Queue.
	get_gpu_queue:            proc() -> rawptr,

	// Return the surface texture format as a u32 (cast to the backend's enum).
	// For the wgpu backend this is a wgpu.TextureFormat.
	get_surface_format:       proc() -> u32,

	// Upload a combined view-projection matrix to the GPU uniform buffer.
	// Used by the camera system to apply camera transforms.
	set_view_projection:      proc(m: matrix[4, 4]f32),

	// Set a callback invoked after the final engine flush but before the render
	// pass ends. Custom renderers (e.g. slug text) use this to draw into the
	// same render pass. The callback receives the render pass handle and
	// framebuffer dimensions.
	set_pre_present_callback: proc(callback: proc(pass: rawptr, width, height: u32)),
}
