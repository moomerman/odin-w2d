// Gamepad input example — drive a ship with the sticks, recolor it with the
// face buttons, watch the triggers as fill bars, and rumble on button press.
// Player one is gamepad slot 0; connected controllers are listed bottom-left.
package main

import "core:fmt"
import "core:math"

import w "../.."

PAD :: w.Gamepad_Index(0)

// Below this magnitude the left stick is treated as centered, so a slightly
// off-center resting stick doesn't drift the ship.
DEADZONE :: 0.20
SPEED :: 300
SHIP :: 22

pos: w.Vec2
heading: f32 // radians, aimed by the right stick
color: w.Color

main :: proc() {
	w.init(1280, 720, "Gamepad Example")
	w.init_gamepad() // opt-in; call before run()
	w.run(init, frame, shutdown)
}

init :: proc() {
	pos = {640, 360}
	color = w.LIGHT_BLUE
}

frame :: proc(dt: f32) {
	w.clear(w.DARK_GRAY)

	if !w.is_gamepad_connected(PAD) {
		msg := "Connect a controller to play"
		size := w.measure_text(msg, 28)
		w.draw_text(msg, {640 - size.x / 2, 340}, 28, w.WHITE)
		draw_connected_list()
		w.present()
		return
	}

	// Move with the left stick, applying a radial deadzone.
	stick := w.Vec2{w.get_gamepad_axis(PAD, .Left_X), w.get_gamepad_axis(PAD, .Left_Y)}
	if linalg_len(stick) > DEADZONE {
		pos += stick * SPEED * dt
	}
	pos.x = clamp(pos.x, SHIP, 1280 - SHIP)
	pos.y = clamp(pos.y, SHIP, 720 - SHIP)

	// Aim with the right stick (only when pushed past the deadzone).
	aim := w.Vec2{w.get_gamepad_axis(PAD, .Right_X), w.get_gamepad_axis(PAD, .Right_Y)}
	if linalg_len(aim) > DEADZONE {
		heading = math.atan2(aim.y, aim.x)
	}

	// Recolor with the face buttons (labelled by position, vendor-neutral).
	if w.gamepad_button_went_down(PAD, .South) do color = w.GREEN
	if w.gamepad_button_went_down(PAD, .East) do color = w.RED
	if w.gamepad_button_went_down(PAD, .West) do color = w.BLUE
	if w.gamepad_button_went_down(PAD, .North) do color = w.YELLOW

	// Rumble while either shoulder is held; intensity scales with the matching
	// trigger so you can feel the analog value. Called every frame to sustain it.
	lt := w.get_gamepad_axis(PAD, .Left_Trigger)
	rt := w.get_gamepad_axis(PAD, .Right_Trigger)
	if w.gamepad_button_is_held(PAD, .Left_Shoulder) ||
	   w.gamepad_button_is_held(PAD, .Right_Shoulder) {
		w.set_gamepad_vibration(PAD, lt, rt)
	} else {
		w.set_gamepad_vibration(PAD, 0, 0)
	}

	draw_ship()
	draw_trigger_bar({40, 660}, "LT", lt)
	draw_trigger_bar({160, 660}, "RT", rt)
	draw_dpad({1180, 620})
	draw_connected_list()

	w.present()
}

shutdown :: proc() {}

draw_ship :: proc() {
	// Body as a rotated rect, with a nose triangle pointing along `heading`.
	w.draw_rect_ex({pos.x, pos.y, SHIP * 2, SHIP * 1.4}, {SHIP, SHIP * 0.7}, heading, color)
	nose := pos + {math.cos(heading), math.sin(heading)} * (SHIP + 10)
	w.draw_circle(nose, 6, w.WHITE)
}

draw_trigger_bar :: proc(at: w.Vec2, label: string, value: f32) {
	w.draw_text(label, at, 18, w.LIGHT_GRAY)
	track := w.Rect{at.x, at.y + 22, 80, 14}
	w.draw_rect(track, w.BLACK)
	w.draw_rect({track.x, track.y, track.w * value, track.h}, w.ORANGE)
	w.draw_rect_outline(track, 1, w.LIGHT_GRAY)
}

draw_dpad :: proc(center: w.Vec2) {
	cell :: f32(22)
	dirs := [4]struct {
		button: w.Gamepad_Button,
		offset: w.Vec2,
	}{{.Dpad_Up, {0, -1}}, {.Dpad_Down, {0, 1}}, {.Dpad_Left, {-1, 0}}, {.Dpad_Right, {1, 0}}}
	for d in dirs {
		r := w.Rect {
			center.x + d.offset.x * cell - cell / 2,
			center.y + d.offset.y * cell - cell / 2,
			cell - 2,
			cell - 2,
		}
		on := w.gamepad_button_is_held(PAD, d.button)
		w.draw_rect(r, on ? w.WHITE : w.GRAY)
	}
}

draw_connected_list :: proc() {
	y: f32 = 10
	for i in 0 ..< w.MAX_GAMEPADS {
		slot := w.Gamepad_Index(i)
		line: string
		if w.is_gamepad_connected(slot) {
			line = fmt.tprintf("Player %d: %s", i + 1, w.get_gamepad_name(slot))
		} else {
			line = fmt.tprintf("Player %d: -", i + 1)
		}
		w.draw_text(line, {10, y}, 16, w.LIGHT_GRAY)
		y += 20
	}
}

// Length of a 2D vector. (Kept local to avoid pulling core:math/linalg into the
// example just for one call.)
linalg_len :: proc(v: w.Vec2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}
