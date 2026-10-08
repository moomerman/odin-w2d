package engine

import "core:math"

// 2D affine transform, applied on the CPU to every vertex the engine emits
// while it is on the stack. Composes with the camera (transform first, then
// camera), costs no flush and no projection slot, and applies to text too.
//
//   x' = a·x + c·y + tx
//   y' = b·x + d·y + ty
Transform :: struct {
	a, b, c, d: f32,
	tx, ty:     f32,
}

IDENTITY_TRANSFORM :: Transform{1, 0, 0, 1, 0, 0}

@(private = "file")
MAX_TRANSFORM_DEPTH :: 64

@(private = "file")
transform_stack: [MAX_TRANSFORM_DEPTH]Transform

@(private = "file")
transform_depth: int

// Build a transform that maps local point `origin` to `translate`, rotated
// by `rotation` radians and scaled by `scale` about that origin — the same
// convention as draw_rect_ex.
transform_make :: proc(
	translate: Vec2,
	rotation: f32 = 0,
	scale: Vec2 = {1, 1},
	origin: Vec2 = {0, 0},
) -> Transform {
	cs := math.cos(rotation)
	sn := math.sin(rotation)
	t := Transform {
		a = cs * scale.x,
		b = sn * scale.x,
		c = -sn * scale.y,
		d = cs * scale.y,
	}
	// translate − R·S·origin
	t.tx = translate.x - (t.a * origin.x + t.c * origin.y)
	t.ty = translate.y - (t.b * origin.x + t.d * origin.y)
	return t
}

// Compose: the result applies `inner` first, then `outer`.
transform_mul :: proc(outer, inner: Transform) -> Transform {
	return {
		a = outer.a * inner.a + outer.c * inner.b,
		b = outer.b * inner.a + outer.d * inner.b,
		c = outer.a * inner.c + outer.c * inner.d,
		d = outer.b * inner.c + outer.d * inner.d,
		tx = outer.a * inner.tx + outer.c * inner.ty + outer.tx,
		ty = outer.b * inner.tx + outer.d * inner.ty + outer.ty,
	}
}

transform_point :: proc(t: Transform, p: Vec2) -> Vec2 {
	return {t.a * p.x + t.c * p.y + t.tx, t.b * p.x + t.d * p.y + t.ty}
}

// Inverse, for mapping mouse positions back into a group's local space.
transform_inverse :: proc(t: Transform) -> Transform {
	det := t.a * t.d - t.b * t.c
	if det == 0 {
		return IDENTITY_TRANSFORM
	}
	inv := Transform {
		a = t.d / det,
		b = -t.b / det,
		c = -t.c / det,
		d = t.a / det,
	}
	inv.tx = -(inv.a * t.tx + inv.c * t.ty)
	inv.ty = -(inv.b * t.tx + inv.d * t.ty)
	return inv
}

// Push a transform that composes with whatever is already on the stack.
// Subsequent draw calls are in the new local space until pop_transform.
//
// Example: draw a rotated, scaled group of shapes around a pivot
//   w.push_transform({400, 300}, rotation = angle, scale = {2, 2}, origin = {50, 50})
//   w.draw_rect({0, 0, 100, 100}, w.RED)   // 100×100 local, drawn 200×200 rotated
//   w.draw_text("label", {10, 10}, 16)      // text follows too
//   w.pop_transform()
push_transform :: proc(
	translate: Vec2,
	rotation: f32 = 0,
	scale: Vec2 = {1, 1},
	origin: Vec2 = {0, 0},
) {
	push_transform_ex(transform_make(translate, rotation, scale, origin))
}

// Push a raw transform, composed with the current one.
push_transform_ex :: proc(t: Transform) {
	assert(transform_depth < MAX_TRANSFORM_DEPTH, "transform stack overflow")
	transform_stack[transform_depth] = transform_mul(get_transform(), t)
	transform_depth += 1
}

pop_transform :: proc() {
	assert(transform_depth > 0, "pop_transform without a matching push")
	transform_depth -= 1
}

// The combined transform currently applied to draw calls.
get_transform :: proc() -> Transform {
	if transform_depth == 0 {
		return IDENTITY_TRANSFORM
	}
	return transform_stack[transform_depth - 1]
}

// Map a point in the current local space to screen (pre-camera) space.
transform_apply :: proc(p: Vec2) -> Vec2 {
	if transform_depth == 0 {
		return p
	}
	return transform_point(transform_stack[transform_depth - 1], p)
}

// Called from clear(): a transform left on the stack would silently move
// everything next frame, so the stack is reset every frame.
@(private = "package")
transform_reset :: proc() {
	transform_depth = 0
}

// --- Quad emission ------------------------------------------------------------
// Every engine draw call goes through these so the transform stack applies
// uniformly to rects, shapes, textures and text.

@(private = "package")
emit_quad :: proc(dst: Rect, uv: [4][2]f32, tex: Texture_Handle, color: Color) {
	if transform_depth == 0 {
		ctx.renderer.push_quad(dst, uv, tex, color)
		return
	}
	t := transform_stack[transform_depth - 1]
	positions := [4]Vec2 {
		transform_point(t, {dst.x, dst.y}),
		transform_point(t, {dst.x + dst.w, dst.y}),
		transform_point(t, {dst.x + dst.w, dst.y + dst.h}),
		transform_point(t, {dst.x, dst.y + dst.h}),
	}
	ctx.renderer.push_quad_ex(positions, uv, tex, color)
}

@(private = "package")
emit_quad_ex :: proc(positions: [4]Vec2, uv: [4][2]f32, tex: Texture_Handle, color: Color) {
	if transform_depth == 0 {
		ctx.renderer.push_quad_ex(positions, uv, tex, color)
		return
	}
	t := transform_stack[transform_depth - 1]
	p := positions
	for &v in p {
		v = transform_point(t, v)
	}
	ctx.renderer.push_quad_ex(p, uv, tex, color)
}

@(private = "package")
emit_quad_colors :: proc(
	positions: [4]Vec2,
	uv: [4][2]f32,
	tex: Texture_Handle,
	colors: [4]Color,
) {
	p := positions
	if transform_depth > 0 {
		t := transform_stack[transform_depth - 1]
		for &v in p {
			v = transform_point(t, v)
		}
	}
	ctx.renderer.push_quad_colors(p, uv, tex, colors)
}
