package renderer_wgpu

import "base:runtime"
import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:time"
import "vendor:wgpu"

import core "../../core"

//-----------//
// CONSTANTS //
//-----------//

// Maximum number of quads per batch before flushing.
@(private = "package")
BATCH_MAX_QUADS :: 4096
@(private = "package")
BATCH_MAX_VERTICES :: BATCH_MAX_QUADS * 4
@(private = "package")
BATCH_MAX_INDICES :: BATCH_MAX_QUADS * 6

// Vertex layout: position (2 floats) + texcoord (2 floats) + color (4 floats) = 8 floats = 32 bytes
@(private = "package")
VERTEX_FLOATS :: 8
@(private = "package")
VERTEX_SIZE :: VERTEX_FLOATS * size_of(f32)

// Each GPU vertex buffer holds multiple batches so that each flush within a
// frame writes to a distinct region (wgpu stages all writes before execution,
// so reusing the same offset would corrupt earlier draw calls). When a frame
// fills one buffer the next flush moves on to another, created on first
// need and kept for later frames, so there is no per-frame quad limit.
@(private = "package")
GPU_BUFFER_BATCHES :: 8
@(private = "package")
GPU_BUFFER_VERTICES :: BATCH_MAX_VERTICES * GPU_BUFFER_BATCHES

@(private = "package")
MAX_BIND_GROUPS_PER_FRAME :: 256

// The projection buffer holds multiple view-projection matrices so that
// mid-frame camera changes (e.g. world → UI) each get their own slot.
// Slot 0 always holds the base window projection; each frame's camera and
// render-target changes use slots 1 ..< MAX_PROJECTION_SLOTS.
// Same principle as GPU_BUFFER_BATCHES for vertices.
// Each slot is aligned to 256 bytes (wgpu min_uniform_buffer_offset_alignment).
@(private = "package")
MAX_PROJECTION_SLOTS :: 32
@(private = "package")
PROJECTION_SLOT_STRIDE :: 256 // must be >= min_uniform_buffer_offset_alignment
@(private = "package")
PROJECTION_MATRIX_SIZE :: size_of(matrix[4, 4]f32)

// Custom shader uniforms use the same scheme: each shader's uniform buffer
// holds several copies of its uniform struct, bound with a dynamic offset,
// and every flush whose values changed writes the next slot. So a draw sees
// the values set when it was issued, not the last values set in the frame.
// Slots are aligned to 256 bytes — the largest min_uniform_buffer_offset_alignment
// WebGPU allows, so valid on every device. The buffer doubles when a frame
// runs out of slots.
@(private = "package")
UNIFORM_SLOT_ALIGNMENT :: 256
@(private = "package")
UNIFORM_INITIAL_SLOTS :: 16

//-------//
// TYPES //
//-------//

@(private = "package")
Renderer_Stats :: struct {
	draw_calls:       int,
	quads:            int,
	vertices:         int,
	texture_switches: int,
	textures_alive:   int,
	texture_memory:   int, // estimated bytes (w * h * 4)
}

// Internal GPU resource pair for a texture.
@(private = "package")
Texture_Entry :: struct {
	handle: wgpu.Texture,
	view:   wgpu.TextureView,
	width:  int,
	height: int,
}

// WGSL type tag for uniform metadata.
@(private = "package")
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
@(private = "package")
Shader_Uniform :: struct {
	offset: int,
	size:   int, // total byte size (count * stride for arrays)
	type:   Shader_Uniform_Type, // element type for arrays
	count:  int, // array element count, 0 for non-arrays
	stride: int, // byte distance between array elements
	warned: bool, // a bad value was already reported for this uniform
}

// A group-1 texture binding slot within a custom shader.
// Stores the handle (not the view) so a destroyed texture fails gracefully:
// rebuilds fall back to the white texture instead of a dangling view.
@(private = "package")
Shader_Texture :: struct {
	binding: u32,
	texture: core.Texture_Handle, // zero-value = unset (white texture)
}

// Internal GPU resources and metadata for a custom shader.
@(private = "package")
Shader_Entry :: struct {
	handle:            core.Shader_Handle,

	// WGPU resources
	// One pipeline per blend mode, created on first use. pipelines[.Alpha]
	// is built at load time and is nil when the shader failed to compile —
	// draws then fall back to the default pipeline.
	module:            wgpu.ShaderModule,
	pipelines:         [core.Blend_Mode]wgpu.RenderPipeline,
	pipeline_layout:   wgpu.PipelineLayout,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
	bind_group_dirty:  bool, // a texture changed — rebuild at next flush

	// Uniform buffer: uniform_capacity slots of uniform_stride bytes each.
	// uniform_data is the CPU copy of the current values; uniform_dirty
	// means it differs from the slot at uniform_offset and the next flush
	// must write a new slot.
	uniform_buffer:    wgpu.Buffer,
	uniform_data:      []u8,
	uniform_dirty:     bool,
	uniform_size:      int,
	uniform_binding:   u32,
	uniform_stride:    u64,
	uniform_capacity:  int,
	uniform_slot:      int, // next slot to write this frame
	uniform_offset:    u32, // dynamic offset of the slot draws bind
	uniform_frame:     u64, // frame_index uniform_slot was last reset in

	// Uniform metadata
	uniforms:          map[string]Shader_Uniform,

	// Texture binding metadata (group 1)
	textures:          map[string]Shader_Texture,

	// Entry points
	vertex_entry:      string,
	fragment_entry:    string,
}

// Per-frame transient GPU state, reset at the start of each frame.
@(private = "package")
Frame_State :: struct {
	encoder:          wgpu.CommandEncoder,
	pass:             wgpu.RenderPassEncoder,
	surface_tex:      wgpu.SurfaceTexture,
	view:             wgpu.TextureView,
	active:           bool,
	// The surface was unavailable (occluded) and this frame draws into the
	// offscreen texture instead; nothing is presented.
	offscreen:        bool,
	// Render texture the current pass draws into, or nil for the screen.
	target:           Maybe(core.Texture_Handle),
	// Pixel size of this frame's screen attachment (surface or offscreen
	// texture) and of the current pass's attachment, for scissor clamping.
	surface_w:        u32,
	surface_h:        u32,
	target_w:         u32,
	target_h:         u32,

	// Bind groups created this frame — released after submit, not mid-pass.
	bind_groups:      [MAX_BIND_GROUPS_PER_FRAME]wgpu.BindGroup,
	bind_group_count: int,
	// Buffers replaced this frame (grown uniform buffers) that recorded
	// draws may still reference — released after submit.
	released_buffers: [dynamic]wgpu.Buffer,
	// Cache so switching back and forth between the same textures reuses
	// one bind group per (texture, projection slot) instead of creating a
	// new one on every switch. Cleared each frame.
	bind_group_cache: map[Bind_Group_Key]wgpu.BindGroup,
}

@(private = "package")
Bind_Group_Key :: struct {
	view:   wgpu.TextureView,
	offset: u64, // projection slot byte offset
}

// Vertex batching state within a frame.
@(private = "package")
Batch_State :: struct {
	vertices:      [BATCH_MAX_VERTICES * VERTEX_FLOATS]f32,
	vertex_count:  int,
	buffer_index:  int, // vertex buffer the next flush writes to
	buffer_offset: int, // running offset (in vertices) into that buffer
	texture_view:  wgpu.TextureView, // currently bound texture for batching
	bind_group:    wgpu.BindGroup, // current projection+sampler+texture bind group
	active_shader: core.Shader_Handle, // zero-value = default pipeline
	blend_mode:    core.Blend_Mode,
}

@(private = "package")
Renderer :: struct {
	ctx:                  runtime.Context,

	// Reference to the window backend for framebuffer queries.
	window:               ^core.Window_Backend,

	// Callback invoked once the GPU device is ready.
	on_initialized:       proc(),

	// Core wgpu objects
	instance:             wgpu.Instance,
	surface:              wgpu.Surface,
	adapter:              wgpu.Adapter,
	device:               wgpu.Device,
	queue:                wgpu.Queue,
	config:               wgpu.SurfaceConfiguration,

	// Pipeline
	shader_module:        wgpu.ShaderModule,
	pipeline_layout:      wgpu.PipelineLayout,
	pipelines:            [core.Blend_Mode]wgpu.RenderPipeline, // one per blend mode

	// Bind group for projection + sampler + texture
	bind_group_layout:    wgpu.BindGroupLayout,

	// Projection uniform buffer (holds MAX_PROJECTION_SLOTS matrices)
	projection_buffer:    wgpu.Buffer,
	projection_offset:    u64, // byte offset of the current slot
	projection_slot:      int, // next slot to write to
	base_projection:      matrix[4, 4]f32, // CPU copy of slot 0

	// Sampler
	sampler:              wgpu.Sampler,

	// Vertex buffers (GPU side), each GPU_BUFFER_VERTICES vertices; a frame
	// uses as many as it fills, starting from the first.
	vertex_buffers:       [dynamic]wgpu.Buffer,

	// Index buffer (GPU side, static — generated once at init)
	index_buffer:         wgpu.Buffer,

	// White 1x1 texture used for solid color drawing
	white_texture:        core.Texture_Handle,

	// Dimensions
	width:                u32,
	height:               u32,

	// Initialization state
	initialized:          bool,

	// Texture handle map
	textures:             map[core.Texture_Handle]Texture_Entry,
	next_handle_id:       u64,

	// Shader handle map
	shaders:              hm.Dynamic_Handle_Map(Shader_Entry, core.Shader_Handle),

	// Stats for the current frame being built, and the last completed frame.
	current_stats:        Renderer_Stats,
	last_stats:           Renderer_Stats,

	// Per-frame and batching state.
	frame:                Frame_State,
	frame_index:          u64, // incremented by every begin_frame
	batch:                Batch_State,

	// Active scissor rect in logical pixels, or nil for full viewport.
	scissor_rect:         Maybe(core.Rect),
	// The scissor rect lies entirely outside the current target (or has no
	// area): flushes discard their quads instead of drawing.
	scissor_empty:        bool,

	// Optional callback invoked after engine flush, before render pass ends.
	pre_present_callback: proc(pass: rawptr, width, height: u32),

	// Whether the surface was configured with CopySrc, so read_pixels can
	// copy the swapchain texture.
	surface_copy_src:     bool,

	// Present modes the surface supports, for set_vsync; vsync is the
	// requested state, applied by the next begin_frame.
	present_modes:        [4]wgpu.PresentMode,
	present_mode_count:   int,
	vsync:                bool,

	// Window-sized render target used when a frame is not drawn to the
	// surface: the window is occluded or (macOS) not yet shown, or vsync
	// is off and the surface was presented less than a display period ago.
	// Created on first use, recreated on resize.
	offscreen_tex:        wgpu.Texture,
	offscreen_view:       wgpu.TextureView,
	offscreen_w:          u32,
	offscreen_h:          u32,
	last_surface_frame:   time.Tick, // begin of the last frame drawn to the surface
}

@(private = "package")
renderer: Renderer

//------------//
// PUBLIC API //
//------------//

// Returns a Render_Backend vtable populated with the wgpu implementation procs.
backend :: proc() -> core.Render_Backend {
	return core.Render_Backend {
		init = renderer_init,
		shutdown = renderer_shutdown,
		resize = renderer_resize,
		is_initialized = renderer_is_initialized,
		begin_frame = renderer_begin_frame,
		present = renderer_present,
		flush = renderer_flush,
		push_quad = renderer_push_quad,
		push_quad_ex = renderer_push_quad_ex,
		push_quad_colors = renderer_push_quad_colors,
		create_texture = renderer_create_texture,
		create_texture_empty = renderer_create_texture_empty,
		update_texture = renderer_update_texture,
		reload_texture = renderer_reload_texture,
		destroy_texture = renderer_destroy_texture,
		get_white_texture = renderer_get_white_texture,
		get_stats = renderer_get_stats,
		load_shader = renderer_load_shader,
		reload_shader = renderer_reload_shader,
		set_shader_uniform = renderer_set_shader_uniform,
		set_shader_texture = renderer_set_shader_texture,
		set_shader = renderer_set_shader,
		reset_shader = renderer_reset_shader,
		destroy_shader = renderer_destroy_shader,
		set_blend_mode = renderer_set_blend_mode,
		create_render_texture = renderer_create_render_texture,
		set_render_target = renderer_set_render_target,
		get_gpu_device = renderer_get_gpu_device,
		get_gpu_queue = renderer_get_gpu_queue,
		get_surface_format = renderer_get_surface_format,
		set_view_projection = renderer_set_view_projection,
		set_scissor_rect = renderer_set_scissor_rect,
		set_pre_present_callback = renderer_set_pre_present_callback,
		set_vsync = renderer_set_vsync,
		read_pixels = renderer_read_pixels,
		read_texture = renderer_read_texture,
	}
}

//------//
// INIT //
//------//

@(private = "file")
renderer_init :: proc(window: ^core.Window_Backend, on_initialized: proc()) {
	renderer.ctx = context
	renderer.window = window
	renderer.on_initialized = on_initialized
	renderer.next_handle_id = 1
	renderer.vsync = true
	renderer.textures = make(map[core.Texture_Handle]Texture_Entry)
	hm.dynamic_init(&renderer.shaders, context.allocator)

	renderer.instance = wgpu.CreateInstance(nil)
	if renderer.instance == nil {
		panic("[renderer/wgpu] WebGPU is not supported")
	}

	renderer.surface = wgpu.Surface(window.get_surface(renderer.instance))

	wgpu.InstanceRequestAdapter(
		renderer.instance,
		&{compatibleSurface = renderer.surface},
		{callback = on_adapter},
	)

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: string,
		userdata1, userdata2: rawptr,
	) {
		context = renderer.ctx
		if status != .Success || adapter == nil {
			fmt.panicf("[renderer/wgpu] request adapter failure: [%v] %s", status, message)
		}
		renderer.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, {callback = on_device})
	}

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: string,
		userdata1, userdata2: rawptr,
	) {
		context = renderer.ctx
		if status != .Success || device == nil {
			fmt.panicf("[renderer/wgpu] request device failure: [%v] %s", status, message)
		}
		renderer.device = device
		renderer_on_device_ready()
	}
}

@(private = "file")
renderer_on_device_ready :: proc() {
	r := &renderer

	r.width, r.height = r.window.get_framebuffer_size()
	r.queue = wgpu.DeviceGetQueue(r.device)

	// Configure surface. CopySrc (when the surface allows it) lets
	// read_pixels copy the swapchain texture directly; desktop only, since
	// readback is not implemented on web.
	usage := wgpu.TextureUsageFlags{.RenderAttachment}
	when ODIN_OS != .JS {
		// A nil surface is the null window backend (headless): every frame
		// draws into the offscreen target and nothing is configured.
		if r.surface == nil {
		} else if caps, status := wgpu.SurfaceGetCapabilities(r.surface, r.adapter);
		   status == .Success {
			if .CopySrc in caps.usages {
				usage += {.CopySrc}
				r.surface_copy_src = true
			}
			r.present_mode_count = min(int(caps.presentModeCount), len(r.present_modes))
			for i in 0 ..< r.present_mode_count {
				r.present_modes[i] = caps.presentModes[i]
			}
			wgpu.SurfaceCapabilitiesFreeMembers(caps)
		}
	}
	r.config = wgpu.SurfaceConfiguration {
		device      = r.device,
		usage       = usage,
		format      = .BGRA8Unorm,
		width       = r.width,
		height      = r.height,
		presentMode = present_mode_for(r.vsync),
		alphaMode   = .Opaque,
	}
	configure_surface()

	// Create shader module
	r.shader_module = wgpu.DeviceCreateShaderModule(
		r.device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = #load("shader.wgsl"),
			},
		},
	)

	// Create sampler
	r.sampler = wgpu.DeviceCreateSampler(
		r.device,
		&{
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			lodMinClamp = 0,
			lodMaxClamp = 32,
			compare = .Undefined,
			maxAnisotropy = 1,
		},
	)

	// Create projection uniform buffer (multi-slot for mid-frame camera changes)
	r.projection_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Projection Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = PROJECTION_SLOT_STRIDE * MAX_PROJECTION_SLOTS,
		},
	)

	// Create the first vertex buffer (GPU side); more are added on demand.
	append(&r.vertex_buffers, create_vertex_buffer())

	// Create static index buffer — pattern repeats for every quad: 0,1,2, 0,2,3, 4,5,6, 4,6,7, ...
	{
		indices: [BATCH_MAX_INDICES]u16
		for i in 0 ..< BATCH_MAX_QUADS {
			base := u16(i * 4)
			off := i * 6
			indices[off + 0] = base + 0
			indices[off + 1] = base + 1
			indices[off + 2] = base + 2
			indices[off + 3] = base + 0
			indices[off + 4] = base + 2
			indices[off + 5] = base + 3
		}
		r.index_buffer = wgpu.DeviceCreateBuffer(
			r.device,
			&{label = "Index Buffer", usage = {.Index, .CopyDst}, size = size_of(indices)},
		)
		wgpu.QueueWriteBuffer(r.queue, r.index_buffer, 0, &indices, size_of(indices))
	}

	// Create bind group layout:
	//   binding 0: projection matrix (uniform)
	//   binding 1: sampler
	//   binding 2: texture
	r.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		r.device,
		&{
			entryCount = 3,
			entries = raw_data(
				[]wgpu.BindGroupLayoutEntry {
					{
						binding = 0,
						visibility = {.Vertex},
						buffer = {type = .Uniform, minBindingSize = size_of(matrix[4, 4]f32)},
					},
					{binding = 1, visibility = {.Fragment}, sampler = {type = .Filtering}},
					{
						binding = 2,
						visibility = {.Fragment},
						texture = {
							sampleType = .Float,
							viewDimension = ._2D,
							multisampled = false,
						},
					},
				},
			),
		},
	)

	// Create pipeline layout
	r.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		r.device,
		&{bindGroupLayoutCount = 1, bindGroupLayouts = &r.bind_group_layout},
	)

	// Create a render pipeline for each blend mode
	for mode in core.Blend_Mode {
		r.pipelines[mode] = create_render_pipeline(
			r.device,
			r.pipeline_layout,
			r.shader_module,
			"vs_main",
			"fs_main",
			mode,
		)
	}

	// Create the 1x1 white texture for solid color drawing
	white_pixels := [4]u8{255, 255, 255, 255}
	r.white_texture = renderer_create_texture(white_pixels[:], 1, 1)

	// Upload initial projection
	renderer_update_projection()

	r.initialized = true

	// Signal that the GPU is ready — the engine uses this to fire the user's init callback.
	if r.on_initialized != nil {
		r.on_initialized()
	}
}

@(private = "package")
create_vertex_buffer :: proc() -> wgpu.Buffer {
	return wgpu.DeviceCreateBuffer(
		renderer.device,
		&{
			label = "Vertex Buffer",
			usage = {.Vertex, .CopyDst},
			size = GPU_BUFFER_VERTICES * VERTEX_SIZE,
		},
	)
}

//----------//
// RESIZE   //
//----------//

@(private = "file")
renderer_update_projection :: proc() {
	r := &renderer
	// Use logical (window) size for projection so coordinates match mouse input
	// and stay DPI-independent. The surface/framebuffer uses physical pixels.
	lw, lh := r.window.get_window_size()
	projection := linalg.matrix_ortho3d_f32(0, f32(lw), f32(lh), 0, -1, 1)
	// Slot 0 is reserved for this base projection; begin_frame starts the
	// per-frame slots at 1. Called at init and on resize. A resize can land
	// mid-frame, so only reset the slot state between frames — slots already
	// written this frame are still referenced by recorded draws.
	r.base_projection = projection
	wgpu.QueueWriteBuffer(r.queue, r.projection_buffer, 0, &projection, size_of(projection))
	if !r.frame.active {
		r.projection_offset = 0
		r.projection_slot = 1
	}
}

@(private = "package")
renderer_resize :: proc() {
	r := &renderer
	if !r.initialized {
		return
	}

	r.width, r.height = r.window.get_framebuffer_size()
	if r.width == 0 || r.height == 0 {
		return
	}

	r.config.width = r.width
	r.config.height = r.height
	configure_surface()
	renderer_update_projection()
}

@(private = "file")
renderer_is_initialized :: proc() -> bool {
	return renderer.initialized
}

// Enable or disable vsync. Off picks the first non-blocking present mode
// the surface offers (Immediate, then Mailbox); when neither is offered
// (web surfaces only do Fifo) the request has no effect. Applied by the
// next begin_frame, so it is safe to call at any time, including before
// the device is ready.
@(private = "package")
renderer_set_vsync :: proc(enabled: bool) {
	renderer.vsync = enabled
}

// Reconfigure the surface if the requested vsync state changed.
@(private = "package")
apply_present_mode :: proc() {
	r := &renderer
	mode := present_mode_for(r.vsync)
	if mode != r.config.presentMode {
		r.config.presentMode = mode
		configure_surface()
	}
}

// Apply r.config to the surface. Headless (nil surface) there is nothing to
// configure; r.config still describes the offscreen target's size and format.
@(private = "file")
configure_surface :: proc() {
	r := &renderer
	if r.surface != nil {
		wgpu.SurfaceConfigure(r.surface, &r.config)
	}
}

@(private = "file")
present_mode_for :: proc(vsync: bool) -> wgpu.PresentMode {
	r := &renderer
	if vsync {
		return .Fifo
	}
	for want in ([]wgpu.PresentMode{.Immediate, .Mailbox}) {
		for i in 0 ..< r.present_mode_count {
			if r.present_modes[i] == want {
				return want
			}
		}
	}
	return .Fifo
}

//----------//
// SHUTDOWN //
//----------//

@(private = "file")
renderer_shutdown :: proc() {
	r := &renderer
	if !r.initialized {
		return
	}

	// Destroy the white texture through the handle system.
	renderer_destroy_texture(r.white_texture)

	// Destroy any remaining textures.
	for handle in r.textures {
		entry := &r.textures[handle]
		if entry.view != nil {
			wgpu.TextureViewRelease(entry.view)
		}
		if entry.handle != nil {
			wgpu.TextureRelease(entry.handle)
		}
	}
	delete(r.textures)

	// Destroy any remaining shaders.
	shader_it := hm.iterator_make(&r.shaders)
	for _, handle in hm.iterate(&shader_it) {
		renderer_destroy_shader(handle)
	}
	hm.dynamic_destroy(&r.shaders)

	offscreen_destroy()
	for buffer in r.vertex_buffers {
		wgpu.BufferRelease(buffer)
	}
	delete(r.vertex_buffers)
	if r.index_buffer != nil {wgpu.BufferRelease(r.index_buffer)}
	if r.projection_buffer != nil {wgpu.BufferRelease(r.projection_buffer)}
	if r.sampler != nil {wgpu.SamplerRelease(r.sampler)}
	if r.batch.bind_group != nil {wgpu.BindGroupRelease(r.batch.bind_group)}
	delete(r.frame.bind_group_cache)
	for buffer in r.frame.released_buffers {
		wgpu.BufferRelease(buffer)
	}
	delete(r.frame.released_buffers)
	if r.bind_group_layout != nil {wgpu.BindGroupLayoutRelease(r.bind_group_layout)}
	for pipeline in r.pipelines {
		if pipeline != nil {wgpu.RenderPipelineRelease(pipeline)}
	}
	if r.pipeline_layout != nil {wgpu.PipelineLayoutRelease(r.pipeline_layout)}
	if r.shader_module != nil {wgpu.ShaderModuleRelease(r.shader_module)}
	if r.queue != nil {wgpu.QueueRelease(r.queue)}
	if r.device != nil {wgpu.DeviceRelease(r.device)}
	if r.adapter != nil {wgpu.AdapterRelease(r.adapter)}
	if r.surface != nil {wgpu.SurfaceRelease(r.surface)}
	if r.instance != nil {wgpu.InstanceRelease(r.instance)}

	r.initialized = false
}

//-------//
// STATS //
//-------//

@(private = "file")
renderer_get_stats :: proc(frame_time: f32) -> core.Stats {
	s := renderer.last_stats
	return core.Stats {
		frame_time_ms = frame_time * 1000.0,
		fps = frame_time > 0 ? 1.0 / frame_time : 0,
		draw_calls = s.draw_calls,
		quads = s.quads,
		vertices = s.vertices,
		texture_switches = s.texture_switches,
		textures_alive = s.textures_alive,
		texture_memory = s.texture_memory,
	}
}

//----------------------//
// GPU HANDLE ACCESSORS //
//----------------------//

@(private = "file")
renderer_get_gpu_device :: proc() -> rawptr {
	return renderer.device
}

@(private = "file")
renderer_get_gpu_queue :: proc() -> rawptr {
	return renderer.queue
}

@(private = "file")
renderer_get_surface_format :: proc() -> u32 {
	return u32(renderer.config.format)
}

@(private = "file")
renderer_set_view_projection :: proc(m: matrix[4, 4]f32) {
	r := &renderer
	if !r.initialized {
		return
	}
	// The base window projection (e.g. set_camera(nil) on the screen) is
	// already in slot 0; reuse it rather than spending a slot.
	if m == r.base_projection {
		if r.projection_offset != 0 {
			r.projection_offset = 0
			r.batch.texture_view = nil
		}
		return
	}
	assert(
		r.projection_slot < MAX_PROJECTION_SLOTS,
		"Too many camera changes in one frame (MAX_PROJECTION_SLOTS). Use push_transform for per-object transforms.",
	)
	offset := u64(r.projection_slot) * PROJECTION_SLOT_STRIDE
	m := m
	wgpu.QueueWriteBuffer(r.queue, r.projection_buffer, offset, &m, size_of(m))
	r.projection_offset = offset
	r.projection_slot += 1
	// Invalidate the current bind group so the next draw call creates a new one
	// referencing the updated projection offset.
	r.batch.texture_view = nil
}

@(private = "file")
renderer_set_scissor_rect :: proc(rect: Maybe(core.Rect)) {
	r := &renderer
	if !r.frame.active {
		return
	}

	if r.scissor_rect == rect {
		return
	}

	renderer_flush()
	r.scissor_rect = rect
	apply_scissor_rect()
}

// Apply the current scissor state to the render pass. Converts logical
// pixels to the current target's pixels — the window's DPI scale for the
// screen, 1:1 for a render texture — and intersects with its bounds. A rect
// with nothing left (off the target, or zero/negative size) can't be given
// to wgpu, so it sets scissor_empty and the pass's scissor is left as is.
@(private = "package")
apply_scissor_rect :: proc() {
	r := &renderer
	if !r.frame.active {
		return
	}

	tw, th := r.frame.target_w, r.frame.target_h
	r.scissor_empty = false
	sr, ok := r.scissor_rect.?
	if !ok {
		wgpu.RenderPassEncoderSetScissorRect(r.frame.pass, 0, 0, tw, th)
		return
	}

	scale_x, scale_y: f32 = 1, 1
	if r.frame.target == nil {
		lw, lh := r.window.get_window_size()
		if lw > 0 && lh > 0 {
			scale_x = f32(tw) / f32(lw)
			scale_y = f32(th) / f32(lh)
		}
	}

	// Clamp the edges in float space, so negative or huge values can't
	// wrap when converted to u32.
	x0 := clamp(math.round(sr.x * scale_x), 0, f32(tw))
	y0 := clamp(math.round(sr.y * scale_y), 0, f32(th))
	x1 := clamp(math.round((sr.x + sr.w) * scale_x), 0, f32(tw))
	y1 := clamp(math.round((sr.y + sr.h) * scale_y), 0, f32(th))
	if !(x1 > x0 && y1 > y0) {
		r.scissor_empty = true
		return
	}

	wgpu.RenderPassEncoderSetScissorRect(
		r.frame.pass,
		u32(x0),
		u32(y0),
		u32(x1) - u32(x0),
		u32(y1) - u32(y0),
	)
}

@(private = "file")
renderer_set_pre_present_callback :: proc(callback: proc(pass: rawptr, width, height: u32)) {
	renderer.pre_present_callback = callback
}

//-----------//
// UTILITIES //
//-----------//

// Blend state for each engine blend mode.
@(private = "file")
blend_state :: proc(mode: core.Blend_Mode) -> wgpu.BlendState {
	component :: proc(src, dst: wgpu.BlendFactor) -> wgpu.BlendComponent {
		return {srcFactor = src, dstFactor = dst, operation = .Add}
	}
	// Source colour is premultiplied by alpha (see core.Blend_Mode), so no
	// mode multiplies by SrcAlpha again.
	switch mode {
	case .Alpha:
		// src + dst*(1-a) for colour and alpha alike: destination alpha
		// accumulates coverage, so a render texture composites correctly.
		return {
			color = component(.One, .OneMinusSrcAlpha),
			alpha = component(.One, .OneMinusSrcAlpha),
		}
	case .Additive:
		// Adds light without adding coverage: drawn into a transparent render
		// texture it still adds (rather than occludes) when composited.
		return {color = component(.One, .One), alpha = component(.Zero, .One)}
	case .Multiply:
		// dst * lerp(1, src_straight, a); destination alpha unchanged.
		return {color = component(.Dst, .OneMinusSrcAlpha), alpha = component(.Zero, .One)}
	}
	return {}
}

// Create a render pipeline with the standard vertex layout and the color
// target blended according to mode. Used for both the default pipelines and
// custom shader pipelines.
@(private = "package")
create_render_pipeline :: proc(
	device: wgpu.Device,
	layout: wgpu.PipelineLayout,
	module: wgpu.ShaderModule,
	vertex_entry: string,
	fragment_entry: string,
	mode: core.Blend_Mode,
) -> wgpu.RenderPipeline {
	blend := blend_state(mode)
	return wgpu.DeviceCreateRenderPipeline(
		device,
		&{
			layout = layout,
			vertex = {
				module      = module,
				entryPoint  = vertex_entry,
				bufferCount = 1,
				buffers     = &wgpu.VertexBufferLayout {
					arrayStride    = VERTEX_SIZE,
					stepMode       = .Vertex,
					attributeCount = 3,
					attributes     = raw_data(
						[]wgpu.VertexAttribute {
							// position: vec2<f32>
							{format = .Float32x2, offset = 0, shaderLocation = 0},
							// texcoord: vec2<f32>
							{format = .Float32x2, offset = 2 * size_of(f32), shaderLocation = 1},
							// color: vec4<f32>
							{format = .Float32x4, offset = 4 * size_of(f32), shaderLocation = 2},
						},
					),
				},
			},
			fragment = &{
				module = module,
				entryPoint = fragment_entry,
				targetCount = 1,
				targets = &wgpu.ColorTargetState {
					format = .BGRA8Unorm,
					blend = &blend,
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
			},
			primitive = {topology = .TriangleList, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFFFFFF},
		},
	)
}
