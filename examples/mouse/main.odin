// Mouse input example — a rectangle follows the cursor and changes color on click.
package main

import w "../.."

RECT_SIZE :: 60

color: w.Color

main :: proc() {
	color = w.BLUE
	w.init(1280, 720, "Mouse Input Example")
	w.run(init, frame, shutdown)
}

init :: proc() {}

frame :: proc(dt: f32) {
	if w.mouse_button_is_held(.Left) {
		color = w.RED
	} else if w.mouse_button_is_held(.Right) {
		color = w.GREEN
	} else {
		color = w.BLUE
	}

	pos := w.get_mouse_position()
	delta := w.get_mouse_delta()

	w.clear(w.DARK_GRAY)

	// Draw a rectangle centered on the cursor.
	w.draw_rect({pos.x - RECT_SIZE / 2, pos.y - RECT_SIZE / 2, RECT_SIZE, RECT_SIZE}, color)

	// Draw a small crosshair at the exact cursor position.
	w.draw_rect({pos.x - 10, pos.y - 1, 20, 2}, w.WHITE)
	w.draw_rect({pos.x - 1, pos.y - 10, 2, 20}, w.WHITE)

	// Show delta as a trailing indicator — a small dot offset by the delta.
	if delta.x != 0 || delta.y != 0 {
		w.draw_rect({pos.x - delta.x * 3 - 3, pos.y - delta.y * 3 - 3, 6, 6}, w.YELLOW)
	}

	w.present()
}

shutdown :: proc() {}
