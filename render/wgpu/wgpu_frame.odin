package renderer_wgpu

import hm "core:container/handle_map"
import "core:fmt"
import "vendor:wgpu"

import core "../../core"

// Begin a new frame, clearing the screen with the given color.
@(private = "package")
renderer_begin_frame :: proc(color: core.Color) -> bool {
	r := &renderer
	if !r.initialized {
		return false
	}

	r.batch.vertex_count = 0
	r.batch.buffer_offset = 0
	r.batch.texture_view = nil
	r.batch.bind_group = nil
	r.frame.bind_group_count = 0
	r.batch.active_shader = {}
	r.projection_slot = 0
	r.projection_offset = 0

	// Reset per-frame stats, carrying over resource counts.
	r.current_stats = {
		textures_alive = r.current_stats.textures_alive,
		texture_memory = r.current_stats.texture_memory,
	}

	r.frame.surface_tex = wgpu.SurfaceGetCurrentTexture(r.surface)
	switch r.frame.surface_tex.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// All good.
	case .Timeout, .Outdated, .Lost:
		if r.frame.surface_tex.texture != nil {
			wgpu.TextureRelease(r.frame.surface_tex.texture)
		}
		renderer_resize()
		return false
	case .OutOfMemory, .DeviceLost, .Error:
		fmt.panicf("[renderer/wgpu] get_current_texture status=%v", r.frame.surface_tex.status)
	}

	r.frame.view = wgpu.TextureCreateView(r.frame.surface_tex.texture, nil)
	r.frame.encoder = wgpu.DeviceCreateCommandEncoder(r.device, nil)

	cf := color_to_f64(color)

	r.frame.pass = wgpu.CommandEncoderBeginRenderPass(
		r.frame.encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = r.frame.view,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {cf[0], cf[1], cf[2], cf[3]},
			},
		},
	)

	r.frame.active = true
	return true
}

// Flush all batched vertices to the GPU and draw them.
@(private = "package")
renderer_flush :: proc() {
	r := &renderer
	if r.batch.vertex_count == 0 || !r.frame.active {
		return
	}

	// Upload vertex data at the current offset into the GPU buffer.
	data_size := uint(r.batch.vertex_count * VERTEX_FLOATS * size_of(f32))
	gpu_offset := uint(r.batch.buffer_offset * VERTEX_FLOATS * size_of(f32))
	wgpu.QueueWriteBuffer(r.queue, r.vertex_buffer, u64(gpu_offset), &r.batch.vertices, data_size)

	// Use the custom shader pipeline if active, otherwise the default.
	if entry, ok := hm.get(&r.shaders, r.batch.active_shader); ok {
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

		wgpu.RenderPassEncoderSetPipeline(r.frame.pass, entry.pipeline)
		if r.batch.bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.frame.pass, 0, r.batch.bind_group)
		}
		if entry.bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.frame.pass, 1, entry.bind_group)
		}
	} else {
		wgpu.RenderPassEncoderSetPipeline(r.frame.pass, r.pipeline)
		if r.batch.bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.frame.pass, 0, r.batch.bind_group)
		}
	}

	wgpu.RenderPassEncoderSetVertexBuffer(
		r.frame.pass,
		0,
		r.vertex_buffer,
		u64(gpu_offset),
		u64(data_size),
	)

	// Bind the static index buffer and draw indexed.
	// Each quad uses 4 vertices but 6 indices (two triangles).
	// The vertex buffer binding already offsets to the start of this batch,
	// so indices always start from 0.
	quad_count := r.batch.vertex_count / 4
	index_count := u32(quad_count * 6)
	wgpu.RenderPassEncoderSetIndexBuffer(
		r.frame.pass,
		r.index_buffer,
		.Uint16,
		0,
		u64(BATCH_MAX_INDICES * size_of(u16)),
	)
	wgpu.RenderPassEncoderDrawIndexed(r.frame.pass, index_count, 1, 0, 0, 0)

	r.current_stats.draw_calls += 1
	r.current_stats.vertices += r.batch.vertex_count
	r.current_stats.quads += quad_count

	r.batch.buffer_offset += r.batch.vertex_count
	if r.batch.buffer_offset + BATCH_MAX_VERTICES > BATCH_MAX_VERTICES * GPU_BUFFER_BATCHES {
		r.batch.buffer_offset = 0
	}
	r.batch.vertex_count = 0
}

// End the current frame: flush, end render pass, submit, present.
@(private = "package")
renderer_present :: proc() {
	r := &renderer
	if !r.frame.active {
		return
	}

	renderer_flush()

	if r.pre_present_callback != nil {
		r.pre_present_callback(r.frame.pass, r.width, r.height)
	}

	wgpu.RenderPassEncoderEnd(r.frame.pass)
	wgpu.RenderPassEncoderRelease(r.frame.pass)

	command_buffer := wgpu.CommandEncoderFinish(r.frame.encoder, nil)
	wgpu.QueueSubmit(r.queue, {command_buffer})

	wgpu.CommandBufferRelease(command_buffer)
	wgpu.CommandEncoderRelease(r.frame.encoder)

	wgpu.SurfacePresent(r.surface)
	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		wgpu.DevicePoll(r.device, false, nil)
	}

	wgpu.TextureViewRelease(r.frame.view)
	wgpu.TextureRelease(r.frame.surface_tex.texture)

	// Release all bind groups created this frame now that the GPU is done with them.
	for i in 0 ..< r.frame.bind_group_count {
		wgpu.BindGroupRelease(r.frame.bind_groups[i])
	}
	r.frame.bind_group_count = 0
	r.batch.bind_group = nil

	// Snapshot stats for the completed frame.
	r.last_stats = r.current_stats

	r.frame.active = false
}

// Push a textured quad into the batch.
@(private = "package")
renderer_push_quad :: proc(
	dst: core.Rect,
	src_uv: [4][2]f32,
	tex_handle: core.Texture_Handle,
	color: core.Color,
) {
	r := prepare_quad(tex_handle)
	if r == nil {return}

	cr, cg, cb, ca := color_to_f32(color)
	x := dst.x
	y := dst.y
	w := dst.w
	h := dst.h

	// Four unique vertices per quad; the index buffer provides triangle connectivity.
	push_vertex(r, x, y, src_uv[0][0], src_uv[0][1], cr, cg, cb, ca) // 0: top-left
	push_vertex(r, x + w, y, src_uv[1][0], src_uv[1][1], cr, cg, cb, ca) // 1: top-right
	push_vertex(r, x + w, y + h, src_uv[2][0], src_uv[2][1], cr, cg, cb, ca) // 2: bottom-right
	push_vertex(r, x, y + h, src_uv[3][0], src_uv[3][1], cr, cg, cb, ca) // 3: bottom-left
}

// Push a quad with explicit vertex positions (for rotated/arbitrary quads).
@(private = "package")
renderer_push_quad_ex :: proc(
	positions: [4]core.Vec2,
	src_uv: [4][2]f32,
	tex_handle: core.Texture_Handle,
	color: core.Color,
) {
	r := prepare_quad(tex_handle)
	if r == nil {return}

	cr, cg, cb, ca := color_to_f32(color)

	// Four unique vertices per quad; the index buffer provides triangle connectivity.
	push_vertex(r, positions[0].x, positions[0].y, src_uv[0][0], src_uv[0][1], cr, cg, cb, ca)
	push_vertex(r, positions[1].x, positions[1].y, src_uv[1][0], src_uv[1][1], cr, cg, cb, ca)
	push_vertex(r, positions[2].x, positions[2].y, src_uv[2][0], src_uv[2][1], cr, cg, cb, ca)
	push_vertex(r, positions[3].x, positions[3].y, src_uv[3][0], src_uv[3][1], cr, cg, cb, ca)
}

// Shared setup for push_quad and push_quad_ex: check frame active, look up texture,
// flush on texture change or batch full. Returns the renderer pointer, or nil if
// the quad should be skipped.
@(private = "file")
prepare_quad :: proc(tex_handle: core.Texture_Handle) -> ^Renderer {
	r := &renderer
	if !r.frame.active {
		return nil
	}

	entry, ok := &r.textures[tex_handle]
	if !ok {
		return nil
	}

	if r.batch.texture_view != entry.view {
		renderer_flush()
		r.batch.texture_view = entry.view
		bind_texture(entry.view)
		r.current_stats.texture_switches += 1
	}

	if r.batch.vertex_count + 4 > BATCH_MAX_VERTICES {
		renderer_flush()
	}

	return r
}

// Convert Color ([4]u8) to four f32 components.
@(private = "file")
color_to_f32 :: proc(c: core.Color) -> (r, g, b, a: f32) {
	return f32(c[0]) / 255.0, f32(c[1]) / 255.0, f32(c[2]) / 255.0, f32(c[3]) / 255.0
}

@(private = "file")
push_vertex :: proc(r: ^Renderer, px, py, u, v, cr, cg, cb, ca: f32) {
	base := r.batch.vertex_count * VERTEX_FLOATS
	r.batch.vertices[base + 0] = px
	r.batch.vertices[base + 1] = py
	r.batch.vertices[base + 2] = u
	r.batch.vertices[base + 3] = v
	r.batch.vertices[base + 4] = cr
	r.batch.vertices[base + 5] = cg
	r.batch.vertices[base + 6] = cb
	r.batch.vertices[base + 7] = ca
	r.batch.vertex_count += 1
}

@(private = "file")
bind_texture :: proc(tex_view: wgpu.TextureView) {
	r := &renderer

	r.batch.bind_group = wgpu.DeviceCreateBindGroup(
		r.device,
		&{
			layout = r.bind_group_layout,
			entryCount = 3,
			entries = raw_data(
				[]wgpu.BindGroupEntry {
					{
						binding = 0,
						buffer = r.projection_buffer,
						offset = r.projection_offset,
						size = PROJECTION_MATRIX_SIZE,
					},
					{binding = 1, sampler = r.sampler},
					{binding = 2, textureView = tex_view},
				},
			),
		},
	)

	// Track for deferred release after frame submit.
	assert(
		r.frame.bind_group_count < MAX_BIND_GROUPS_PER_FRAME,
		"Too many texture switches in one frame",
	)
	r.frame.bind_groups[r.frame.bind_group_count] = r.batch.bind_group
	r.frame.bind_group_count += 1
}

// Helper to convert Color ([4]u8) to [4]f64 for wgpu clear values.
@(private = "file")
color_to_f64 :: proc(c: core.Color) -> [4]f64 {
	return {f64(c[0]) / 255.0, f64(c[1]) / 255.0, f64(c[2]) / 255.0, f64(c[3]) / 255.0}
}
