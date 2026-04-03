// Scissor rect example — demonstrates clipping draw calls to a rectangular region.
//
//   odin run examples/scissor
//   odin run tools/build_web -- examples/scissor --serve
package main

import "core:math"

import w "../.."

time: f32

main :: proc() {
	w.init(1280, 720, "Scissor Rect")
	w.run(init, frame, shutdown)
}

init :: proc() {}
shutdown :: proc() {}

frame :: proc(dt: f32) {
	time += dt
	w.clear(w.DARK_GRAY)

	clip := w.Rect{100, 100, 500, 400}

	// Draw the scissor region outline (before scissor is active).
	w.draw_text("Clipped region:", {100, 72}, 20, w.WHITE)
	w.draw_rect_outline(clip, 2, w.WHITE)

	// Activate scissor — all drawing is now clipped to this rectangle.
	w.set_scissor_rect(clip)

	// Background fill for the clipped area.
	w.draw_rect(clip, {30, 30, 40, 255})

	// Shapes that extend beyond the clip boundary.
	w.draw_rect({50, 120, 600, 80}, w.BLUE) // extends left and right
	w.draw_rect({150, 250, 200, 350}, w.DARK_GREEN) // extends below

	// Animated circle crossing the scissor boundary.
	cx := 350 + math.cos(time) * 300
	cy := 300 + math.sin(time * 0.7) * 250
	w.draw_circle({cx, cy}, 60, w.RED, 32)

	// Shapes at corners — partially visible.
	w.draw_circle({100, 100}, 50, w.PURPLE, 24) // top-left corner
	w.draw_rect({420, 360, 300, 200}, w.ORANGE) // bottom-right corner

	w.draw_text("This text is clipped at the edges of the rectangle", {110, 470}, 18, w.WHITE)

	// Done with scissor.
	w.reset_scissor_rect()

	// Draw outside the scissor area to prove it is no longer clipping.
	w.draw_text("Not clipped:", {700, 100}, 20, w.WHITE)
	w.draw_rect({700, 130, 200, 150}, w.GREEN)
	w.draw_circle({800, 400}, 80, w.YELLOW, 32)

	w.draw_text(
		"Shapes are clipped to the white rectangle. The circle animates across the boundary.",
		{100, 530},
		18,
		w.LIGHT_GRAY,
	)

	w.draw_stats()
	w.present()
}
