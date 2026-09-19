package engine

// Set the blend mode for all subsequent drawing, including draws with a
// custom shader. The mode persists across render-texture switches and resets
// to .Alpha at the start of each frame.
//
// Example: accumulate lights additively into a light-map
//   w.set_render_texture(light_map, w.BLACK)
//   w.set_blend_mode(.Additive)
//   // draw light sprites here
//   w.reset_blend_mode()
//   w.reset_render_texture()
set_blend_mode :: proc(mode: Blend_Mode) {
	ctx.renderer.set_blend_mode(mode)
}

// Restore the default alpha blend mode.
reset_blend_mode :: proc() {
	ctx.renderer.set_blend_mode(.Alpha)
}
