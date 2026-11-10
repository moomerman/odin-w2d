package engine

// Per-texture sampling: how a texture is filtered and what it returns
// outside its edges. Applies to loaded textures and render textures alike
// (pass rt.texture), for the default shader and for custom shaders, which
// sample through the same group 0 `tex_sampler` binding. Every texture
// starts as .Nearest / .Clamp: crisp pixels, edges clamped.
//
// A change affects draws issued after it, including later in the same
// frame; draws already issued keep the previous setting. The setting lives
// with the texture's handle, so it survives a hot reload of the file.
//
// The font atlas stays .Nearest / .Clamp: glyphs are rasterised at the size
// they are drawn, so filtering would only soften them.

// Nearest (default) keeps pixel art crisp. Linear blends neighbouring texels:
// use it for smooth scaling, rotation, or a low-resolution render texture
// stretched over the screen by a post-process shader.
set_texture_filter :: proc(tex: Texture, filter: Texture_Filter) {
	_, wrap, ok := ctx.renderer.get_texture_sampling(tex.handle)
	if ok {
		ctx.renderer.set_texture_sampling(tex.handle, filter, wrap)
	}
}

// Clamp (default) stretches the edge texels outwards. Repeat tiles the
// texture, so a source rect larger than the texture draws several copies:
// a scrolling backdrop is draw_texture_rect with a moving, oversized src.
// Mirror tiles with every other copy flipped.
set_texture_wrap :: proc(tex: Texture, wrap: Texture_Wrap) {
	filter, _, ok := ctx.renderer.get_texture_sampling(tex.handle)
	if ok {
		ctx.renderer.set_texture_sampling(tex.handle, filter, wrap)
	}
}

// The texture's current filter (.Nearest for an unknown handle).
get_texture_filter :: proc(tex: Texture) -> Texture_Filter {
	filter, _, _ := ctx.renderer.get_texture_sampling(tex.handle)
	return filter
}

// The texture's current wrap mode (.Clamp for an unknown handle).
get_texture_wrap :: proc(tex: Texture) -> Texture_Wrap {
	_, wrap, _ := ctx.renderer.get_texture_sampling(tex.handle)
	return wrap
}
