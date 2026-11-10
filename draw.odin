package engine

import "core:fmt"
import "core:image"
import _ "core:image/bmp"
import _ "core:image/png"
import _ "core:image/tga"
import "core:math"

// Full UV rect for the 1x1 white texture — used by all solid-color primitives.
@(private = "package")
WHITE_UV :: [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}

// Clear the screen with a solid color. Call once at the start of each frame's drawing.
clear :: proc(color: Color) {
	ctx.renderer.begin_frame(color)
	transform_reset()
	// Re-apply camera view_projection in case the projection was reset by a resize
	// (e.g. surface lost during begin_frame). This is a cheap 64-byte buffer write.
	if ctx.camera != nil {
		upload_view_projection()
	}
}

// Present the frame to the screen. Call once at the end of each frame's drawing.
present :: proc() {
	automation_present() // scripted screenshots of this frame
	ctx.renderer.present()
}

// Draw a solid-colored rectangle.
draw_rect :: proc(r: Rect, color: Color) {
	white := ctx.renderer.get_white_texture()
	emit_quad(r, WHITE_UV, white, color)
}

// Draw the outline of a rectangle with a given thickness.
draw_rect_outline :: proc(r: Rect, thickness: f32, color: Color) {
	// Top edge
	draw_rect({r.x, r.y, r.w, thickness}, color)
	// Bottom edge
	draw_rect({r.x, r.y + r.h - thickness, r.w, thickness}, color)
	// Left edge (between top and bottom)
	draw_rect({r.x, r.y + thickness, thickness, r.h - thickness * 2}, color)
	// Right edge (between top and bottom)
	draw_rect({r.x + r.w - thickness, r.y + thickness, thickness, r.h - thickness * 2}, color)
}

// Draw a line between two points with a given thickness.
draw_line :: proc(from: Vec2, to: Vec2, thickness: f32, color: Color) {
	dx := to.x - from.x
	dy := to.y - from.y
	length := math.sqrt(dx * dx + dy * dy)
	if length < 0.001 {
		return
	}

	// Perpendicular unit vector scaled by half thickness.
	nx := (-dy / length) * thickness * 0.5
	ny := (dx / length) * thickness * 0.5

	// Four corners of the line quad.
	// p0--p1
	// |    |
	// p3--p2
	p0 := Vec2{from.x + nx, from.y + ny}
	p1 := Vec2{to.x + nx, to.y + ny}
	p2 := Vec2{to.x - nx, to.y - ny}
	p3 := Vec2{from.x - nx, from.y - ny}

	white := ctx.renderer.get_white_texture()
	emit_quad_ex({p0, p1, p2, p3}, WHITE_UV, white, color)
}

// Draw a texture at the given position with an optional tint.
draw_texture :: proc(tex: Texture, pos: Vec2, tint: Color = WHITE) {
	dst := Rect{pos.x, pos.y, f32(tex.width), f32(tex.height)}
	emit_quad(dst, WHITE_UV, tex.handle, tint)
}

// Draw a sub-region of a texture into a destination rectangle with an optional tint.
// A negative src width or height mirrors the image (see source_uv).
draw_texture_rect :: proc(tex: Texture, src: Rect, dst: Rect, tint: Color = WHITE) {
	emit_quad(dst, source_uv(tex, src), tex.handle, tint)
}

// Normalized UVs (top-left, top-right, bottom-right, bottom-left) for a
// pixel-space source rect. The rect is taken literally: its left edge is x
// and its right edge x + w, so a negative width mirrors the image, and
// covers the texels to the LEFT of x. To flip a sprite cell in place, move
// the origin to the far edge and negate the size:
//     src.x += src.w; src.w = -src.w
// (likewise y and h to flip vertically).
@(private = "file")
source_uv :: proc(tex: Texture, src: Rect) -> [4][2]f32 {
	tw := f32(tex.width)
	th := f32(tex.height)
	u0, u1 := src.x / tw, (src.x + src.w) / tw
	v0, v1 := src.y / th, (src.y + src.h) / th
	return {{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}
}

// Draw a rectangle with a custom origin and rotation.
// The origin is relative to the rectangle's top-left corner. For example,
// {r.w/2, r.h/2} rotates around the center.
// Rotation is in radians.
draw_rect_ex :: proc(r: Rect, origin: Vec2, rotation: f32, color: Color) {
	white := ctx.renderer.get_white_texture()

	// Corners relative to the origin point.
	corners := [4]Vec2 {
		{-origin.x, -origin.y},
		{r.w - origin.x, -origin.y},
		{r.w - origin.x, r.h - origin.y},
		{-origin.x, r.h - origin.y},
	}

	// Rotate each corner and translate to the rect position + origin.
	center := Vec2{r.x + origin.x, r.y + origin.y}
	positions: [4]Vec2
	for i in 0 ..< 4 {
		positions[i] = rotate_vec2(corners[i], rotation) + center
	}

	emit_quad_ex(positions, WHITE_UV, white, color)
}

// Draw a texture from `src` into `dst`, rotated around `origin` by `rotation` radians.
// The origin is relative to the destination rectangle's top-left corner.
// A negative src width or height mirrors the image, as in draw_texture_rect.
draw_texture_ex :: proc(
	tex: Texture,
	src: Rect,
	dst: Rect,
	origin: Vec2,
	rotation: f32,
	tint: Color = WHITE,
) {
	uv := source_uv(tex, src)

	corners := [4]Vec2 {
		{-origin.x, -origin.y},
		{dst.w - origin.x, -origin.y},
		{dst.w - origin.x, dst.h - origin.y},
		{-origin.x, dst.h - origin.y},
	}

	center := Vec2{dst.x + origin.x, dst.y + origin.y}
	positions: [4]Vec2
	for i in 0 ..< 4 {
		positions[i] = rotate_vec2(corners[i], rotation) + center
	}

	emit_quad_ex(positions, uv, tex.handle, tint)
}

// Draw a filled circle.
draw_circle :: proc(center: Vec2, radius: f32, color: Color, segments: int = 16) {
	white := ctx.renderer.get_white_texture()
	step := math.TAU / f32(segments)

	for i in 0 ..< segments {
		a0 := step * f32(i)
		a1 := step * f32(i + 1)

		p1 := Vec2{center.x + math.cos(a0) * radius, center.y + math.sin(a0) * radius}
		p2 := Vec2{center.x + math.cos(a1) * radius, center.y + math.sin(a1) * radius}

		// Degenerate quad: 4th vertex = 3rd to form a single triangle.
		emit_quad_ex({center, p1, p2, p2}, WHITE_UV, white, color)
	}
}

// Draw the outline of a circle.
draw_circle_outline :: proc(
	center: Vec2,
	radius: f32,
	thickness: f32,
	color: Color,
	segments: int = 16,
) {
	white := ctx.renderer.get_white_texture()
	step := math.TAU / f32(segments)
	inner := radius - thickness * 0.5
	outer := radius + thickness * 0.5

	for i in 0 ..< segments {
		a0 := step * f32(i)
		a1 := step * f32(i + 1)
		c0 := math.cos(a0)
		s0 := math.sin(a0)
		c1 := math.cos(a1)
		s1 := math.sin(a1)

		emit_quad_ex(
			{
				{center.x + c0 * outer, center.y + s0 * outer},
				{center.x + c1 * outer, center.y + s1 * outer},
				{center.x + c1 * inner, center.y + s1 * inner},
				{center.x + c0 * inner, center.y + s0 * inner},
			},
			WHITE_UV,
			white,
			color,
		)
	}
}

// Draw a convex quad with one colour per vertex (top-left, top-right,
// bottom-right, bottom-left order). Colours interpolate across the quad.
draw_quad :: proc(positions: [4]Vec2, colors: [4]Color) {
	white := ctx.renderer.get_white_texture()
	emit_quad_colors(positions, WHITE_UV, white, colors)
}

// Rectangle with a different colour at each corner (top-left, top-right,
// bottom-right, bottom-left).
draw_rect_gradient :: proc(r: Rect, top_left, top_right, bottom_right, bottom_left: Color) {
	draw_quad(
		{{r.x, r.y}, {r.x + r.w, r.y}, {r.x + r.w, r.y + r.h}, {r.x, r.y + r.h}},
		{top_left, top_right, bottom_right, bottom_left},
	)
}

// Vertical gradient: `top` at the top edge fading to `bottom`.
draw_rect_gradient_v :: proc(r: Rect, top, bottom: Color) {
	draw_rect_gradient(r, top, top, bottom, bottom)
}

// Horizontal gradient: `left` at the left edge fading to `right`.
draw_rect_gradient_h :: proc(r: Rect, left, right: Color) {
	draw_rect_gradient(r, left, right, right, left)
}

// Draw a filled triangle.
draw_triangle :: proc(vertices: [3]Vec2, color: Color) {
	white := ctx.renderer.get_white_texture()
	// Degenerate quad: 4th vertex = 3rd to form a single triangle.
	emit_quad_ex({vertices[0], vertices[1], vertices[2], vertices[2]}, WHITE_UV, white, color)
}

@(private = "file")
rotate_vec2 :: proc(v: Vec2, angle: f32) -> Vec2 {
	c := math.cos(angle)
	s := math.sin(angle)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

// Load a texture from a byte slice. Supports two modes:
//
// 1. Encoded image (PNG, BMP, TGA) — pass the file bytes, dimensions are read from the header:
//      tex = engine.load_texture(#load("logo.png"))
//
// 2. Raw RGBA8 pixel data — pass the pixels and specify dimensions:
//      tex = engine.load_texture(pixels[:], 16, 16)
//
// Either way the pixels are ordinary straight-alpha RGBA, as image files
// store them; the engine premultiplies them for the GPU.
load_texture :: proc(bytes: []u8, width: int = 0, height: int = 0) -> Texture {
	if width > 0 && height > 0 {
		// Raw RGBA8 pixel data. Premultiply a copy: the caller keeps theirs.
		pixels := premultiplied_copy(bytes)
		defer delete(pixels)
		handle := ctx.renderer.create_texture(pixels, width, height)
		return Texture{handle = handle, width = width, height = height}
	}

	img, img_err := decode_image(bytes)
	if img_err != nil {
		fmt.panicf("[engine] failed to load texture: %v", img_err)
	}
	defer image.destroy(img)

	premultiply_alpha(img.pixels[:])
	handle := ctx.renderer.create_texture(img.pixels[:], img.width, img.height)
	return Texture{handle = handle, width = img.width, height = img.height}
}

// Decode an encoded image (PNG/BMP/TGA) into straight-alpha RGBA8. The
// caller owns the result and must free it with image.destroy.
@(private = "package")
decode_image :: proc(bytes: []u8) -> (img: ^image.Image, err: image.Error) {
	return image.load_from_bytes(bytes, {.alpha_add_if_missing})
}

@(private = "file")
STATS_UPDATE_INTERVAL :: 0.5 // seconds between stats text refreshes

@(private = "file")
stats_text_buf: [256]u8

@(private = "file")
stats_text: string

@(private = "file")
stats_timer: f32 = STATS_UPDATE_INTERVAL // start expired so first frame updates immediately

// Draw a debug status bar at the bottom of the screen showing FPS, frame time, and draw calls.
draw_stats :: proc() {
	stats_timer += ctx.frame_time
	if stats_timer >= STATS_UPDATE_INTERVAL {
		stats_timer = 0
		stats := get_stats()
		n := fmt.bprintf(
			stats_text_buf[:],
			"FPS: %.0f  |  Frame: %.1fms  |  Draw calls: %d  |  Quads: %d  |  Textures: %d",
			stats.fps,
			stats.frame_time_ms,
			stats.draw_calls,
			stats.quads,
			stats.textures_alive,
		)
		stats_text = string(stats_text_buf[:len(n)])
	}

	w, h := ctx.window.get_window_size()
	screen_w := f32(w)
	screen_h := f32(h)

	font_size: f32 = 16
	padding: f32 = 6
	bar_height := font_size + padding * 2

	draw_rect({0, screen_h - bar_height, screen_w, bar_height}, {0, 0, 0, 120})
	draw_text(stats_text, {padding + 14, screen_h - bar_height + padding}, font_size, LIGHT_GRAY)
}

// Update a sub-region of an existing texture with new RGBA8 pixel data
// (straight alpha, like load_texture).
update_texture :: proc(tex: Texture, data: []u8, x, y, width, height: int) {
	pixels := premultiplied_copy(data)
	defer delete(pixels)
	ctx.renderer.update_texture(tex.handle, pixels, x, y, width, height)
}

// --- Premultiplied alpha --------------------------------------------------------
// The public API speaks straight alpha (Color values, texture pixels,
// readback); the renderer works in premultiplied alpha, where RGB is already
// scaled by A. That is what makes blending, filtering and render-texture
// compositing come out right. These helpers convert RGBA8 at the boundary.

// Multiply RGB by alpha in place, rounding to nearest.
@(private = "package")
premultiply_alpha :: proc(pixels: []u8) {
	for i := 0; i + 3 < len(pixels); i += 4 {
		a := u32(pixels[i + 3])
		if a == 255 {
			continue
		}
		pixels[i + 0] = u8((u32(pixels[i + 0]) * a + 127) / 255)
		pixels[i + 1] = u8((u32(pixels[i + 1]) * a + 127) / 255)
		pixels[i + 2] = u8((u32(pixels[i + 2]) * a + 127) / 255)
	}
}

@(private = "package")
premultiplied_copy :: proc(pixels: []u8) -> []u8 {
	out := make([]u8, len(pixels))
	copy(out, pixels)
	premultiply_alpha(out)
	return out
}

// Divide RGB by alpha in place (the inverse of premultiply_alpha, exact for
// opaque pixels and within rounding elsewhere). Fully transparent pixels
// carry no colour and come out as zero.
@(private = "package")
unpremultiply_alpha :: proc(pixels: []u8) {
	for i := 0; i + 3 < len(pixels); i += 4 {
		a := u32(pixels[i + 3])
		if a == 255 {
			continue
		}
		if a == 0 {
			pixels[i + 0], pixels[i + 1], pixels[i + 2] = 0, 0, 0
			continue
		}
		pixels[i + 0] = u8(min((u32(pixels[i + 0]) * 255 + a / 2) / a, 255))
		pixels[i + 1] = u8(min((u32(pixels[i + 1]) * 255 + a / 2) / a, 255))
		pixels[i + 2] = u8(min((u32(pixels[i + 2]) * 255 + a / 2) / a, 255))
	}
}

// Destroy a texture and free its GPU resources.
destroy_texture :: proc(tex: ^Texture) {
	ctx.renderer.destroy_texture(tex.handle)
	tex.handle = {}
	tex.width = 0
	tex.height = 0
}
