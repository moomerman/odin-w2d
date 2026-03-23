package renderer_wgpu

import "vendor:wgpu"

import core "../../core"

// Allocate a new texture handle.
@(private = "file")
alloc_handle :: proc() -> core.Texture_Handle {
	handle := core.Texture_Handle(renderer.next_handle_id)
	renderer.next_handle_id += 1
	return handle
}

// Create a texture from raw RGBA pixel data.
@(private = "package")
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
@(private = "package")
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
@(private = "package")
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

@(private = "package")
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

@(private = "package")
renderer_get_white_texture :: proc() -> core.Texture_Handle {
	return renderer.white_texture
}
