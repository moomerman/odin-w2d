package renderer_wgpu

import "base:runtime"
import hm "core:container/handle_map"
import "core:fmt"
import "core:math/linalg"
import "core:strings"
import "vendor:wgpu"

import core "../../core"

// Maximum number of quads per batch before flushing.
@(private = "file")
BATCH_MAX_QUADS :: 4096
@(private = "file")
BATCH_MAX_VERTICES :: BATCH_MAX_QUADS * 4
@(private = "file")
BATCH_MAX_INDICES :: BATCH_MAX_QUADS * 6

// Vertex layout: position (2 floats) + texcoord (2 floats) + color (4 floats) = 8 floats = 32 bytes
@(private = "file")
VERTEX_FLOATS :: 8
@(private = "file")
VERTEX_SIZE :: VERTEX_FLOATS * size_of(f32)

@(private = "file")
MAX_BIND_GROUPS_PER_FRAME :: 256

@(private = "file")
Renderer_Stats :: struct {
	draw_calls:       int,
	quads:            int,
	vertices:         int,
	texture_switches: int,
	textures_alive:   int,
	texture_memory:   int, // estimated bytes (w * h * 4)
}

// Internal GPU resource pair for a texture.
@(private = "file")
Texture_Entry :: struct {
	handle: wgpu.Texture,
	view:   wgpu.TextureView,
	width:  int,
	height: int,
}

// WGSL type tag for uniform metadata.
@(private = "file")
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
@(private = "file")
Shader_Uniform :: struct {
	offset: int,
	size:   int,
	type:   Shader_Uniform_Type,
}

// Internal GPU resources and metadata for a custom shader.
@(private = "file")
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

@(private = "file")
Renderer :: struct {
	ctx:                    runtime.Context,

	// Reference to the window backend for framebuffer queries.
	window:                 ^core.Window_Backend,

	// Callback invoked once the GPU device is ready.
	on_initialized:         proc(),

	// Core wgpu objects
	instance:               wgpu.Instance,
	surface:                wgpu.Surface,
	adapter:                wgpu.Adapter,
	device:                 wgpu.Device,
	queue:                  wgpu.Queue,
	config:                 wgpu.SurfaceConfiguration,

	// Pipeline
	shader_module:          wgpu.ShaderModule,
	pipeline_layout:        wgpu.PipelineLayout,
	pipeline:               wgpu.RenderPipeline,

	// Bind group for projection + sampler + texture
	bind_group_layout:      wgpu.BindGroupLayout,

	// Projection uniform buffer
	projection_buffer:      wgpu.Buffer,

	// Sampler
	sampler:                wgpu.Sampler,

	// Vertex buffer (GPU side)
	vertex_buffer:          wgpu.Buffer,

	// Index buffer (GPU side, static — generated once at init)
	index_buffer:           wgpu.Buffer,

	// CPU-side vertex data for batching
	vertices:               [BATCH_MAX_VERTICES * VERTEX_FLOATS]f32,
	vertex_count:           int,
	vertex_buffer_offset:   int, // running offset into GPU vertex buffer across flushes

	// White 1x1 texture used for solid color drawing
	white_texture:          core.Texture_Handle,

	// Currently bound texture view for batching
	current_texture_view:   wgpu.TextureView,

	// Current frame state
	current_bind_group:     wgpu.BindGroup,
	current_encoder:        wgpu.CommandEncoder,
	current_pass:           wgpu.RenderPassEncoder,
	current_surface_tex:    wgpu.SurfaceTexture,
	current_view:           wgpu.TextureView,
	frame_active:           bool,

	// Bind groups created this frame — released after submit, not mid-pass.
	frame_bind_groups:      [MAX_BIND_GROUPS_PER_FRAME]wgpu.BindGroup,
	frame_bind_group_count: int,

	// Dimensions
	width:                  u32,
	height:                 u32,

	// Initialization state
	initialized:            bool,

	// Texture handle map
	textures:               map[core.Texture_Handle]Texture_Entry,
	next_handle_id:         u64,

	// Shader handle map
	shaders:                hm.Dynamic_Handle_Map(Shader_Entry, core.Shader_Handle),

	// Stats for the current frame being built, and the last completed frame.
	current_stats:          Renderer_Stats,
	last_stats:             Renderer_Stats,

	// Active custom shader (zero-value = default pipeline).
	active_shader:          core.Shader_Handle,
}

@(private = "file")
renderer: Renderer

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
	}
}

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

	// Create projection uniform buffer
	r.projection_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Projection Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = size_of(matrix[4, 4]f32),
		},
	)

	// Create vertex buffer (GPU side)
	r.vertex_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{label = "Vertex Buffer", usage = {.Vertex, .CopyDst}, size = size_of(r.vertices)},
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
	r.pipeline = wgpu.DeviceCreateRenderPipeline(
		r.device,
		&{
			layout = r.pipeline_layout,
			vertex = {
				module      = r.shader_module,
				entryPoint  = "vs_main",
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
				module = r.shader_module,
				entryPoint = "fs_main",
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

@(private = "file")
renderer_update_projection :: proc() {
	r := &renderer
	projection := linalg.matrix_ortho3d_f32(0, f32(r.width), f32(r.height), 0, -1, 1)
	wgpu.QueueWriteBuffer(r.queue, r.projection_buffer, 0, &projection, size_of(projection))
}

@(private = "file")
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

// Begin a new frame, clearing the screen with the given color.
@(private = "file")
renderer_begin_frame :: proc(color: core.Color) -> bool {
	r := &renderer
	if !r.initialized {
		return false
	}

	r.vertex_count = 0
	r.vertex_buffer_offset = 0
	r.current_texture_view = nil
	r.current_bind_group = nil
	r.frame_bind_group_count = 0
	r.active_shader = {}

	// Reset per-frame stats, carrying over resource counts.
	r.current_stats = {
		textures_alive = r.current_stats.textures_alive,
		texture_memory = r.current_stats.texture_memory,
	}

	r.current_surface_tex = wgpu.SurfaceGetCurrentTexture(r.surface)
	switch r.current_surface_tex.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// All good.
	case .Timeout, .Outdated, .Lost:
		if r.current_surface_tex.texture != nil {
			wgpu.TextureRelease(r.current_surface_tex.texture)
		}
		renderer_resize()
		return false
	case .OutOfMemory, .DeviceLost, .Error:
		fmt.panicf("[renderer/wgpu] get_current_texture status=%v", r.current_surface_tex.status)
	}

	r.current_view = wgpu.TextureCreateView(r.current_surface_tex.texture, nil)
	r.current_encoder = wgpu.DeviceCreateCommandEncoder(r.device, nil)

	cf := color_to_f64(color)

	r.current_pass = wgpu.CommandEncoderBeginRenderPass(
		r.current_encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = r.current_view,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {cf[0], cf[1], cf[2], cf[3]},
			},
		},
	)

	r.frame_active = true
	return true
}

// Flush all batched vertices to the GPU and draw them.
@(private = "file")
renderer_flush :: proc() {
	r := &renderer
	if r.vertex_count == 0 || !r.frame_active {
		return
	}

	// Upload vertex data at the current offset into the GPU buffer.
	data_size := uint(r.vertex_count * VERTEX_FLOATS * size_of(f32))
	gpu_offset := uint(r.vertex_buffer_offset * VERTEX_FLOATS * size_of(f32))
	wgpu.QueueWriteBuffer(r.queue, r.vertex_buffer, u64(gpu_offset), &r.vertices, data_size)

	// Use the custom shader pipeline if active, otherwise the default.
	if entry, ok := hm.get(&r.shaders, r.active_shader); ok {
		// Upload dirty uniforms
		if entry.uniform_dirty && entry.uniform_buffer != nil {
			wgpu.QueueWriteBuffer(
				r.queue,
				entry.uniform_buffer,
				0,
				raw_data(entry.uniform_data),
				uint(entry.uniform_size),
			)
			entry.uniform_dirty = false
		}

		wgpu.RenderPassEncoderSetPipeline(r.current_pass, entry.pipeline)
		if r.current_bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.current_pass, 0, r.current_bind_group)
		}
		if entry.bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.current_pass, 1, entry.bind_group)
		}
	} else {
		wgpu.RenderPassEncoderSetPipeline(r.current_pass, r.pipeline)
		if r.current_bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.current_pass, 0, r.current_bind_group)
		}
	}

	wgpu.RenderPassEncoderSetVertexBuffer(
		r.current_pass,
		0,
		r.vertex_buffer,
		u64(gpu_offset),
		u64(data_size),
	)

	// Bind the static index buffer and draw indexed.
	// Each quad uses 4 vertices but 6 indices (two triangles).
	// The vertex buffer binding already offsets to the start of this batch,
	// so indices always start from 0.
	quad_count := r.vertex_count / 4
	index_count := u32(quad_count * 6)
	wgpu.RenderPassEncoderSetIndexBuffer(
		r.current_pass,
		r.index_buffer,
		.Uint16,
		0,
		u64(BATCH_MAX_INDICES * size_of(u16)),
	)
	wgpu.RenderPassEncoderDrawIndexed(r.current_pass, index_count, 1, 0, 0, 0)

	r.current_stats.draw_calls += 1
	r.current_stats.vertices += r.vertex_count
	r.current_stats.quads += quad_count

	r.vertex_buffer_offset += r.vertex_count
	r.vertex_count = 0
}

// End the current frame: flush, end render pass, submit, present.
@(private = "file")
renderer_present :: proc() {
	r := &renderer
	if !r.frame_active {
		return
	}

	renderer_flush()

	wgpu.RenderPassEncoderEnd(r.current_pass)
	wgpu.RenderPassEncoderRelease(r.current_pass)

	command_buffer := wgpu.CommandEncoderFinish(r.current_encoder, nil)
	wgpu.QueueSubmit(r.queue, {command_buffer})

	wgpu.CommandBufferRelease(command_buffer)
	wgpu.CommandEncoderRelease(r.current_encoder)

	wgpu.SurfacePresent(r.surface)
	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		wgpu.DevicePoll(r.device, false, nil)
	}

	wgpu.TextureViewRelease(r.current_view)
	wgpu.TextureRelease(r.current_surface_tex.texture)

	// Release all bind groups created this frame now that the GPU is done with them.
	for i in 0 ..< r.frame_bind_group_count {
		wgpu.BindGroupRelease(r.frame_bind_groups[i])
	}
	r.frame_bind_group_count = 0
	r.current_bind_group = nil

	// Snapshot stats for the completed frame.
	r.last_stats = r.current_stats

	r.frame_active = false
}

// Push a textured quad into the batch.
@(private = "file")
renderer_push_quad :: proc(
	dst: core.Rect,
	src_uv: [4][2]f32,
	tex_handle: core.Texture_Handle,
	color: core.Color,
) {
	r := &renderer
	if !r.frame_active {
		return
	}

	entry, ok := &r.textures[tex_handle]
	if !ok {
		return
	}

	// If the texture changed, flush the current batch and rebind.
	if r.current_texture_view != entry.view {
		renderer_flush()
		r.current_texture_view = entry.view
		renderer_bind_texture(entry.view)
		r.current_stats.texture_switches += 1
	}

	// If the batch is full, flush.
	if r.vertex_count + 4 > BATCH_MAX_VERTICES {
		renderer_flush()
	}

	cr, cg, cb, ca :=
		f32(color[0]) / 255.0, f32(color[1]) / 255.0, f32(color[2]) / 255.0, f32(color[3]) / 255.0

	x := dst.x
	y := dst.y
	w := dst.w
	h := dst.h

	// Four unique vertices per quad; the index buffer provides triangle connectivity.
	push_vertex(r, x, y, src_uv[0][0], src_uv[0][1], cr, cg, cb, ca)         // 0: top-left
	push_vertex(r, x + w, y, src_uv[1][0], src_uv[1][1], cr, cg, cb, ca)     // 1: top-right
	push_vertex(r, x + w, y + h, src_uv[2][0], src_uv[2][1], cr, cg, cb, ca) // 2: bottom-right
	push_vertex(r, x, y + h, src_uv[3][0], src_uv[3][1], cr, cg, cb, ca)     // 3: bottom-left
}

// Push a quad with explicit vertex positions (for rotated/arbitrary quads).
@(private = "file")
renderer_push_quad_ex :: proc(
	positions: [4]core.Vec2,
	src_uv: [4][2]f32,
	tex_handle: core.Texture_Handle,
	color: core.Color,
) {
	r := &renderer
	if !r.frame_active {
		return
	}

	entry, ok := &r.textures[tex_handle]
	if !ok {
		return
	}

	if r.current_texture_view != entry.view {
		renderer_flush()
		r.current_texture_view = entry.view
		renderer_bind_texture(entry.view)
		r.current_stats.texture_switches += 1
	}

	if r.vertex_count + 4 > BATCH_MAX_VERTICES {
		renderer_flush()
	}

	cr, cg, cb, ca :=
		f32(color[0]) / 255.0, f32(color[1]) / 255.0, f32(color[2]) / 255.0, f32(color[3]) / 255.0

	// Four unique vertices per quad; the index buffer provides triangle connectivity.
	push_vertex(r, positions[0].x, positions[0].y, src_uv[0][0], src_uv[0][1], cr, cg, cb, ca)
	push_vertex(r, positions[1].x, positions[1].y, src_uv[1][0], src_uv[1][1], cr, cg, cb, ca)
	push_vertex(r, positions[2].x, positions[2].y, src_uv[2][0], src_uv[2][1], cr, cg, cb, ca)
	push_vertex(r, positions[3].x, positions[3].y, src_uv[3][0], src_uv[3][1], cr, cg, cb, ca)
}

@(private = "file")
push_vertex :: proc(r: ^Renderer, px, py, u, v, cr, cg, cb, ca: f32) {
	base := r.vertex_count * VERTEX_FLOATS
	r.vertices[base + 0] = px
	r.vertices[base + 1] = py
	r.vertices[base + 2] = u
	r.vertices[base + 3] = v
	r.vertices[base + 4] = cr
	r.vertices[base + 5] = cg
	r.vertices[base + 6] = cb
	r.vertices[base + 7] = ca
	r.vertex_count += 1
}

@(private = "file")
renderer_bind_texture :: proc(tex_view: wgpu.TextureView) {
	r := &renderer

	r.current_bind_group = wgpu.DeviceCreateBindGroup(
		r.device,
		&{
			layout = r.bind_group_layout,
			entryCount = 3,
			entries = raw_data(
				[]wgpu.BindGroupEntry {
					{binding = 0, buffer = r.projection_buffer, size = size_of(matrix[4, 4]f32)},
					{binding = 1, sampler = r.sampler},
					{binding = 2, textureView = tex_view},
				},
			),
		},
	)

	// Track for deferred release after frame submit.
	assert(
		r.frame_bind_group_count < MAX_BIND_GROUPS_PER_FRAME,
		"Too many texture switches in one frame",
	)
	r.frame_bind_groups[r.frame_bind_group_count] = r.current_bind_group
	r.frame_bind_group_count += 1
}

// Allocate a new texture handle.
@(private = "file")
alloc_handle :: proc() -> core.Texture_Handle {
	handle := core.Texture_Handle(renderer.next_handle_id)
	renderer.next_handle_id += 1
	return handle
}

// Create a texture from raw RGBA pixel data.
@(private = "file")
renderer_create_texture :: proc(data: []u8, width, height: int) -> core.Texture_Handle {
	r := &renderer

	tex := wgpu.DeviceCreateTexture(
		r.device,
		&{
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {u32(width), u32(height), 1},
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)

	tex_view := wgpu.TextureCreateView(tex, nil)

	// Upload pixel data
	wgpu.QueueWriteTexture(
		r.queue,
		&{texture = tex},
		raw_data(data),
		uint(len(data)),
		&{bytesPerRow = u32(width) * 4, rowsPerImage = u32(height)},
		&{u32(width), u32(height), 1},
	)

	r.current_stats.textures_alive += 1
	r.current_stats.texture_memory += width * height * 4

	handle := alloc_handle()
	r.textures[handle] = Texture_Entry {
		handle = tex,
		view   = tex_view,
		width  = width,
		height = height,
	}

	return handle
}

// Create an empty texture (no initial pixel data). Used for atlases filled on demand.
@(private = "file")
renderer_create_texture_empty :: proc(width, height: int) -> core.Texture_Handle {
	r := &renderer

	tex := wgpu.DeviceCreateTexture(
		r.device,
		&{
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {u32(width), u32(height), 1},
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)

	tex_view := wgpu.TextureCreateView(tex, nil)

	r.current_stats.textures_alive += 1
	r.current_stats.texture_memory += width * height * 4

	handle := alloc_handle()
	r.textures[handle] = Texture_Entry {
		handle = tex,
		view   = tex_view,
		width  = width,
		height = height,
	}

	return handle
}

// Update a sub-region of an existing texture with new RGBA8 pixel data.
@(private = "file")
renderer_update_texture :: proc(
	handle: core.Texture_Handle,
	data: []u8,
	x, y, width, height: int,
) {
	r := &renderer

	entry, ok := &r.textures[handle]
	if !ok {
		return
	}

	wgpu.QueueWriteTexture(
		r.queue,
		&{texture = entry.handle, origin = {u32(x), u32(y), 0}},
		raw_data(data),
		uint(len(data)),
		&{bytesPerRow = u32(width) * 4, rowsPerImage = u32(height)},
		&{u32(width), u32(height), 1},
	)
}

@(private = "file")
renderer_destroy_texture :: proc(handle: core.Texture_Handle) {
	r := &renderer

	entry, ok := &r.textures[handle]
	if !ok {
		return
	}

	r.current_stats.textures_alive -= 1
	r.current_stats.texture_memory -= entry.width * entry.height * 4

	if entry.view != nil {
		wgpu.TextureViewRelease(entry.view)
	}
	if entry.handle != nil {
		wgpu.TextureRelease(entry.handle)
	}

	delete_key(&r.textures, handle)
}

@(private = "file")
renderer_get_white_texture :: proc() -> core.Texture_Handle {
	return renderer.white_texture
}

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
	for entry, handle in hm.iterate(&shader_it) {
		renderer_destroy_shader(handle)
	}
	hm.dynamic_destroy(&r.shaders)

	if r.vertex_buffer != nil {wgpu.BufferRelease(r.vertex_buffer)}
	if r.index_buffer != nil {wgpu.BufferRelease(r.index_buffer)}
	if r.projection_buffer != nil {wgpu.BufferRelease(r.projection_buffer)}
	if r.sampler != nil {wgpu.SamplerRelease(r.sampler)}
	if r.current_bind_group != nil {wgpu.BindGroupRelease(r.current_bind_group)}
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

// --- Custom Shader API ---

@(private = "file")
renderer_load_shader :: proc(wgsl_source: string) -> core.Shader_Handle {
	r := &renderer
	entry: Shader_Entry

	// Parse WGSL to extract metadata
	parse := parse_wgsl(wgsl_source)
	defer destroy_parse_result(&parse)

	// Create shader module
	entry.module = wgpu.DeviceCreateShaderModule(
		r.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = wgsl_source}},
	)

	// Store entry points
	entry.vertex_entry = strings.clone(
		len(parse.vertex_entry) > 0 ? parse.vertex_entry : "vs_main",
	)
	entry.fragment_entry = strings.clone(
		len(parse.fragment_entry) > 0 ? parse.fragment_entry : "fs_main",
	)

	// Find group 1 uniform binding and compute layout
	uniform_struct_name: string
	for &b in parse.bindings {
		if b.group == 1 && b.type == "uniform" {
			uniform_struct_name = b.type_name
			break
		}
	}

	// Build uniform metadata from the struct
	if len(uniform_struct_name) > 0 {
		s := find_struct(&parse.structs, uniform_struct_name)
		if s != nil {
			entry.uniform_size = s.size
			entry.uniforms = make(map[string]Shader_Uniform)

			for &field in s.fields {
				uniform_type: Shader_Uniform_Type
				#partial switch field.type {
				case .F32:
					uniform_type = .F32
				case .I32:
					uniform_type = .I32
				case .U32:
					uniform_type = .U32
				case .Vec2F32:
					uniform_type = .Vec2F32
				case .Vec3F32:
					uniform_type = .Vec3F32
				case .Vec4F32:
					uniform_type = .Vec4F32
				case .Mat4x4F32:
					uniform_type = .Mat4x4F32
				}
				entry.uniforms[strings.clone(field.name)] = Shader_Uniform {
					offset = field.offset,
					size   = field.size,
					type   = uniform_type,
				}
			}
		}
	}

	// Create bind group layout for group 1 (user uniforms)
	if entry.uniform_size > 0 {
		entry.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
			r.device,
			&{
				entryCount = 1,
				entries = &wgpu.BindGroupLayoutEntry {
					binding = 0,
					visibility = {.Vertex, .Fragment},
					buffer = {type = .Uniform, minBindingSize = u64(entry.uniform_size)},
				},
			},
		)

		// Create uniform buffer
		// Round up to 16 bytes for WebGPU minimum buffer size
		buf_size := u64(align_up(entry.uniform_size, 16))
		entry.uniform_buffer = wgpu.DeviceCreateBuffer(
			r.device,
			&{
				label = "Custom Shader Uniform Buffer",
				usage = {.Uniform, .CopyDst},
				size = buf_size,
			},
		)

		// Create CPU staging buffer
		entry.uniform_data = make([]u8, entry.uniform_size)

		// Create bind group
		entry.bind_group = wgpu.DeviceCreateBindGroup(
			r.device,
			&{
				layout = entry.bind_group_layout,
				entryCount = 1,
				entries = &wgpu.BindGroupEntry {
					binding = 0,
					buffer = entry.uniform_buffer,
					size = u64(entry.uniform_size),
				},
			},
		)
	}

	// Create pipeline layout: [engine group 0, user group 1]
	if entry.bind_group_layout != nil {
		layouts := [2]wgpu.BindGroupLayout{r.bind_group_layout, entry.bind_group_layout}
		entry.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
			r.device,
			&{bindGroupLayoutCount = 2, bindGroupLayouts = &layouts[0]},
		)
	} else {
		// No user uniforms — still need a pipeline with just group 0
		entry.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
			r.device,
			&{bindGroupLayoutCount = 1, bindGroupLayouts = &r.bind_group_layout},
		)
	}

	// Create render pipeline (same vertex layout as default)
	entry.pipeline = wgpu.DeviceCreateRenderPipeline(
		r.device,
		&{
			layout = entry.pipeline_layout,
			vertex = {
				module = entry.module,
				entryPoint = entry.vertex_entry,
				bufferCount = 1,
				buffers = &wgpu.VertexBufferLayout {
					arrayStride = VERTEX_SIZE,
					stepMode = .Vertex,
					attributeCount = 3,
					attributes = raw_data(
						[]wgpu.VertexAttribute {
							{format = .Float32x2, offset = 0, shaderLocation = 0},
							{format = .Float32x2, offset = 2 * size_of(f32), shaderLocation = 1},
							{format = .Float32x4, offset = 4 * size_of(f32), shaderLocation = 2},
						},
					),
				},
			},
			fragment = &{
				module = entry.module,
				entryPoint = entry.fragment_entry,
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

	// Store in handle map and return the handle.
	handle, _ := hm.add(&r.shaders, entry)
	return handle
}

@(private = "file")
renderer_set_shader_uniform :: proc(handle: core.Shader_Handle, name: string, value: any) {
	entry, ok := hm.get(&renderer.shaders, handle)
	if !ok {
		fmt.eprintf("[shader] invalid shader handle\n")
		return
	}

	uniform: Shader_Uniform
	uniform, ok = entry.uniforms[name]
	if !ok {
		fmt.eprintf("[shader] unknown uniform: %s\n", name)
		return
	}

	dst := entry.uniform_data[uniform.offset:][:uniform.size]

	// Copy the value bytes into the staging buffer
	src_ptr := value.data
	src_size := 0

	#partial switch uniform.type {
	case .F32:
		src_size = 4
	case .I32:
		src_size = 4
	case .U32:
		src_size = 4
	case .Vec2F32:
		src_size = 8
	case .Vec3F32:
		src_size = 12
	case .Vec4F32:
		src_size = 16
	case .Mat4x4F32:
		src_size = 64
	}

	if src_size > 0 && src_size <= uniform.size {
		src_bytes := ([^]u8)(src_ptr)[:src_size]
		copy(dst, src_bytes)
	}

	entry.uniform_dirty = true
}

@(private = "file")
renderer_set_shader :: proc(handle: core.Shader_Handle) {
	r := &renderer
	if r.active_shader != handle {
		renderer_flush()
		r.active_shader = handle
	}
}

@(private = "file")
renderer_reset_shader :: proc() {
	r := &renderer
	if hm.is_valid(&r.shaders, r.active_shader) {
		renderer_flush()
		r.active_shader = {}
	}
}

@(private = "file")
renderer_destroy_shader :: proc(handle: core.Shader_Handle) {
	entry, ok := hm.get(&renderer.shaders, handle)
	if !ok {return}

	if entry.bind_group != nil {wgpu.BindGroupRelease(entry.bind_group)}
	if entry.bind_group_layout != nil {wgpu.BindGroupLayoutRelease(entry.bind_group_layout)}
	if entry.uniform_buffer != nil {wgpu.BufferRelease(entry.uniform_buffer)}
	if entry.pipeline != nil {wgpu.RenderPipelineRelease(entry.pipeline)}
	if entry.pipeline_layout != nil {wgpu.PipelineLayoutRelease(entry.pipeline_layout)}
	if entry.module != nil {wgpu.ShaderModuleRelease(entry.module)}

	if entry.uniform_data != nil {
		delete(entry.uniform_data)
	}

	// Free uniform map keys
	for key in entry.uniforms {
		delete(key)
	}
	delete(entry.uniforms)

	delete(entry.vertex_entry)
	delete(entry.fragment_entry)

	hm.remove(&renderer.shaders, handle)
}

// Helper to convert Color ([4]u8) to [4]f64 for wgpu clear values.
@(private = "file")
color_to_f64 :: proc(c: core.Color) -> [4]f64 {
	return {f64(c[0]) / 255.0, f64(c[1]) / 255.0, f64(c[2]) / 255.0, f64(c[3]) / 255.0}
}
