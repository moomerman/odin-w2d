// https://gist.github.com/Falconerd/7ecfd7112121be2a2a72f57c7bd38b0a
package main

import "core:math/linalg"
import rl "vendor:raylib"

Vec2 :: rl.Vector2
Rect :: rl.Rectangle
Color :: rl.Color

BG :: Color{0, 0, 0x1C, 0xFF}
FG :: Color{0, 0xDF, 0, 0xFF}
FADED :: Color{0, 0xDF, 0, 0x44}

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

MOVING_RECT_SIZE :: Vec2{90, 140}

SCREEN_CENTER :: Vec2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2}

ITERATIONS :: 8

main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "AABB Continuous")

	static_rects: [dynamic]Rect

	append(&static_rects, Rect{200, 200, 200, 300})
	append(&static_rects, Rect{400, 200, 200, 300})
	append(&static_rects, Rect{200, 500, 200, 300})
	append(&static_rects, Rect{800, 500, 40, 300})

	old_position: Vec2

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(BG)

		mouse_position := rl.GetMousePosition()

		if rl.IsMouseButtonPressed(.LEFT) {
			old_position = mouse_position
		}

		old_rect := rect_from_pos_size(old_position - MOVING_RECT_SIZE / 2, MOVING_RECT_SIZE)
		moving_rect := rect_from_pos_size(mouse_position - MOVING_RECT_SIZE / 2, MOVING_RECT_SIZE)

		rl.DrawRectangleLinesEx(old_rect, 4, rl.GRAY)
		rl.DrawRectangleLinesEx(moving_rect, 4, rl.WHITE)

		rl.DrawLineEx(rect_center(moving_rect), rect_center(old_rect), 4, FADED)

		for static_rect in static_rects {
			rl.DrawRectangleLinesEx(static_rect, 4, rl.WHITE)

			expanded_rect := aabb_sum(static_rect, moving_rect)

			rl.DrawRectangleLinesEx(expanded_rect, 2, {255, 0, 0, 80})
		}

		// ---- STATIC PASS ----
		for static_rect in static_rects {
			if aabb_intersects_aabb(old_rect, static_rect) {
				overlap := get_overlap(old_rect, static_rect)

				EPSILON :: 0.001

				if overlap.width < overlap.height {
					// x axis
					if old_rect.x < static_rect.x {
						old_rect.x -= overlap.width + EPSILON
					} else {
						old_rect.x += overlap.width + EPSILON
					}
				} else {
					// y axis
					if old_rect.y < static_rect.y {
						old_rect.y -= overlap.height + EPSILON
					} else {
						old_rect.y += overlap.height + EPSILON
					}
				}

			}
		}

		// ---- FIRST PASS ----
		velocity := rect_center(moving_rect) - rect_center(old_rect)

		hit, did_hit := sweep_multi(old_rect, static_rects[:], velocity)

		if did_hit {
			intermediate_rect := moving_rect
			intermediate_rect.x = hit.position.x - moving_rect.width / 2
			intermediate_rect.y = hit.position.y - moving_rect.height / 2

			rl.DrawRectangleLinesEx(intermediate_rect, 2, rl.YELLOW)

			// ---- SECOND PASS (SLIDE) ----
			full_length := rl.Vector2Length(velocity)
			remaining_length := (full_length - hit.tmin)
			slide_direction := rl.Vector2Normalize(velocity)

			if hit.normal.x != 0 do slide_direction.x = 0
			if hit.normal.y != 0 do slide_direction.y = 0

			remaining_velocity := slide_direction * remaining_length

			hit, did_hit = sweep_multi(intermediate_rect, static_rects[:], remaining_velocity)
			if did_hit {
				intermediate_rect.x = hit.position.x - moving_rect.width / 2
				intermediate_rect.y = hit.position.y - moving_rect.height / 2
				rl.DrawRectangleLinesEx(intermediate_rect, 2, rl.RED)
			} else {
				intermediate_rect.x += remaining_velocity.x
				intermediate_rect.y += remaining_velocity.y
				rl.DrawRectangleLinesEx(intermediate_rect, 2, rl.RED)
			}
		}

		rl.EndDrawing()
	}
}

Hit :: struct {
	tmin:     f32,
	position: Vec2,
	normal:   Vec2,
}

sweep_multi :: proc(
	moving_rect: Rect,
	static_rects: []Rect,
	velocity: Vec2,
) -> (
	hit: Hit,
	did_hit: bool,
) {
	hit.tmin = max(f32)

	start := rect_center(moving_rect)
	rl.DrawLineEx(start, start + velocity, 2, rl.YELLOW)

	for static_rect in static_rects {
		if new_hit, ok := sweep(moving_rect, static_rect, velocity); ok {
			if new_hit.tmin > hit.tmin do continue
			hit = new_hit
			did_hit = true
		}
	}

	return hit, did_hit
}

sweep :: proc(moving_rect, static_rect: Rect, velocity: Vec2) -> (hit: Hit, did_hit: bool) {
	EPSILON :: 0.001
	direction := rl.Vector2Normalize(velocity)

	moving_rect_center := rect_center(moving_rect)
	static_rect_center := rect_center(static_rect)
	static_rect_expanded := aabb_sum(static_rect, moving_rect)

	length := rl.Vector2Length(velocity)

	tmin, hit_point := intersect_ray_aabb(
		moving_rect_center,
		direction,
		static_rect_expanded,
	) or_return

	if tmin > length {
		return
	}

	if tmin < 0 {
		return
	}

	hit_point -= direction * EPSILON

	hit.position = hit_point
	hit.tmin = tmin

	expanded_half_size := Vec2{static_rect_expanded.width, static_rect_expanded.height} / 2

	d := hit.position - static_rect_center
	p := expanded_half_size - linalg.abs(d)

	if p.x < p.y {
		hit.normal.x = 1 if d.x > 0 else -1
	} else {
		hit.normal.y = 1 if d.y > 0 else -1
	}

	return hit, true
}

intersect_ray_aabb :: proc(
	origin, direction: Vec2,
	aabb: Rect,
) -> (
	tmin: f32,
	hit_point: Vec2,
	did_hit: bool,
) {
	EPSILON :: 0.001

	tmax := max(f32)

	// Compute the slabs
	amin := Vec2{aabb.x, aabb.y}
	amax := amin + {aabb.width, aabb.height}

	// rl.DrawLineEx({0, amin.y}, {WINDOW_WIDTH, amin.y}, 4, {0, 255, 0, 80})
	// rl.DrawLineEx({amin.x, 0}, {amin.x, WINDOW_HEIGHT}, 4, {0, 255, 0, 80})

	// rl.DrawLineEx({0, amax.y}, {WINDOW_WIDTH, amax.y}, 4, {255, 0, 255, 80})
	// rl.DrawLineEx({amax.x, 0}, {amax.x, WINDOW_HEIGHT}, 4, {255, 0, 255, 80})

	for i in 0 ..< 2 { 	// X and Y (also works with N-dimensions)
		// Check parallel
		if abs(direction[i]) < EPSILON {
			if origin[i] < amin[i] || origin[i] > amax[i] {
				// Origin not within slab
				return
			}
		} else {
			// Compute intersection of near and far-plane of slab
			ood := 1 / direction[i]
			t1 := (amin[i] - origin[i]) * ood
			t2 := (amax[i] - origin[i]) * ood

			// rl.DrawCircleV(origin + t1 * direction, 8, rl.GREEN)
			// rl.DrawCircleV(origin + t2 * direction, 8, rl.MAGENTA)

			// Make t1 always be near-plane
			// as rays traveling negatively may enter the far-plane first
			if t1 > t2 {
				t1, t2 = t2, t1 // swap
			}

			tmin = max(tmin, t1)
			tmax = min(tmax, t2)

			if tmin > tmax {
				return
			}
		}
	}

	// rl.DrawCircleV(origin + tmin * direction, 8, rl.YELLOW)
	// rl.DrawCircleV(origin + tmax * direction, 8, rl.RED)

	hit_point = origin + direction * tmin
	return tmin, hit_point, true
}

aabb_sum :: proc(a, b: Rect) -> Rect {
	result := a
	result.x -= b.width / 2
	result.y -= b.height / 2
	result.width += b.width
	result.height += b.height
	return result
}

get_overlap :: proc(a, b: Rect) -> Rect {
	x := max(a.x, b.x)
	y := max(a.y, b.y)
	z := min(a.x + a.width, b.x + b.width)
	w := min(a.y + a.height, b.y + b.height)
	return Rect{x, y, z - x, w - y}
}

aabb_intersects_aabb :: proc(a, b: Rect) -> bool {
	if a.x >= b.x + b.width do return false // too far right
	if a.y >= b.y + b.height do return false // too far down
	if a.x + a.width <= b.x do return false // too far left
	if a.y + a.height <= b.y do return false // too far up
	return true
}

rect_from_pos_size :: proc(pos, size: Vec2) -> Rect {
	return Rect{pos.x, pos.y, size.x, size.y}
}

rect_center :: proc(rect: Rect) -> Vec2 {
	return {rect.x + rect.width / 2, rect.y + rect.height / 2}
}
