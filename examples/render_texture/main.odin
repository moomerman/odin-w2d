// Render texture example — draw a spinning scene into an offscreen texture,
// then display it multiple times on screen with different sizes and tints.
//
// odin run examples/render_texture
// odin run tools/build_web -- examples/render_texture --serve
package main

import "core:math"

import w "../.."

rt: w.Render_Texture
time: f32

RT_SIZE :: 256

main :: proc() {
	w.init(1280, 720, "Render Texture Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	rt = w.create_render_texture(RT_SIZE, RT_SIZE)
}

frame :: proc(dt: f32) {
	time += dt

	// Start the frame — clear must be called before set_render_texture
	// because it initialises the command encoder for the frame.
	w.clear(w.Color{30, 30, 30, 255})

	// --- Draw into the render texture ---
	w.set_render_texture(rt, w.Color{20, 20, 40, 255})

	// Spinning shapes inside the render texture
	center := w.Vec2{RT_SIZE / 2, RT_SIZE / 2}
	for i in 0 ..< 6 {
		angle := time + f32(i) * (math.TAU / 6)
		pos := w.Vec2{center.x + math.cos(angle) * 70, center.y + math.sin(angle) * 70}
		w.draw_circle(pos, 20, color_for_index(i))
	}

	// Center circle
	w.draw_circle(center, 30, w.WHITE)

	// Rotating rect
	w.draw_rect_ex(
		{center.x - 50, center.y - 50, 100, 100},
		{50, 50},
		time * 0.5,
		w.Color{255, 255, 255, 40},
	)

	// --- Resume drawing to the screen ---
	w.reset_render_texture()

	// Draw the render texture at original size
	w.draw_texture(rt.texture, {40, 40})
	w.draw_text("1x", {40, 310}, 20, w.LIGHT_GRAY)

	// Draw it scaled up
	w.draw_texture_rect(rt.texture, {0, 0, RT_SIZE, RT_SIZE}, {340, 40, 400, 400})
	w.draw_text("Scaled up", {340, 450}, 20, w.LIGHT_GRAY)

	// Draw it tinted
	w.draw_texture_rect(
		rt.texture,
		{0, 0, RT_SIZE, RT_SIZE},
		{780, 40, 200, 200},
		w.Color{255, 100, 100, 255},
	)
	w.draw_text("Red tint", {780, 250}, 20, w.LIGHT_GRAY)

	w.draw_texture_rect(
		rt.texture,
		{0, 0, RT_SIZE, RT_SIZE},
		{780, 290, 200, 200},
		w.Color{100, 200, 255, 255},
	)
	w.draw_text("Blue tint", {780, 500}, 20, w.LIGHT_GRAY)

	// Draw it small, tiled
	for row in 0 ..< 4 {
		for col in 0 ..< 4 {
			x := f32(40 + col * 70)
			y := f32(480 + row * 70)
			w.draw_texture_rect(rt.texture, {0, 0, RT_SIZE, RT_SIZE}, {x, y, 64, 64})
		}
	}
	w.draw_text("Tiled", {40, 770 - 70}, 20, w.LIGHT_GRAY)

	w.draw_stats()
	w.present()
}

shutdown :: proc() {
	w.destroy_render_texture(&rt)
}

color_for_index :: proc(i: int) -> w.Color {
	colors := [6]w.Color{w.RED, w.ORANGE, w.YELLOW, w.GREEN, w.BLUE, w.PURPLE}
	return colors[i % len(colors)]
}
