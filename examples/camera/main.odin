// Camera example — pan, zoom, and rotate a world of colored rectangles.
// Demonstrates set_camera, screen_to_world, world_to_screen, and drawing
// UI in screen space after resetting the camera.
package main

import w "../.."

import "core:fmt"
import "core:math"

camera: w.Camera
dragging: bool
drag_start: w.Vec2

main :: proc() {
	camera.zoom = 1
	w.init(1280, 720, "Camera Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	screen_w, screen_h := w.get_screen_size()
	camera.offset = {f32(screen_w) / 2, f32(screen_h) / 2}
}

frame :: proc(dt: f32) {
	// --- Input ---

	// Arrow keys / WASD: pan
	speed: f32 = 300 / camera.zoom
	if w.key_is_held(.W) || w.key_is_held(.Up) do camera.target.y -= speed * dt
	if w.key_is_held(.S) || w.key_is_held(.Down) do camera.target.y += speed * dt
	if w.key_is_held(.A) || w.key_is_held(.Left) do camera.target.x -= speed * dt
	if w.key_is_held(.D) || w.key_is_held(.Right) do camera.target.x += speed * dt

	// Mouse drag: pan
	if w.mouse_button_went_down(.Left) {
		dragging = true
		drag_start = w.get_mouse_position()
	}
	if w.mouse_button_went_up(.Left) {
		dragging = false
	}
	if dragging {
		mouse := w.get_mouse_position()
		delta := w.Vec2{mouse.x - drag_start.x, mouse.y - drag_start.y}
		camera.target.x -= delta.x / camera.zoom
		camera.target.y -= delta.y / camera.zoom
		drag_start = mouse
	}

	// Scroll: zoom
	scroll := w.get_scroll_delta(include_momentum = false)
	if scroll.y != 0 {
		camera.zoom = clamp(camera.zoom * (1 + scroll.y * 0.1), 0.25, 10)
	}

	// Z/X: rotate
	if w.key_is_held(.Z) do camera.rotation -= 1.5 * dt
	if w.key_is_held(.X) do camera.rotation += 1.5 * dt

	// R: reset
	if w.key_went_down(.R) {
		camera.target = {0, 0}
		camera.rotation = 0
		camera.zoom = 1
	}

	// --- Draw world ---

	w.clear(w.Color{30, 30, 35, 255})
	w.set_camera(camera)

	// Grid
	for gy in -10 ..< 10 {
		for gx in -10 ..< 10 {
			x := f32(gx) * 60
			y := f32(gy) * 60
			w.draw_rect({x, y, 56, 56}, w.Color{50, 50, 55, 255})
		}
	}

	// Colored world objects
	w.draw_rect({-100, -80, 200, 160}, w.DARK_BLUE)
	w.draw_rect({-60, -40, 120, 80}, w.BLUE)
	w.draw_rect({200, 100, 80, 80}, w.RED)
	w.draw_rect({-300, 150, 120, 60}, w.GREEN)
	w.draw_rect({150, -200, 60, 120}, w.ORANGE)
	w.draw_rect({-250, -180, 100, 100}, w.PURPLE)

	// Origin crosshair
	w.draw_rect({-1, -20, 2, 40}, w.WHITE)
	w.draw_rect({-20, -1, 40, 2}, w.WHITE)

	// Mouse world position indicator
	mouse_world := w.screen_to_world(w.get_mouse_position(), camera)
	w.draw_rect({mouse_world.x - 4, mouse_world.y - 4, 8, 8}, w.YELLOW)

	// --- Draw UI (screen space) ---

	w.set_camera(nil)

	w.draw_text(
		"WASD/Arrows: pan  Scroll: zoom  Z/X: rotate  R: reset  Drag: pan",
		{10, 10},
		14,
		w.LIGHT_GRAY,
	)

	zoom_text := fmt.tprintf("Zoom: %.2f", camera.zoom)
	w.draw_text(zoom_text, {10, 30}, 14, w.WHITE)

	rot_deg := camera.rotation * (180 / math.PI)
	rot_text := fmt.tprintf("Rotation: %.1f°", rot_deg)
	w.draw_text(rot_text, {10, 48}, 14, w.WHITE)

	target_text := fmt.tprintf("Target: (%.0f, %.0f)", camera.target.x, camera.target.y)
	w.draw_text(target_text, {10, 66}, 14, w.WHITE)

	world_text := fmt.tprintf("Mouse world: (%.0f, %.0f)", mouse_world.x, mouse_world.y)
	w.draw_text(world_text, {10, 84}, 14, w.YELLOW)

	w.draw_stats()
	w.present()
}

shutdown :: proc() {}
