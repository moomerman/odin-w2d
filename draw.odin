package engine

import "core:fmt"
import "core:image"
import _ "core:image/bmp"
import _ "core:image/png"
import _ "core:image/tga"
import "core:math"

// Full UV rect for the 1x1 white texture — used by all solid-color primitives.
@(private = "file")
WHITE_UV :: [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}

// Clear the screen with a solid color. Call once at the start of each frame's drawing.
clear :: proc(color: Color) {
	ctx.renderer.begin_frame(color)
	// Re-apply camera view_projection in case the projection was reset by a resize
	// (e.g. surface lost during begin_frame). This is a cheap 64-byte buffer write.
	if ctx.camera != nil {
		upload_view_projection()
	}
}

// Present the frame to the screen. Call once at the end of each frame's drawing.
present :: proc() {
	ctx.renderer.present()
}

// Draw a solid-colored rectangle.
draw_rect :: proc(r: Rect, color: Color) {
	white := ctx.renderer.get_white_texture()
	ctx.renderer.push_quad(r, WHITE_UV, white, color)
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
	ctx.renderer.push_quad_ex({p0, p1, p2, p3}, WHITE_UV, white, color)
}

// Draw a texture at the given position with an optional tint.
draw_texture :: proc(tex: Texture, pos: Vec2, tint: Color = WHITE) {
	dst := Rect{pos.x, pos.y, f32(tex.width), f32(tex.height)}
	ctx.renderer.push_quad(dst, WHITE_UV, tex.handle, tint)
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

	ctx.renderer.push_quad_ex(positions, WHITE_UV, white, color)
}

// Draw a texture from `src` into `dst`, rotated around `origin` by `rotation` radians.
// The origin is relative to the destination rectangle's top-left corner.
draw_texture_ex :: proc(
	tex: Texture,
	src: Rect,
	dst: Rect,
	origin: Vec2,
	rotation: f32,
	tint: Color = WHITE,
) {
	tw := f32(tex.width)
	th := f32(tex.height)
	u0 := src.x / tw
	v0 := src.y / th
	u1 := (src.x + src.w) / tw
	v1 := (src.y + src.h) / th
	uv := [4][2]f32{{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}

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

	ctx.renderer.push_quad_ex(positions, uv, tex.handle, tint)
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
		ctx.renderer.push_quad_ex({center, p1, p2, p2}, WHITE_UV, white, color)
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

		ctx.renderer.push_quad_ex(
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

// Draw a filled triangle.
draw_triangle :: proc(vertices: [3]Vec2, color: Color) {
	white := ctx.renderer.get_white_texture()
	// Degenerate quad: 4th vertex = 3rd to form a single triangle.
	ctx.renderer.push_quad_ex(
		{vertices[0], vertices[1], vertices[2], vertices[2]},
		WHITE_UV,
		white,
		color,
	)
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

// Update a sub-region of an existing texture with new RGBA8 pixel data.
update_texture :: proc(tex: Texture, data: []u8, x, y, width, height: int) {
	ctx.renderer.update_texture(tex.handle, data, x, y, width, height)
}

// Destroy a texture and free its GPU resources.
destroy_texture :: proc(tex: ^Texture) {
	ctx.renderer.destroy_texture(tex.handle)
	tex.handle = {}
	tex.width = 0
	tex.height = 0
}
