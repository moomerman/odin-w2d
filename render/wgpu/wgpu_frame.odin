package renderer_wgpu

import hm "core:container/handle_map"
import "core:fmt"
import "core:math/linalg"
import "core:time"
import "vendor:wgpu"

import core "../../core"

// How often the surface is drawn when vsync is off or the window is
// occluded; the display rate is not known, 60 Hz is the common case.
@(private = "file")
SURFACE_FRAME_INTERVAL :: time.Second / 60

// Begin a new frame, clearing the screen with the given color.
@(private = "package")
renderer_begin_frame :: proc(color: core.Color) -> bool {
	r := &renderer
	if !r.initialized {
		return false
	}

	r.frame_index += 1
	r.batch.vertex_count = 0
	r.batch.buffer_index = 0
	r.batch.buffer_offset = 0
	r.batch.texture_view = nil
	r.batch.bind_group = nil
	r.frame.bind_group_count = 0
	clear(&r.frame.bind_group_cache)
	r.batch.active_shader = {}
	r.batch.blend_mode = .Alpha
	// Slot 0 holds the base window projection (renderer_update_projection);
	// per-frame camera and render-target matrices go in slots 1 and up.
	r.projection_slot = 1
	r.projection_offset = 0

	// Reset per-frame stats, carrying over resource counts.
	r.current_stats = {
		textures_alive = r.current_stats.textures_alive,
		texture_memory = r.current_stats.texture_memory,
	}

	apply_present_mode()

	// Acquiring a surface texture blocks until the compositor frees one,
	// which macOS paces at the display rate whatever the present mode. So
	// with vsync off the surface is drawn at most once per display period
	// and the frames between go to the offscreen target: the frame loop
	// never waits for the display, and the window still shows the latest
	// picture.
	r.frame.offscreen = false
	now := time.tick_now()
	if r.surface == nil {
		// Headless (null window backend): there is no surface, so every
		// frame is offscreen and nothing paces the loop.
		r.frame.offscreen = true
	} else if !r.vsync && time.tick_diff(r.last_surface_frame, now) < SURFACE_FRAME_INTERVAL {
		r.frame.offscreen = true
	} else {
		r.frame.surface_tex = wgpu.SurfaceGetCurrentTexture(r.surface)
		switch r.frame.surface_tex.status {
		case .SuccessOptimal, .SuccessSuboptimal:
			r.frame.view = wgpu.TextureCreateView(r.frame.surface_tex.texture, nil)
			r.last_surface_frame = now
		case .Timeout, .Outdated, .Lost:
			if r.frame.surface_tex.texture != nil {
				wgpu.TextureRelease(r.frame.surface_tex.texture)
			}
			renderer_resize()
			return false
		case .Occluded:
			// Window hidden, covered, or (macOS) not yet shown: the surface
			// has no texture for us. Draw offscreen instead so the frame
			// proc, readback and timing behave as usual, and (vsync on)
			// hold the loop to the display rate rather than spin.
			if r.frame.surface_tex.texture != nil {
				wgpu.TextureRelease(r.frame.surface_tex.texture)
			}
			r.frame.offscreen = true
			if r.vsync {
				if left := SURFACE_FRAME_INTERVAL - time.tick_diff(r.last_surface_frame, now);
				   left > 0 {
					time.sleep(left)
				}
				r.last_surface_frame = time.tick_now()
			}
		case .Error:
			fmt.panicf("[renderer/wgpu] get_current_texture status=%v", r.frame.surface_tex.status)
		}
	}
	if r.frame.offscreen {
		r.frame.surface_tex.texture = nil
		r.frame.view = offscreen_view()
		r.frame.surface_w, r.frame.surface_h = r.offscreen_w, r.offscreen_h
	} else {
		r.frame.surface_w = wgpu.TextureGetWidth(r.frame.surface_tex.texture)
		r.frame.surface_h = wgpu.TextureGetHeight(r.frame.surface_tex.texture)
	}
	r.frame.target_w, r.frame.target_h = r.frame.surface_w, r.frame.surface_h

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
	r.frame.target = nil
	r.scissor_rect = nil
	r.scissor_empty = false
	return true
}

// Flush all batched vertices to the GPU and draw them.
@(private = "package")
renderer_flush :: proc() {
	r := &renderer
	if r.batch.vertex_count == 0 || !r.frame.active {
		return
	}
	// The scissor rect covers none of the target: nothing can be drawn.
	if r.scissor_empty {
		r.batch.vertex_count = 0
		return
	}

	// Upload vertex data at the current offset into the GPU buffer. Regions
	// written earlier this frame are still referenced by recorded draws, so
	// when this buffer is full move on to the next one (creating it if this
	// is the most any frame has needed so far).
	if r.batch.buffer_offset + r.batch.vertex_count > GPU_BUFFER_VERTICES {
		r.batch.buffer_index += 1
		r.batch.buffer_offset = 0
		if r.batch.buffer_index == len(r.vertex_buffers) {
			append(&r.vertex_buffers, create_vertex_buffer())
		}
	}
	vertex_buffer := r.vertex_buffers[r.batch.buffer_index]
	data_size := uint(r.batch.vertex_count * VERTEX_SIZE)
	gpu_offset := uint(r.batch.buffer_offset * VERTEX_SIZE)
	wgpu.QueueWriteBuffer(r.queue, vertex_buffer, u64(gpu_offset), &r.batch.vertices, data_size)

	// Use the custom shader pipeline if active (and compiled), otherwise the default.
	entry, ok := hm.get(&r.shaders, r.batch.active_shader)
	if ok && entry.pipelines[.Alpha] != nil {
		// Upload changed uniforms into a fresh slot; earlier draws this frame
		// keep reading the slot they were recorded with.
		if entry.uniform_buffer != nil {
			if entry.uniform_frame != r.frame_index {
				// First use this frame: slots restart at 0, and the slot the
				// shader last bound may be among those about to be reused,
				// so write the current values again.
				entry.uniform_frame = r.frame_index
				entry.uniform_slot = 0
				entry.uniform_dirty = true
			}
			if entry.uniform_dirty {
				if entry.uniform_slot >= entry.uniform_capacity {
					shader_grow_uniform_buffer(entry)
				}
				offset := u64(entry.uniform_slot) * entry.uniform_stride
				wgpu.QueueWriteBuffer(
					r.queue,
					entry.uniform_buffer,
					offset,
					raw_data(entry.uniform_data),
					uint(entry.uniform_size),
				)
				entry.uniform_offset = u32(offset)
				entry.uniform_slot += 1
				entry.uniform_dirty = false
			}
		}

		// Rebuild the group-1 bind group if a texture binding changed. The old
		// bind group may have been used earlier in this pass, so defer its
		// release to after submit via the per-frame ring.
		if entry.bind_group_dirty {
			if entry.bind_group != nil {
				assert(
					r.frame.bind_group_count < MAX_BIND_GROUPS_PER_FRAME,
					"Too many bind group changes in one frame",
				)
				r.frame.bind_groups[r.frame.bind_group_count] = entry.bind_group
				r.frame.bind_group_count += 1
			}
			entry.bind_group = shader_create_bind_group(entry)
			entry.bind_group_dirty = false
		}

		wgpu.RenderPassEncoderSetPipeline(r.frame.pass, shader_pipeline(entry, r.batch.blend_mode))
		if r.batch.bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.frame.pass, 0, r.batch.bind_group)
		}
		if entry.bind_group != nil {
			if entry.uniform_buffer != nil {
				offsets := [1]u32{entry.uniform_offset}
				wgpu.RenderPassEncoderSetBindGroup(r.frame.pass, 1, entry.bind_group, offsets[:])
			} else {
				wgpu.RenderPassEncoderSetBindGroup(r.frame.pass, 1, entry.bind_group)
			}
		}
	} else {
		wgpu.RenderPassEncoderSetPipeline(r.frame.pass, r.pipelines[r.batch.blend_mode])
		if r.batch.bind_group != nil {
			wgpu.RenderPassEncoderSetBindGroup(r.frame.pass, 0, r.batch.bind_group)
		}
	}

	wgpu.RenderPassEncoderSetVertexBuffer(
		r.frame.pass,
		0,
		vertex_buffer,
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
	r.batch.vertex_count = 0
}

// Switch the render target mid-frame.
// Pass a texture handle to draw into a render texture, or nil to draw to the screen.
// clear_color clears the target when set; nil preserves existing contents.
@(private = "package")
renderer_set_render_target :: proc(
	target: Maybe(core.Texture_Handle),
	clear_color: Maybe(core.Color),
) {
	r := &renderer
	if !r.frame.active {
		return
	}

	// Validate before touching the current pass: a destroyed handle, or a
	// texture that was not created as a render texture, can't be drawn into.
	if handle, ok := target.?; ok {
		entry, found := r.textures[handle]
		if !found ||
		   entry.view == nil ||
		   .RenderAttachment not_in wgpu.TextureGetUsage(entry.handle) {
			fmt.eprintln(
				"[renderer/wgpu] set_render_target: invalid or destroyed render texture — target unchanged",
			)
			return
		}
	}

	// Flush any pending geometry and end the current render pass.
	renderer_flush()
	wgpu.RenderPassEncoderEnd(r.frame.pass)
	wgpu.RenderPassEncoderRelease(r.frame.pass)
	r.batch.texture_view = nil
	r.batch.bind_group = nil

	// Determine the target view and dimensions.
	target_view: wgpu.TextureView
	target_w, target_h: u32

	r.frame.target = target
	if handle, ok := target.?; ok {
		entry := &r.textures[handle]
		target_view = entry.view
		target_w = u32(entry.width)
		target_h = u32(entry.height)
		r.frame.target_w, r.frame.target_h = target_w, target_h
	} else {
		target_view = r.frame.view
		target_w, target_h = r.window.get_window_size()
		r.frame.target_w, r.frame.target_h = r.frame.surface_w, r.frame.surface_h
	}

	// Choose load op: Clear if a clear color was given, Load to preserve contents.
	load_op: wgpu.LoadOp
	clear_value: wgpu.Color
	if cc, has_clear := clear_color.?; has_clear {
		load_op = .Clear
		cf := color_to_f64(cc)
		clear_value = {cf[0], cf[1], cf[2], cf[3]}
	} else {
		load_op = .Load
	}

	// Begin a new render pass on the target.
	r.frame.pass = wgpu.CommandEncoderBeginRenderPass(
		r.frame.encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = target_view,
				loadOp = load_op,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = clear_value,
			},
		},
	)

	// Update projection to match the target dimensions. The screen's is the
	// base window projection, which always lives in slot 0.
	if target == nil {
		r.projection_offset = 0
	} else {
		projection := linalg.matrix_ortho3d_f32(0, f32(target_w), f32(target_h), 0, -1, 1)
		assert(
			r.projection_slot < MAX_PROJECTION_SLOTS,
			"Too many render target switches in one frame (MAX_PROJECTION_SLOTS)",
		)
		offset := u64(r.projection_slot) * PROJECTION_SLOT_STRIDE
		wgpu.QueueWriteBuffer(
			r.queue,
			r.projection_buffer,
			offset,
			&projection,
			size_of(projection),
		)
		r.projection_offset = offset
		r.projection_slot += 1
	}

	// Reset scissor — the new pass defaults to full viewport.
	r.scissor_rect = nil
	r.scissor_empty = false
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
		// Reset scissor so custom renderers draw to the full viewport (of
		// the current target, which may be a render texture).
		if r.scissor_rect != nil {
			wgpu.RenderPassEncoderSetScissorRect(
				r.frame.pass,
				0,
				0,
				r.frame.target_w,
				r.frame.target_h,
			)
		}
		lw, lh := r.window.get_window_size()
		r.pre_present_callback(r.frame.pass, lw, lh)
	}

	wgpu.RenderPassEncoderEnd(r.frame.pass)
	wgpu.RenderPassEncoderRelease(r.frame.pass)

	command_buffer := wgpu.CommandEncoderFinish(r.frame.encoder, nil)
	wgpu.QueueSubmit(r.queue, {command_buffer})

	wgpu.CommandBufferRelease(command_buffer)
	wgpu.CommandEncoderRelease(r.frame.encoder)

	if !r.frame.offscreen {
		wgpu.SurfacePresent(r.surface)
	}
	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		wgpu.DevicePoll(r.device, false, nil)
	}

	// The offscreen view is kept across frames; a surface view is per frame.
	if !r.frame.offscreen {
		wgpu.TextureViewRelease(r.frame.view)
		wgpu.TextureRelease(r.frame.surface_tex.texture)
	}
	r.frame.view = nil

	// Release all bind groups created this frame now that the GPU is done with them.
	for i in 0 ..< r.frame.bind_group_count {
		wgpu.BindGroupRelease(r.frame.bind_groups[i])
	}
	r.frame.bind_group_count = 0
	r.batch.bind_group = nil
	for buffer in r.frame.released_buffers {
		wgpu.BufferRelease(buffer)
	}
	clear(&r.frame.released_buffers)

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

// Push a quad with explicit positions and a colour per vertex.
@(private = "package")
renderer_push_quad_colors :: proc(
	positions: [4]core.Vec2,
	src_uv: [4][2]f32,
	tex_handle: core.Texture_Handle,
	colors: [4]core.Color,
) {
	r := prepare_quad(tex_handle)
	if r == nil {return}

	for i in 0 ..< 4 {
		cr, cg, cb, ca := color_to_f32(colors[i])
		push_vertex(r, positions[i].x, positions[i].y, src_uv[i][0], src_uv[i][1], cr, cg, cb, ca)
	}
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

// Convert a straight-alpha Color ([4]u8) to four premultiplied f32 components.
@(private = "file")
color_to_f32 :: proc(c: core.Color) -> (r, g, b, a: f32) {
	a = f32(c[3]) / 255.0
	k := a / 255.0
	return f32(c[0]) * k, f32(c[1]) * k, f32(c[2]) * k, a
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

	key := Bind_Group_Key {
		view   = tex_view,
		offset = r.projection_offset,
	}
	if cached, found := r.frame.bind_group_cache[key]; found {
		r.batch.bind_group = cached
		return
	}

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

	// Track for deferred release after frame submit, and cache for reuse.
	assert(
		r.frame.bind_group_count < MAX_BIND_GROUPS_PER_FRAME,
		"Too many distinct texture/camera combinations in one frame (MAX_BIND_GROUPS_PER_FRAME)",
	)
	r.frame.bind_groups[r.frame.bind_group_count] = r.batch.bind_group
	r.frame.bind_group_count += 1
	r.frame.bind_group_cache[key] = r.batch.bind_group
}

// Convert a straight-alpha Color ([4]u8) to a premultiplied [4]f64 for wgpu
// clear values.
@(private = "file")
color_to_f64 :: proc(c: core.Color) -> [4]f64 {
	a := f64(c[3]) / 255.0
	k := a / 255.0
	return {f64(c[0]) * k, f64(c[1]) * k, f64(c[2]) * k, a}
}

//-----------//
// OFFSCREEN //
//-----------//

// The offscreen target at the current surface size, created or resized on
// demand. BGRA8 like the surface so shaders and readback see one format.
@(private = "package")
offscreen_view :: proc() -> wgpu.TextureView {
	r := &renderer
	if r.offscreen_view != nil &&
	   r.offscreen_w == r.config.width &&
	   r.offscreen_h == r.config.height {
		return r.offscreen_view
	}
	offscreen_destroy()
	r.offscreen_tex = wgpu.DeviceCreateTexture(
		r.device,
		&{
			label = "Offscreen Target",
			usage = {.RenderAttachment, .CopySrc},
			dimension = ._2D,
			size = {r.config.width, r.config.height, 1},
			format = r.config.format,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	r.offscreen_view = wgpu.TextureCreateView(r.offscreen_tex, nil)
	r.offscreen_w = r.config.width
	r.offscreen_h = r.config.height
	return r.offscreen_view
}

@(private = "package")
offscreen_destroy :: proc() {
	r := &renderer
	if r.offscreen_view != nil {
		wgpu.TextureViewRelease(r.offscreen_view)
		r.offscreen_view = nil
	}
	if r.offscreen_tex != nil {
		wgpu.TextureRelease(r.offscreen_tex)
		r.offscreen_tex = nil
	}
	r.offscreen_w, r.offscreen_h = 0, 0
}
