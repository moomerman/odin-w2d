// Nav2D demo — click to pathfind around obstacles.
// Press M to toggle navmesh wireframe.
package main

import "core:math"

import w "../.."
import nav "../../.deps/github.com/moomerman/odin-navmesh"

SPEED :: 250.0
ARRIVE_DIST :: 3.0

mesh: nav.Nav_Mesh
bake_ok: bool
char_pos: [2]f32
current_path: [][2]f32
path_idx: int
show_mesh: bool

main :: proc() {
	w.init(1280, 720, "Nav2D Demo")
	w.run(init, frame, shutdown)
}

init :: proc() {
	show_mesh = true

	// Room boundary (counter-clockwise winding).
	room := [][2]f32{{40, 40}, {1240, 40}, {1240, 680}, {40, 680}}

	// Obstacles (clockwise winding).
	desk := [][2]f32{{200, 120}, {200, 250}, {400, 250}, {400, 120}}
	shelf := [][2]f32{{750, 80}, {750, 280}, {870, 280}, {870, 80}}
	couch := [][2]f32{{500, 350}, {500, 490}, {800, 490}, {800, 350}}
	table := [][2]f32{{120, 480}, {120, 610}, {360, 610}, {360, 480}}
	plant := [][2]f32{{950, 500}, {950, 620}, {1050, 620}, {1050, 500}}

	err: nav.Bake_Error
	mesh, err = nav.bake(room, {desk, shelf, couch, table, plant})
	bake_ok = err == .None

	char_pos = {80, 360}
}

frame :: proc(dt: f32) {
	w.clear({25, 25, 35, 255})

	if !bake_ok {
		w.draw_text("Navmesh bake failed!", {100, 350}, 24, w.RED)
		w.present()
		return
	}

	if w.key_went_down(.M) do show_mesh = !show_mesh

	// Click to move.
	if w.mouse_button_went_down(.Left) {
		click := w.get_mouse_position()
		target: [2]f32 = click

		if !nav.point_in_mesh(&mesh, target) {
			target = nav.nearest_point_on_mesh_boundary(&mesh, target)
		}

		if current_path != nil do delete(current_path)
		current_path = nav.find_path(&mesh, char_pos, target)
		path_idx = 0
	}

	// Follow path.
	if current_path != nil && path_idx < len(current_path) {
		wp := current_path[path_idx]
		dir := wp - char_pos
		dist := math.sqrt(nav.dot2d(dir, dir))

		if dist < ARRIVE_DIST {
			path_idx += 1
		} else {
			step := min(SPEED * dt, dist)
			char_pos += (dir / dist) * step
		}
	}

	// -- Draw --

	// Room floor.
	w.draw_rect({40, 40, 1200, 640}, {42, 46, 56, 255})

	// Navmesh wireframe.
	if show_mesh {
		for tri in mesh.triangles {
			a := mesh.vertices[tri[0]]
			b := mesh.vertices[tri[1]]
			c := mesh.vertices[tri[2]]
			w.draw_line(a, b, 1, {58, 64, 82, 255})
			w.draw_line(b, c, 1, {58, 64, 82, 255})
			w.draw_line(c, a, 1, {58, 64, 82, 255})
		}
	}

	// Obstacles.
	_draw_obstacle({200, 120, 200, 130}, "desk")
	_draw_obstacle({750, 80, 120, 200}, "shelf")
	_draw_obstacle({500, 350, 300, 140}, "couch")
	_draw_obstacle({120, 480, 240, 130}, "table")
	_draw_obstacle({950, 500, 100, 120}, "plant")

	// Room border.
	w.draw_rect_outline({40, 40, 1200, 640}, 2, {90, 98, 118, 255})

	// Path visualization.
	if current_path != nil && len(current_path) > 0 {
		path_color := w.Color{90, 180, 240, 180}

		// Line from character to next waypoint.
		if path_idx < len(current_path) {
			w.draw_line(char_pos, current_path[path_idx], 2, path_color)
		}

		// Remaining path segments.
		for i in path_idx ..< len(current_path) - 1 {
			w.draw_line(current_path[i], current_path[i + 1], 2, path_color)
		}

		// Waypoint dots.
		for i in path_idx ..< len(current_path) {
			p := current_path[i]
			w.draw_rect({p.x - 3, p.y - 3, 6, 6}, {90, 180, 240, 255})
		}

		// Target crosshair.
		goal := current_path[len(current_path) - 1]
		w.draw_line({goal.x - 10, goal.y}, {goal.x + 10, goal.y}, 2, {255, 200, 50, 255})
		w.draw_line({goal.x, goal.y - 10}, {goal.x, goal.y + 10}, 2, {255, 200, 50, 255})
	}

	// Character.
	w.draw_rect({char_pos.x - 10, char_pos.y - 10, 20, 20}, {210, 70, 50, 255})
	w.draw_rect({char_pos.x - 8, char_pos.y - 8, 16, 16}, {240, 110, 75, 255})

	// Mouse hover — green dot if walkable, red if not.
	mouse := w.get_mouse_position()
	walkable := nav.point_in_mesh(&mesh, mouse)
	dot_color := walkable ? w.Color{80, 200, 100, 200} : w.Color{200, 80, 80, 200}
	w.draw_rect({mouse.x - 2, mouse.y - 2, 4, 4}, dot_color)

	// HUD.
	w.draw_text("Click to move  |  M: toggle mesh", {50, 15}, 14, {120, 125, 140, 200})

	w.draw_stats()
	w.present()
}

shutdown :: proc() {
	if current_path != nil do delete(current_path)
	nav.destroy(&mesh)
}

@(private = "file")
_draw_obstacle :: proc(rect: w.Rect, label: string) {
	w.draw_rect(rect, {32, 35, 45, 255})
	w.draw_rect_outline(rect, 2, {72, 78, 98, 255})
	text_size := w.measure_text(label, 14)
	// w.draw_text(
	// 	label,
	// 	{rect.x + (rect.w - text_size.x) / 2, rect.y + (rect.h - text_size.y) / 2},
	// 	14,
	// 	{85, 90, 108, 255},
	// )
}
