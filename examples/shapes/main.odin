// odin run examples/shapes
// odin run tools/build_web -- examples/shapes --serve
package main

import w "../.."

time: f32

main :: proc() {
	w.init(1280, 720, "Shapes Example")
	w.run(init, frame, shutdown)
}

init :: proc() {}

frame :: proc(dt: f32) {
	time += dt
	w.clear(w.DARK_GRAY)

	// Filled circles
	w.draw_circle({200, 150}, 80, w.BLUE)
	w.draw_circle({200, 150}, 40, w.LIGHT_BLUE)

	// Circle outline
	w.draw_circle_outline({450, 150}, 80, 4, w.GREEN)
	w.draw_circle_outline({450, 150}, 50, 8, w.DARK_GREEN, 32)

	// Triangles
	w.draw_triangle({{700, 80}, {780, 220}, {620, 220}}, w.RED)
	w.draw_triangle({{900, 220}, {980, 80}, {1060, 220}}, w.ORANGE)

	// Rotating rectangle (rotates around its center)
	rect := w.Rect{500, 400, 200, 120}
	origin := w.Vec2{100, 60}
	w.draw_rect_ex(rect, origin, time, w.PURPLE)
	// Draw a small dot at the rotation center for reference
	w.draw_circle({rect.x + origin.x, rect.y + origin.y}, 4, w.WHITE)

	// Rotating rectangle (rotates around a corner)
	rect2 := w.Rect{200, 450, 120, 80}
	w.draw_rect_ex(rect2, {0, 0}, time * 0.7, w.BLUE)
	w.draw_circle({rect2.x, rect2.y}, 4, w.WHITE)

	// Rotating textured rect (using a procedural checkerboard via draw_rect_ex)
	rect3 := w.Rect{900, 400, 160, 160}
	origin3 := w.Vec2{80, 80}
	w.draw_rect_ex(rect3, origin3, -time * 1.3, w.YELLOW)
	w.draw_circle({rect3.x + origin3.x, rect3.y + origin3.y}, 4, w.WHITE)

	// High-segment circle for smooth appearance
	w.draw_circle({200, 600}, 60, w.MAGENTA, 64)
	w.draw_circle_outline({450, 600}, 60, 3, w.YELLOW, 64)

	// Draw some labels
	w.draw_text("Circles", {140, 20}, 20, w.WHITE)
	w.draw_text("Circle Outlines", {370, 20}, 20, w.WHITE)
	w.draw_text("Triangles", {680, 20}, 20, w.WHITE)
	w.draw_text("Rotating Rects", {300, 330}, 20, w.WHITE)
	w.draw_text("High Segments", {240, 530}, 20, w.WHITE)

	w.draw_stats()
	w.present()
}

shutdown :: proc() {}
