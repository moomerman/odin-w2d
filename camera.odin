package engine

import "core:math/linalg"

// Set the active camera. All subsequent draw calls will be transformed by the
// camera's view matrix until a different camera is set or nil is passed.
//
// Passing nil resets to identity view (screen-space drawing) — use this to draw
// UI on top of world content.
//
// The camera state persists across frames. Call set_camera once and it stays
// active until changed.
//
// Example:
//   camera := w2.Camera{ target = player_pos, offset = screen_center, zoom = 2.0 }
//   w2.set_camera(camera)
//   // draw world content...
//   w2.set_camera(nil)
//   // draw UI...
set_camera :: proc(camera: Maybe(Camera)) {
	ctx.renderer.flush()
	ctx.camera = camera
	upload_view_projection()
}

// Convert a screen-space position (e.g. mouse coordinates) to world-space,
// using the given camera transform.
screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	m := camera_world_matrix(camera)
	v := m * [4]f32{pos.x, pos.y, 0, 1}
	return {v.x, v.y}
}

// Convert a world-space position to screen-space, using the given camera transform.
world_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	m := camera_view_matrix(camera)
	v := m * [4]f32{pos.x, pos.y, 0, 1}
	return {v.x, v.y}
}

// Compute the view matrix for a camera. This transforms world coordinates to
// screen coordinates. Constructed directly (no matrix inverse needed):
//   offset_translate * scale * rotate * (-target_translate)
camera_view_matrix :: proc(c: Camera) -> matrix[4, 4]f32 {
	z := c.zoom if c.zoom != 0 else 1
	inv_target := linalg.matrix4_translate_f32({-c.target.x, -c.target.y, 0})
	inv_rot := linalg.matrix4_rotate_f32(c.rotation, {0, 0, 1})
	inv_scale := linalg.matrix4_scale_f32({z, z, 1})
	inv_offset := linalg.matrix4_translate_f32({c.offset.x, c.offset.y, 0})
	return inv_offset * inv_scale * inv_rot * inv_target
}

// Compute the world matrix for a camera (inverse of the view matrix).
// Transforms screen coordinates to world coordinates.
//   target_translate * (-rotate) * (1/scale) * (-offset_translate)
camera_world_matrix :: proc(c: Camera) -> matrix[4, 4]f32 {
	z := c.zoom if c.zoom != 0 else 1
	target := linalg.matrix4_translate_f32({c.target.x, c.target.y, 0})
	rot := linalg.matrix4_rotate_f32(-c.rotation, {0, 0, 1})
	scale := linalg.matrix4_scale_f32({1 / z, 1 / z, 1})
	offset := linalg.matrix4_translate_f32({-c.offset.x, -c.offset.y, 0})
	return target * rot * scale * offset
}

// Recompute and upload the combined view-projection matrix to the GPU.
// Called when the camera changes or after a window resize.
@(private = "package")
upload_view_projection :: proc() {
	w, h := ctx.window.get_framebuffer_size()
	projection := linalg.matrix_ortho3d_f32(0, f32(w), f32(h), 0, -1, 1)

	vp: matrix[4, 4]f32
	if c, ok := ctx.camera.?; ok {
		vp = projection * camera_view_matrix(c)
	} else {
		vp = projection
	}
	ctx.renderer.set_view_projection(vp)
}
