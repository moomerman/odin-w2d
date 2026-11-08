package engine

// Read back the pixels drawn so far this frame, as tightly packed RGBA8,
// row 0 at the top, at the window's framebuffer size in physical pixels
// (HiDPI: the real pixel size, not get_screen_size). Flushes pending draws.
// Call from inside the frame proc after drawing, before present. Drawing
// from set_pre_present_callback runs at present, so it is not included.
// Stalls until the GPU has finished the frame so far: a debug/test tool.
// Desktop only; on js returns ok = false.
read_pixels :: proc(
	allocator := context.allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	return ctx.renderer.read_pixels(allocator)
}

// Read back a render texture's contents as tightly packed RGBA8, row 0 at
// the top. Works inside a frame (after drawing into it) or between frames.
// Stalls like read_pixels. Desktop only; on js returns ok = false.
read_render_texture :: proc(
	rt: Render_Texture,
	allocator := context.allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	return ctx.renderer.read_texture(rt.texture.handle, allocator)
}
