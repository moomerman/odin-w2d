package engine

// Create a render texture that you can draw into. Use set_render_texture to
// direct drawing into it, then draw_texture to display it on screen.
create_render_texture :: proc(width: int, height: int) -> Render_Texture {
	handle := ctx.renderer.create_render_texture(width, height)
	return Render_Texture{texture = Texture{handle = handle, width = width, height = height}}
}

// Direct all subsequent drawing into a render texture. Pass a clear_color
// to clear the texture first, or omit it to preserve existing contents.
// Call reset_render_texture to resume drawing to the screen.
// Must be called after clear() which starts the frame.
set_render_texture :: proc(rt: Render_Texture, clear_color: Maybe(Color) = nil) {
	ctx.renderer.set_render_target(rt.texture.handle, clear_color)
}

// Resume drawing to the screen after drawing into a render texture.
// Existing screen contents from before set_render_texture are preserved.
reset_render_texture :: proc() {
	ctx.renderer.set_render_target(nil, nil)
	// Re-apply the camera/projection for the screen.
	upload_view_projection()
}

// Destroy a render texture and free its GPU resources.
destroy_render_texture :: proc(rt: ^Render_Texture) {
	ctx.renderer.destroy_texture(rt.texture.handle)
	rt.texture.handle = {}
	rt.texture.width = 0
	rt.texture.height = 0
}
