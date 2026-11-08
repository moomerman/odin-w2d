#+build !js
package renderer_wgpu

// Pixel readback: copy a texture into a mappable buffer, block until the
// map completes, then repack the rows as tightly packed RGBA8. A debug and
// test tool — each call stalls the CPU until the GPU has drained.

import "base:runtime"
import "vendor:wgpu"

import core "../../core"

// wgpu requires bytesPerRow in texture-to-buffer copies to be a multiple of this.
@(private = "file")
COPY_BYTES_PER_ROW_ALIGNMENT :: 256

// Upper bound on blocking polls while waiting for a buffer map.
@(private = "file")
MAX_MAP_POLLS :: 10_000

@(private = "file")
Map_Result :: struct {
	done:   bool,
	status: wgpu.MapAsyncStatus,
}

@(private = "package")
renderer_read_pixels :: proc(
	allocator: runtime.Allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	r := &renderer
	if !r.frame.active {
		return
	}
	// An occluded frame draws into the offscreen target, which always has
	// CopySrc; a surface texture only when the surface allowed it.
	tex := r.frame.surface_tex.texture
	if r.frame.offscreen {
		tex = r.offscreen_tex
	} else if !r.surface_copy_src {
		return
	}
	return read_frame_texture(
		tex,
		r.config.format,
		r.config.width,
		r.config.height,
		true,
		allocator,
	)
}

@(private = "package")
renderer_read_texture :: proc(
	handle: core.Texture_Handle,
	allocator: runtime.Allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	r := &renderer
	if !r.initialized {
		return
	}
	entry, found := r.textures[handle]
	if !found || entry.width <= 0 || entry.height <= 0 {
		return
	}
	// Render textures are BGRA8 with CopySrc; plain textures are RGBA8 and
	// were created without CopySrc, so only render textures can be read.
	if .CopySrc not_in wgpu.TextureGetUsage(entry.handle) {
		return
	}
	format := wgpu.TextureGetFormat(entry.handle)
	if r.frame.active {
		return read_frame_texture(
			entry.handle,
			format,
			u32(entry.width),
			u32(entry.height),
			false,
			allocator,
		)
	}
	encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
	return copy_and_map(
		encoder,
		entry.handle,
		format,
		u32(entry.width),
		u32(entry.height),
		false,
		allocator,
	)
}

// Read a texture mid-frame: flush, end the current pass, submit the work so
// far plus the copy, then resume drawing on a fresh encoder and pass that
// loads the existing contents of the current target.
@(private = "file")
read_frame_texture :: proc(
	tex: wgpu.Texture,
	format: wgpu.TextureFormat,
	w, h: u32,
	opaque: bool,
	allocator: runtime.Allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	r := &renderer
	renderer_flush()
	wgpu.RenderPassEncoderEnd(r.frame.pass)
	wgpu.RenderPassEncoderRelease(r.frame.pass)
	r.batch.texture_view = nil
	r.batch.bind_group = nil

	pixels, width, height, ok = copy_and_map(r.frame.encoder, tex, format, w, h, opaque, allocator)

	r.frame.encoder = wgpu.DeviceCreateCommandEncoder(r.device, nil)
	target_view := r.frame.view
	if handle, has := r.frame.target.?; has {
		if entry, found := r.textures[handle]; found {
			target_view = entry.view
		}
	}
	r.frame.pass = wgpu.CommandEncoderBeginRenderPass(
		r.frame.encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = target_view,
				loadOp = .Load,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			},
		},
	)
	if r.scissor_rect != nil {
		apply_scissor_rect()
	}
	return
}

// Record a texture-to-buffer copy on encoder, finish and submit it (taking
// ownership of the encoder), wait for the map and convert to RGBA8.
@(private = "file")
copy_and_map :: proc(
	encoder: wgpu.CommandEncoder,
	tex: wgpu.Texture,
	format: wgpu.TextureFormat,
	w, h: u32,
	opaque: bool,
	allocator: runtime.Allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	r := &renderer

	swizzle: bool
	#partial switch format {
	case .RGBA8Unorm, .RGBA8UnormSrgb:
	case .BGRA8Unorm, .BGRA8UnormSrgb:
		swizzle = true
	case:
		wgpu.CommandEncoderRelease(encoder)
		return
	}

	padded_row := (w * 4 + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &~ (COPY_BYTES_PER_ROW_ALIGNMENT - 1)
	size := u64(padded_row) * u64(h)
	buffer := wgpu.DeviceCreateBuffer(
		r.device,
		&{label = "Readback Buffer", usage = {.CopyDst, .MapRead}, size = size},
	)
	defer wgpu.BufferRelease(buffer)

	wgpu.CommandEncoderCopyTextureToBuffer(
		encoder,
		&{texture = tex, aspect = .All},
		&{layout = {bytesPerRow = padded_row, rowsPerImage = h}, buffer = buffer},
		&{w, h, 1},
	)
	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	wgpu.QueueSubmit(r.queue, {command_buffer})
	wgpu.CommandBufferRelease(command_buffer)
	wgpu.CommandEncoderRelease(encoder)

	result: Map_Result
	wgpu.BufferMapAsync(
		buffer,
		{.Read},
		0,
		uint(size),
		{mode = .AllowProcessEvents, callback = on_mapped, userdata1 = &result},
	)
	for i := 0; !result.done && i < MAX_MAP_POLLS; i += 1 {
		wgpu.DevicePoll(r.device, true, nil)
		wgpu.InstanceProcessEvents(r.instance)
	}
	if !result.done || result.status != .Success {
		return
	}
	defer wgpu.BufferUnmap(buffer)

	mapped := wgpu.BufferGetConstMappedRange(buffer, 0, uint(size))
	if mapped == nil {
		return
	}

	err: runtime.Allocator_Error
	pixels, err = make([]u8, int(w) * int(h) * 4, allocator)
	if err != nil {
		return
	}
	row := int(w) * 4
	for y in 0 ..< int(h) {
		src := mapped[y * int(padded_row):][:row]
		dst := pixels[y * row:][:row]
		copy(dst, src)
		if swizzle || opaque {
			for x := 0; x < row; x += 4 {
				if swizzle {
					dst[x], dst[x + 2] = dst[x + 2], dst[x]
				}
				if opaque {
					dst[x + 3] = 255
				}
			}
		}
	}
	return pixels, int(w), int(h), true

	on_mapped :: proc "c" (
		status: wgpu.MapAsyncStatus,
		message: wgpu.StringView,
		userdata1, userdata2: rawptr,
	) {
		res := (^Map_Result)(userdata1)
		res.done = true
		res.status = status
	}
}
