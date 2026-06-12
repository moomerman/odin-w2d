// Animation: hover/press transition timers advance linearly over
// Style.transition seconds (smoothstepped on use), and hover/press
// scale/offset effects compose into per-element transforms that propagate to
// descendants — a card scaling up on hover carries its labels with it.
package ui

@(private)
_animate :: proc() {
	for i in 0 ..< len(state.elements) {
		e := &state.elements[i]
		r := state.retained[e.id]
		t := e.style.transition
		r.hover_t = _move_toward(r.hover_t, r.hovered ? 1 : 0, t, state.dt)
		r.press_t = _move_toward(r.press_t, r.held[.Left] ? 1 : 0, t, state.dt)
		state.retained[e.id] = r
	}
}

@(private)
_move_toward :: proc(value, target, duration, dt: f32) -> f32 {
	if duration <= 0 {
		return target
	}
	step := dt / duration
	if value < target {
		return min(value + step, target)
	}
	return max(value - step, target)
}

@(private)
_smooth :: proc(t: f32) -> f32 {
	return t * t * (3 - 2 * t)
}

// _apply_transforms accumulates each element's hover/press transform with its
// ancestors'. Forward iteration guarantees the parent's transform is final
// before its children compose with it.
@(private)
_apply_transforms :: proc() {
	for i in 0 ..< len(state.elements) {
		e := &state.elements[i]
		parent_xf := e.parent >= 0 ? state.elements[e.parent].xform : Xform{scale = 1}
		e.xform = _compose(parent_xf, _own_xform(e))
	}
}

@(private)
_own_xform :: proc(e: ^Element) -> Xform {
	r := state.retained[e.id]
	hover_k := _smooth(r.hover_t)
	press_k := _smooth(r.press_t)

	scale: f32 = 1
	offset: Vec2
	if e.style.hover.scale != 0 {
		scale *= 1 + (e.style.hover.scale - 1) * hover_k
	}
	offset += e.style.hover.offset * hover_k
	if e.style.press.scale != 0 {
		scale *= 1 + (e.style.press.scale - 1) * press_k
	}
	offset += e.style.press.offset * press_k

	if scale == 1 && offset == (Vec2{}) {
		return Xform{scale = 1}
	}

	// Scale around the element's own center: p' = c + (p - c) * s.
	center := e.pos + e.size / 2
	return Xform{scale = scale, translate = center * (1 - scale) + offset}
}

// _compose applies inner first, then outer: p' = (p*si + ti)*so + to.
@(private)
_compose :: proc(outer, inner: Xform) -> Xform {
	return Xform {
		scale = outer.scale * inner.scale,
		translate = inner.translate * outer.scale + outer.translate,
	}
}

@(private)
_xform_rect :: proc(xf: Xform, pos, size: Vec2) -> Rect {
	p := pos * xf.scale + xf.translate
	s := size * xf.scale
	return Rect{p.x, p.y, s.x, s.y}
}
