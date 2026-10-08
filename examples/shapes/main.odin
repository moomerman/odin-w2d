// odin run examples/shapes
// odin run tools/build_web -- examples/shapes --serve
//
// Primitives: circles, triangles, rotated rects, rounded rects, ellipses,
// polylines, Béziers, arcs, gradients, and the transform stack.
package main

import "core:math"

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

	// Row 1: circles, outlines, triangles.
	w.draw_text("Circles", {40, 20}, 20, w.WHITE)
	w.draw_circle({120, 130}, 70, w.BLUE)
	w.draw_circle({120, 130}, 35, w.LIGHT_BLUE)
	w.draw_circle_outline({300, 130}, 70, 4, w.GREEN)
	w.draw_circle_outline({300, 130}, 45, 8, w.DARK_GREEN, 32)

	w.draw_text("Triangles", {440, 20}, 20, w.WHITE)
	w.draw_triangle({{520, 70}, {600, 200}, {440, 200}}, w.RED)
	w.draw_triangle({{640, 200}, {720, 70}, {800, 200}}, w.ORANGE)

	// Rounded rects, ellipse, polygon.
	w.draw_text("Rounded, ellipse, polygon", {860, 20}, 20, w.WHITE)
	w.draw_rounded_rect({860, 60, 150, 80}, 16, w.PURPLE)
	w.draw_rounded_rect_outline({860, 150, 150, 50}, 12, 3, w.YELLOW)
	w.draw_ellipse({1100, 100}, 70, 40, w.MAGENTA)
	hexagon: [6]w.Vec2
	for i in 0 ..< 6 {
		a := f32(i) / 6 * math.TAU
		hexagon[i] = {1100 + math.cos(a) * 36, 175 + math.sin(a) * 36}
	}
	w.draw_polygon(hexagon[:], w.LIGHT_GRAY)

	// Row 2: rotating rects (draw_rect_ex) next to the same thing done with
	// the transform stack, which also carries the text along.
	w.draw_text("draw_rect_ex", {40, 240}, 20, w.WHITE)
	rect := w.Rect{80, 300, 160, 100}
	w.draw_rect_ex(rect, {80, 50}, time, w.PURPLE)
	w.draw_circle({rect.x + 80, rect.y + 50}, 4, w.WHITE)

	w.draw_text("push_transform", {330, 240}, 20, w.WHITE)
	w.push_transform({440, 350}, rotation = -time * 0.7, scale = {1.2, 1.2}, origin = {60, 35})
	w.draw_rounded_rect({0, 0, 120, 70}, 10, w.BLUE)
	w.draw_rect_outline({0, 0, 120, 70}, 2, w.LIGHT_BLUE)
	w.draw_text("local", {30, 25}, 18, w.WHITE)
	// Nested: a satellite orbiting in the group's local space.
	w.push_transform({60, 35}, rotation = time * 3)
	w.draw_circle({90, 0}, 10, w.YELLOW)
	w.pop_transform()
	w.pop_transform()

	// Strokes: polyline, Bézier, arc.
	w.draw_text("Polyline, Bezier, arc", {620, 240}, 20, w.WHITE)
	w.draw_polyline({{620, 300}, {680, 360}, {740, 300}, {800, 360}}, 8, w.GREEN)
	w.draw_bezier({620, 420}, {700, 300}, {760, 480}, {840, 380}, 5, w.ORANGE)
	w.draw_arc({920, 360}, 50, math.PI, math.PI * 1.75 + math.sin(time) * 0.2, 6, w.RED)

	// Row 3: gradients from per-vertex colour, and a glow with no texture.
	w.draw_text("Gradients", {40, 460}, 20, w.WHITE)
	w.draw_rect_gradient_v({40, 500, 200, 100}, w.LIGHT_BLUE, w.DARK_BLUE)
	w.draw_rect_gradient_h({260, 500, 200, 100}, w.RED, w.YELLOW)
	w.draw_rect_gradient({480, 500, 200, 100}, w.RED, w.GREEN, w.BLUE, w.WHITE)

	w.draw_text("Glow (additive gradient)", {740, 460}, 20, w.WHITE)
	w.set_blend_mode(.Additive)
	w.draw_circle_gradient({860, 560}, 90, {255, 120, 40, 200}, {255, 120, 40, 0}, 48)
	w.reset_blend_mode()
	w.draw_circle({860, 560}, 14, w.ORANGE)
	// Round shadow: alpha fades to zero at the rim.
	w.draw_circle_gradient({1060, 580}, 60, {0, 0, 0, 160}, {0, 0, 0, 0}, 48)
	w.draw_circle({1050, 560}, 40, w.LIGHT_GRAY)

	w.draw_stats()
	w.present()
}

shutdown :: proc() {}
