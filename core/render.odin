package core

import "base:runtime"

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

// Render_Texture is a texture that can be used as a render target.
// Draw into it with set_render_target, then use .texture with draw_texture.
Render_Texture :: struct {
	texture: Texture,
}

// How a texture is sampled when it is drawn larger or smaller than its
// pixels, or at a fractional position. Per texture; set with
// set_texture_filter.
Texture_Filter :: enum u8 {
	Nearest, // default: crisp pixels, no blending between texels
	Linear, // bilinear: blends the four nearest texels (smooth scaling)
}

// What a texture sampled outside 0..1 returns — a source rect that extends
// past the texture's edges. Per texture; set with set_texture_wrap.
Texture_Wrap :: enum u8 {
	Clamp, // default: the edge texel repeats outwards
	Repeat, // the texture tiles
	Mirror, // the texture tiles, every other copy flipped
}

// How drawn pixels combine with what is already in the render target.
// Alpha is the default. Additive suits lights, particles and glow;
// Multiply suits shadows and light-map compositing.
//
// The renderer works in premultiplied alpha: texture data and vertex colours
// reach the shader with RGB already multiplied by alpha, and shaders output
// premultiplied colour. `src` below is that premultiplied colour, `a` its
// alpha. (The public API takes straight-alpha colours and pixels; they are
// premultiplied on the way in.)
Blend_Mode :: enum {
	Alpha, // src + dst*(1-a)
	Additive, // src + dst; coverage (dst alpha) is left unchanged
	Multiply, // src*dst + dst*(1-a); dst alpha is left unchanged
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

	// Push a textured quad into the current batch. Colours in the push_quad
	// procs are straight alpha; the backend premultiplies them.
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

	// Push a quad with explicit positions and one colour per vertex
	// (gradients, soft edges). Colours are interpolated across the quad.
	push_quad_colors:         proc(
		positions: [4]Vec2,
		src_uv: [4][2]f32,
		tex: Texture_Handle,
		colors: [4]Color,
	),

	// Create a texture from raw RGBA8 pixel data with premultiplied alpha
	// (as for update_texture and reload_texture). Returns an opaque handle.
	create_texture:           proc(data: []u8, width, height: int) -> Texture_Handle,

	// Create an empty texture (no initial pixel data). Used for atlases filled on demand.
	create_texture_empty:     proc(width, height: int) -> Texture_Handle,

	// Update a sub-region of an existing texture with new RGBA8 pixel data.
	update_texture:           proc(handle: Texture_Handle, data: []u8, x, y, width, height: int),

	// Destroy a texture and free its GPU resources.
	destroy_texture:          proc(handle: Texture_Handle),

	// Replace the contents of an existing texture in place behind its handle.
	// Same-size reloads update pixels only; size changes recreate the GPU
	// texture and rebind any custom-shader bindings that reference it.
	// Must be called outside begin_frame/present.
	reload_texture:           proc(handle: Texture_Handle, data: []u8, width, height: int),

	// Set how a texture is filtered and wrapped when sampled (by the default
	// shader and by custom shaders, through the group 0 sampler). Draws
	// already issued keep the previous setting; later draws use the new one.
	set_texture_sampling:     proc(
		handle: Texture_Handle,
		filter: Texture_Filter,
		wrap: Texture_Wrap,
	),

	// The texture's current filter and wrap; ok = false for an unknown handle.
	get_texture_sampling:     proc(
		handle: Texture_Handle,
	) -> (
		filter: Texture_Filter,
		wrap: Texture_Wrap,
		ok: bool,
	),

	// Get the built-in 1x1 white texture used for solid color drawing.
	get_white_texture:        proc() -> Texture_Handle,

	// Get rendering statistics for the most recently completed frame.
	get_stats:                proc(frame_time: f32) -> Stats,

	// Load a custom shader from WGSL source. Returns an opaque handle. If
	// compilation fails, ok is false but the handle is still valid: draws
	// with it use the default shader until a successful reload_shader.
	// fragment_only: the source is the fragment stage alone, and the backend
	// supplies the vertex format, group 0 bindings and vertex stage.
	load_shader:              proc(
		wgsl_source: string,
		fragment_only: bool,
	) -> (
		handle: Shader_Handle,
		ok: bool,
	),

	// Recompile a custom shader from new WGSL source in place behind its
	// handle, in the same form (full or fragment-only) it was loaded in.
	// Returns false — keeping the previous program intact — if compilation
	// fails. Uniform values and texture bindings are preserved
	// by name where compatible. Must be called outside begin_frame/present.
	reload_shader:            proc(handle: Shader_Handle, wgsl_source: string) -> bool,

	// Set a uniform value by name on a custom shader.
	set_shader_uniform:       proc(handle: Shader_Handle, name: string, value: any),

	// Bind a texture to a named group-1 texture binding on a custom shader.
	set_shader_texture:       proc(handle: Shader_Handle, name: string, texture: Texture_Handle),

	// Activate a custom shader for subsequent draw calls.
	set_shader:               proc(handle: Shader_Handle),

	// Reset to the default engine shader.
	reset_shader:             proc(),

	// Destroy a custom shader and free its GPU resources.
	destroy_shader:           proc(handle: Shader_Handle),

	// Set the blend mode for subsequent draw calls (default and custom shaders).
	set_blend_mode:           proc(mode: Blend_Mode),

	// Create a render texture that can be drawn into as a render target.
	create_render_texture:    proc(width, height: int) -> Texture_Handle,

	// Set the render target. Pass a texture handle to draw into a render
	// texture, or nil to draw to the screen. clear_color (straight alpha),
	// when set, clears the target; when nil the existing contents are preserved.
	set_render_target:        proc(target: Maybe(Texture_Handle), clear_color: Maybe(Color)),

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

	// Set or clear the scissor rectangle for subsequent draw calls.
	// Coordinates are in logical pixels; the backend handles DPI scaling.
	// Pass nil to reset to the full viewport.
	set_scissor_rect:         proc(rect: Maybe(Rect)),

	// Set a callback invoked after the final engine flush but before the render
	// pass ends. Custom renderers (e.g. slug text) use this to draw into the
	// same render pass. The callback receives the render pass handle and
	// framebuffer dimensions.
	set_pre_present_callback: proc(callback: proc(pass: rawptr, width, height: u32)),

	// Enable (default) or disable vsync; off uses a non-blocking present
	// mode when the surface offers one.
	set_vsync:                proc(enabled: bool),

	// Read back the screen as drawn so far this frame: flushes pending draws,
	// copies the surface texture to a buffer and blocks until it is mapped.
	// Returns tightly packed RGBA8, row 0 at the top, at framebuffer size.
	// The pre-present callback has not run yet, so its drawing is not
	// included. ok = false outside a frame or where unsupported (web).
	read_pixels:              proc(
		allocator: runtime.Allocator,
	) -> (
		pixels: []u8,
		width, height: int,
		ok: bool,
	),

	// Read back a render texture's contents as tightly packed RGBA8, row 0
	// at the top, premultiplied as stored. Works inside or outside a frame;
	// blocks until done.
	read_texture:             proc(
		handle: Texture_Handle,
		allocator: runtime.Allocator,
	) -> (
		pixels: []u8,
		width, height: int,
		ok: bool,
	),
}
