// AABB discrete collision example — ported from a raylib demo.
//
// Click to set the anchor position. Move the mouse to see collision resolution
// against the static rectangles.
//
// odin run examples/collisions
// odin run tools/build_web -- examples/collisions --serve
package main

import w "../.."
import "core:math"

Vec2 :: w.Vec2
Rect :: w.Rect
Color :: w.Color

BG :: Color{0, 0, 0x1C, 0xFF}
FG :: Color{0, 0xDF, 0, 0xFF}
FADED :: Color{0, 0xDF, 0, 0x44}

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

MOVING_RECT_SIZE :: Vec2{90, 140}

SCREEN_CENTER :: Vec2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2}

static_rects: [dynamic]Rect
old_position: Vec2

main :: proc() {
	w.init(WINDOW_WIDTH, WINDOW_HEIGHT, "AABB Discrete Collisions")
	w.run(init, frame, shutdown)
}

init :: proc() {
	old_position = SCREEN_CENTER

	append(&static_rects, Rect{200, 200, 200, 300})
	append(&static_rects, Rect{400, 200, 200, 300})
	append(&static_rects, Rect{200, 500, 200, 300})
	append(&static_rects, Rect{800, 500, 40, 300})
}

frame :: proc(dt: f32) {
	w.clear(BG)

	mouse_position := w.get_mouse_position()

	if w.mouse_button_went_down(.Left) {
		old_position = mouse_position
	}

	old_rect := rect_from_pos_size(old_position - MOVING_RECT_SIZE / 2, MOVING_RECT_SIZE)
	moving_rect := rect_from_pos_size(mouse_position - MOVING_RECT_SIZE / 2, MOVING_RECT_SIZE)

	// Draw the anchor rect outline and the moving rect outline.
	w.draw_rect_outline(old_rect, 4, w.GRAY)
	w.draw_rect_outline(moving_rect, 4, w.WHITE)

	// Draw velocity line from moving rect center to old rect center.
	w.draw_line(rect_center(moving_rect), rect_center(old_rect), 4, FADED)

	// Draw static obstacles.
	for static_rect in static_rects {
		w.draw_rect_outline(static_rect, 4, w.WHITE)
	}

	// Compute resolved position and draw the result.
	velocity := rect_center(moving_rect) - rect_center(old_rect)
	next_position := compute_next_position(old_rect, static_rects[:], velocity)
	w.draw_rect(rect_from_pos_size(next_position, MOVING_RECT_SIZE), w.RED)

	w.present()
}

shutdown :: proc() {
	delete(static_rects)
}

compute_next_position :: proc(moving: Rect, statics: []Rect, v: Vec2) -> Vec2 {
	next_rect := moving
	iterations := vec2_length(v)
	if iterations < 0.001 {
		return {next_rect.x, next_rect.y}
	}
	step := v / iterations

	for _ in 0 ..< i32(iterations) {
		next_rect.x += step.x
		next_rect.y += step.y
		w.draw_rect(next_rect, FADED)

		for static_rect in statics {
			if aabb_intersects_aabb(next_rect, static_rect) {
				w.draw_rect_outline(static_rect, 4, FG)

				overlap := get_overlap(next_rect, static_rect)

				if overlap.w < overlap.h {
					// Resolve on x axis.
					if next_rect.x < static_rect.x {
						next_rect.x -= overlap.w
					} else {
						next_rect.x += overlap.w
					}
					step.x = 0
				} else {
					// Resolve on y axis.
					if next_rect.y < static_rect.y {
						next_rect.y -= overlap.h
					} else {
						next_rect.y += overlap.h
					}
					step.y = 0
				}
			}
		}
	}

	return {next_rect.x, next_rect.y}
}

get_overlap :: proc(a, b: Rect) -> Rect {
	x := max(a.x, b.x)
	y := max(a.y, b.y)
	z := min(a.x + a.w, b.x + b.w)
	ww := min(a.y + a.h, b.y + b.h)
	return Rect{x, y, z - x, ww - y}
}

aabb_intersects_aabb :: proc(a, b: Rect) -> bool {
	if a.x >= b.x + b.w do return false
	if a.y >= b.y + b.h do return false
	if a.x + a.w <= b.x do return false
	if a.y + a.h <= b.y do return false
	return true
}

rect_from_pos_size :: proc(pos, size: Vec2) -> Rect {
	return Rect{pos.x, pos.y, size.x, size.y}
}

rect_center :: proc(rect: Rect) -> Vec2 {
	return {rect.x + rect.w / 2, rect.y + rect.h / 2}
}

vec2_length :: proc(v: Vec2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}
