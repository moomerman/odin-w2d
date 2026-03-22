// Mouse input example — a rectangle follows the cursor and changes color on click.
// Demonstrates cursor visibility toggling, system cursor shapes, and custom cursors.
package main

import w "../.."

RECT_SIZE :: 60

scroll_y: f32
color: w.Color
cursor_hidden: bool
cursor_index: int

cursors := [?]w.System_Cursor {
	.Default,
	.Text,
	.Crosshair,
	.Pointer,
	.Resize_EW,
	.Resize_NS,
	.Resize_NWSE,
	.Resize_NESW,
	.Move,
	.Not_Allowed,
}

cursor_names := [?]string {
	"Default",
	"Text",
	"Crosshair",
	"Pointer",
	"Resize_EW",
	"Resize_NS",
	"Resize_NWSE",
	"Resize_NESW",
	"Move",
	"Not_Allowed",
}

main :: proc() {
	color = w.BLUE
	w.init(1280, 720, "Mouse Input Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	// Start with crosshair cursor.
	cursor_index = 2
	w.set_cursor(.Crosshair)
}

frame :: proc(dt: f32) {
	if w.mouse_button_is_held(.Left) {
		color = w.RED
	} else if w.mouse_button_is_held(.Right) {
		color = w.GREEN
	} else {
		color = w.BLUE
	}

	// Press H to toggle cursor visibility.
	if w.key_went_down(.H) {
		cursor_hidden = !cursor_hidden
		if cursor_hidden {
			w.hide_cursor()
		} else {
			w.show_cursor()
		}
	}

	// Press C to cycle through system cursors.
	if w.key_went_down(.C) {
		cursor_index = (cursor_index + 1) % len(cursors)
		w.set_cursor(cursors[cursor_index])
	}

	// Press X to set a custom 16x16 cursor (white square with red center).
	if w.key_went_down(.X) {
		pixels: [16 * 16 * 4]u8
		for y in 0 ..< 16 {
			for x in 0 ..< 16 {
				i := (y * 16 + x) * 4
				if x >= 6 && x <= 9 && y >= 6 && y <= 9 {
					pixels[i] = 255 // R
					pixels[i + 1] = 0 // G
					pixels[i + 2] = 0 // B
				} else {
					pixels[i] = 255 // R
					pixels[i + 1] = 255 // G
					pixels[i + 2] = 255 // B
				}
				pixels[i + 3] = 255 // A
			}
		}
		w.set_custom_cursor(pixels[:], 16, 16, 8, 8)
	}

	pos := w.get_mouse_position()
	delta := w.get_mouse_delta()
	scroll := w.get_scroll_delta(include_momentum = false)
	scroll_y += scroll.y

	w.clear(w.DARK_GRAY)

	// Draw a rectangle centered on the cursor, scaled by scroll wheel.
	scale := clamp(1.0 + scroll_y * 0.1, 0.2, 5.0)
	size := f32(RECT_SIZE) * scale
	w.draw_rect({pos.x - size / 2, pos.y - size / 2, size, size}, color)

	// Draw a small crosshair at the exact cursor position.
	w.draw_rect({pos.x - 10, pos.y - 1, 20, 2}, w.WHITE)
	w.draw_rect({pos.x - 1, pos.y - 10, 2, 20}, w.WHITE)

	// Show delta as a trailing indicator — a small dot offset by the delta.
	if delta.x != 0 || delta.y != 0 {
		w.draw_rect({pos.x - delta.x * 3 - 3, pos.y - delta.y * 3 - 3, 6, 6}, w.YELLOW)
	}

	// HUD: show current cursor info.
	w.draw_text(cursor_names[cursor_index], {10, 10}, 16, w.WHITE)
	w.draw_text(cursor_hidden ? "Hidden (H)" : "Visible (H)", {10, 30}, 16, w.WHITE)
	w.draw_text("C: cycle cursor  X: custom cursor  Scroll: resize", {10, 50}, 16, w.LIGHT_GRAY)

	w.present()
}

shutdown :: proc() {}
