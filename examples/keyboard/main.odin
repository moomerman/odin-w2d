// Keyboard input example — move a rectangle with WASD/arrow keys, change color on key press.
package main

import w "../.."

RECT_SIZE :: 40
SPEED :: 200

pos: w.Vec2
color: w.Color

main :: proc() {
	w.init(1280, 720, "Keyboard Input Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	pos = {620, 340}
	color = w.BLUE
}

frame :: proc(dt: f32) {
	// Change color on key press.
	if w.key_went_down(.Space) do color = w.PURPLE
	if w.key_went_down(.Return) do color = w.BLUE

	// Move with WASD or arrow keys.
	move: w.Vec2
	if w.key_is_held(.W) || w.key_is_held(.Up) do move.y -= 1
	if w.key_is_held(.S) || w.key_is_held(.Down) do move.y += 1
	if w.key_is_held(.A) || w.key_is_held(.Left) do move.x -= 1
	if w.key_is_held(.D) || w.key_is_held(.Right) do move.x += 1
	pos += move * SPEED * dt

	w.clear(w.DARK_GRAY)
	w.draw_rect({pos.x - RECT_SIZE / 2, pos.y - RECT_SIZE / 2, RECT_SIZE, RECT_SIZE}, color)

	// Draw a small indicator when shift is held.
	if w.key_is_held(.Left_Shift) || w.key_is_held(.Right_Shift) {
		w.draw_rect({pos.x - 5, pos.y - RECT_SIZE / 2 - 12, 10, 8}, w.YELLOW)
	}

	w.present()
}

shutdown :: proc() {}
