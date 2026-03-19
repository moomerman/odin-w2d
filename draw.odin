package engine

import "core:fmt"
import "core:image"
import _ "core:image/bmp"
import _ "core:image/png"
import _ "core:image/tga"

// Clear the screen with a solid color. Call once at the start of each frame's drawing.
clear :: proc(color: Color) {
	ctx.renderer.begin_frame(color)
}

// Present the frame to the screen. Call once at the end of each frame's drawing.
present :: proc() {
	ctx.renderer.present()
}

// Draw a solid-colored rectangle.
draw_rect :: proc(r: Rect, color: Color) {
	white := ctx.renderer.get_white_texture()
	// Full UV rect for the 1x1 white texture
	uv := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	ctx.renderer.push_quad(r, uv, white, color)
}

// Draw a texture at the given position with an optional tint.
draw_texture :: proc(tex: Texture, pos: Vec2, tint: Color = WHITE) {
	dst := Rect{pos.x, pos.y, f32(tex.width), f32(tex.height)}
	uv := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	ctx.renderer.push_quad(dst, uv, tex.handle, tint)
}

// Draw a sub-region of a texture into a destination rectangle with an optional tint.
draw_texture_rect :: proc(tex: Texture, src: Rect, dst: Rect, tint: Color = WHITE) {
	// Convert pixel-space source rect to normalized UV coordinates.
	tw := f32(tex.width)
	th := f32(tex.height)
	u0 := src.x / tw
	v0 := src.y / th
	u1 := (src.x + src.w) / tw
	v1 := (src.y + src.h) / th
	uv := [4][2]f32{{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}
	ctx.renderer.push_quad(dst, uv, tex.handle, tint)
}

// Load a texture from a byte slice. Supports two modes:
//
// 1. Encoded image (PNG, BMP, TGA) — pass the file bytes, dimensions are read from the header:
//      tex = engine.load_texture(#load("logo.png"))
//
// 2. Raw RGBA8 pixel data — pass the pixels and specify dimensions:
//      tex = engine.load_texture(pixels[:], 16, 16)
//
load_texture :: proc(bytes: []u8, width: int = 0, height: int = 0) -> Texture {
	if width > 0 && height > 0 {
		// Raw RGBA8 pixel data.
		handle := ctx.renderer.create_texture(bytes, width, height)
		return Texture{handle = handle, width = width, height = height}
	}

	// Encoded image — decode via core:image.
	img, img_err := image.load_from_bytes(bytes, {.alpha_add_if_missing})
	if img_err != nil {
		fmt.panicf("[engine] failed to load texture: %v", img_err)
	}
	defer image.destroy(img)

	handle := ctx.renderer.create_texture(img.pixels.buf[:], img.width, img.height)
	return Texture{handle = handle, width = img.width, height = img.height}
}

// Destroy a texture and free its GPU resources.
destroy_texture :: proc(tex: ^Texture) {
	ctx.renderer.destroy_texture(tex.handle)
	tex.handle = {}
	tex.width = 0
	tex.height = 0
}
