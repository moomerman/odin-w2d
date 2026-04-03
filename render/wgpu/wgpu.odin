package renderer_wgpu

import "base:runtime"
import hm "core:container/handle_map"
import "core:fmt"
import "core:math/linalg"
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

// The GPU vertex buffer holds multiple batches so that each flush within a
// frame writes to a distinct region (wgpu stages all writes before execution,
// so reusing the same offset would corrupt earlier draw calls).
@(private = "package")
GPU_BUFFER_BATCHES :: 8

@(private = "package")
MAX_BIND_GROUPS_PER_FRAME :: 256

// The projection buffer holds multiple view-projection matrices so that
// mid-frame camera changes (e.g. world → UI) each get their own slot.
// Same principle as GPU_BUFFER_BATCHES for vertices.
// Each slot is aligned to 256 bytes (wgpu min_uniform_buffer_offset_alignment).
@(private = "package")
MAX_PROJECTION_SLOTS :: 32
@(private = "package")
PROJECTION_SLOT_STRIDE :: 256 // must be >= min_uniform_buffer_offset_alignment
@(private = "package")
PROJECTION_MATRIX_SIZE :: size_of(matrix[4, 4]f32)

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
	size:   int,
	type:   Shader_Uniform_Type,
}

// Internal GPU resources and metadata for a custom shader.
@(private = "package")
Shader_Entry :: struct {
	handle:            core.Shader_Handle,

	// WGPU resources
	module:            wgpu.ShaderModule,
	pipeline:          wgpu.RenderPipeline,
	pipeline_layout:   wgpu.PipelineLayout,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,

	// Uniform buffer
	uniform_buffer:    wgpu.Buffer,
	uniform_data:      []u8,
	uniform_dirty:     bool,
	uniform_size:      int,

	// Uniform metadata
	uniforms:          map[string]Shader_Uniform,

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

	// Bind groups created this frame — released after submit, not mid-pass.
	bind_groups:      [MAX_BIND_GROUPS_PER_FRAME]wgpu.BindGroup,
	bind_group_count: int,
}

// Vertex batching state within a frame.
@(private = "package")
Batch_State :: struct {
	vertices:      [BATCH_MAX_VERTICES * VERTEX_FLOATS]f32,
	vertex_count:  int,
	buffer_offset: int, // running offset into GPU vertex buffer across flushes
	texture_view:  wgpu.TextureView, // currently bound texture for batching
	bind_group:    wgpu.BindGroup, // current projection+sampler+texture bind group
	active_shader: core.Shader_Handle, // zero-value = default pipeline
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
	pipeline:             wgpu.RenderPipeline,

	// Bind group for projection + sampler + texture
	bind_group_layout:    wgpu.BindGroupLayout,

	// Projection uniform buffer (holds MAX_PROJECTION_SLOTS matrices)
	projection_buffer:    wgpu.Buffer,
	projection_offset:    u64, // byte offset of the current slot
	projection_slot:      int, // next slot to write to

	// Sampler
	sampler:              wgpu.Sampler,

	// Vertex buffer (GPU side)
	vertex_buffer:        wgpu.Buffer,

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
	batch:                Batch_State,

	// Active scissor rect in logical pixels, or nil for full viewport.
	scissor_rect:         Maybe(core.Rect),

	// Optional callback invoked after engine flush, before render pass ends.
	pre_present_callback: proc(pass: rawptr, width, height: u32),
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
		create_texture = renderer_create_texture,
		create_texture_empty = renderer_create_texture_empty,
		update_texture = renderer_update_texture,
		destroy_texture = renderer_destroy_texture,
		get_white_texture = renderer_get_white_texture,
		get_stats = renderer_get_stats,
		load_shader = renderer_load_shader,
		set_shader_uniform = renderer_set_shader_uniform,
		set_shader = renderer_set_shader,
		reset_shader = renderer_reset_shader,
		destroy_shader = renderer_destroy_shader,
		create_render_texture = renderer_create_render_texture,
		set_render_target = renderer_set_render_target,
		get_gpu_device = renderer_get_gpu_device,
		get_gpu_queue = renderer_get_gpu_queue,
		get_surface_format = renderer_get_surface_format,
		set_view_projection = renderer_set_view_projection,
		set_scissor_rect = renderer_set_scissor_rect,
		set_pre_present_callback = renderer_set_pre_present_callback,
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

	// Configure surface
	r.config = wgpu.SurfaceConfiguration {
		device      = r.device,
		usage       = {.RenderAttachment},
		format      = .BGRA8Unorm,
		width       = r.width,
		height      = r.height,
		presentMode = .Fifo,
		alphaMode   = .Opaque,
	}
	wgpu.SurfaceConfigure(r.surface, &r.config)

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

	// Create vertex buffer (GPU side)
	r.vertex_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Vertex Buffer",
			usage = {.Vertex, .CopyDst},
			size = size_of(r.batch.vertices) * GPU_BUFFER_BATCHES,
		},
	)

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

	// Create render pipeline
	r.pipeline = create_render_pipeline(
		r.device,
		r.pipeline_layout,
		r.shader_module,
		"vs_main",
		"fs_main",
	)

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
	// Write to slot 0 and reset the slot counter. Called at init and on resize.
	wgpu.QueueWriteBuffer(r.queue, r.projection_buffer, 0, &projection, size_of(projection))
	r.projection_offset = 0
	r.projection_slot = 1
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
	wgpu.SurfaceConfigure(r.surface, &r.config)
	renderer_update_projection()
}

@(private = "file")
renderer_is_initialized :: proc() -> bool {
	return renderer.initialized
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

	if r.vertex_buffer != nil {wgpu.BufferRelease(r.vertex_buffer)}
	if r.index_buffer != nil {wgpu.BufferRelease(r.index_buffer)}
	if r.projection_buffer != nil {wgpu.BufferRelease(r.projection_buffer)}
	if r.sampler != nil {wgpu.SamplerRelease(r.sampler)}
	if r.batch.bind_group != nil {wgpu.BindGroupRelease(r.batch.bind_group)}
	if r.bind_group_layout != nil {wgpu.BindGroupLayoutRelease(r.bind_group_layout)}
	if r.pipeline != nil {wgpu.RenderPipelineRelease(r.pipeline)}
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
	assert(r.projection_slot < MAX_PROJECTION_SLOTS, "Too many camera changes in one frame")
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

// Apply the current scissor state to the render pass.
// Converts logical pixels to physical pixels and clamps to framebuffer bounds.
@(private = "package")
apply_scissor_rect :: proc() {
	r := &renderer
	if !r.frame.active {
		return
	}

	if sr, ok := r.scissor_rect.?; ok {
		lw, lh := r.window.get_window_size()
		scale_x := f32(r.width) / f32(lw)
		scale_y := f32(r.height) / f32(lh)

		px := u32(sr.x * scale_x)
		py := u32(sr.y * scale_y)
		pw := u32(sr.w * scale_x)
		ph := u32(sr.h * scale_y)

		// Clamp to framebuffer bounds to avoid wgpu validation errors.
		if px + pw > r.width {pw = r.width - px}
		if py + ph > r.height {ph = r.height - py}

		wgpu.RenderPassEncoderSetScissorRect(r.frame.pass, px, py, pw, ph)
	} else {
		wgpu.RenderPassEncoderSetScissorRect(r.frame.pass, 0, 0, r.width, r.height)
	}
}

@(private = "file")
renderer_set_pre_present_callback :: proc(callback: proc(pass: rawptr, width, height: u32)) {
	renderer.pre_present_callback = callback
}

//-----------//
// UTILITIES //
//-----------//

// Create a render pipeline with the standard vertex layout and alpha-blended color target.
// Used for both the default pipeline and custom shader pipelines.
@(private = "package")
create_render_pipeline :: proc(
	device: wgpu.Device,
	layout: wgpu.PipelineLayout,
	module: wgpu.ShaderModule,
	vertex_entry: string,
	fragment_entry: string,
) -> wgpu.RenderPipeline {
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
					blend = &{
						alpha = {
							srcFactor = .SrcAlpha,
							dstFactor = .OneMinusSrcAlpha,
							operation = .Add,
						},
						color = {
							srcFactor = .SrcAlpha,
							dstFactor = .OneMinusSrcAlpha,
							operation = .Add,
						},
					},
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
			},
			primitive = {topology = .TriangleList, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFFFFFF},
		},
	)
}
