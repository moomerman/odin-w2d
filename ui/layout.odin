// Layout: Clay-style passes over the element tree.
//
// Elements are stored in declaration order (a preorder DFS: parents before
// children), which the passes exploit — reverse iteration visits children
// before parents (bottom-up fit sizing), forward iteration visits parents
// before children (top-down grow/percent resolution and positioning).
//
// No wrapping and no shrink in v1: children that overflow a fixed-size
// parent simply overflow.
package ui

@(private)
_style_size :: proc(s: Style, axis: int) -> Size {
	return axis == 0 ? s.w : s.h
}

@(private)
_pad_total :: proc(e: ^Element, axis: int) -> f32 {
	return axis == 0 ? e.pad[0] + e.pad[1] : e.pad[2] + e.pad[3]
}

@(private)
_pad_lo :: proc(e: ^Element, axis: int) -> f32 {
	return axis == 0 ? e.pad[0] : e.pad[2]
}

@(private)
_clamp_axis :: proc(s: Style, axis: int, v: f32) -> f32 {
	out := v
	min_v := axis == 0 ? s.min_w : s.min_h
	max_v := axis == 0 ? s.max_w : s.max_h
	if min_v > 0 && out < min_v {
		out = min_v
	}
	if max_v > 0 && out > max_v {
		out = max_v
	}
	return out
}

@(private)
_layout :: proc() {
	if len(state.elements) == 0 {
		return
	}

	// Pass 1 — fit sizing, bottom-up. Fixed sizes resolve directly; fit
	// sizes come from content. Grow and Pct contribute 0 here (their
	// minimum) and are finalized against the parent in pass 2.
	for i := len(state.elements) - 1; i >= 0; i -= 1 {
		e := &state.elements[i]
		main := e.style.dir == .Row ? 0 : 1
		for axis in 0 ..< 2 {
			spec := _style_size(e.style, axis)
			size: f32
			if fixed, is_fixed := spec.(f32); is_fixed {
				size = fixed
			} else if spec == nil {
				size = _fit_size(e, axis, axis == main)
			}
			e.size[axis] = _clamp_axis(e.style, axis, size)
		}
	}

	// Pass 2 — resolve Grow/Pct against the parent and position children,
	// top-down: a parent's final size is known before its children are
	// visited.
	state.elements[0].pos = {0, 0}

	for i in 0 ..< len(state.elements) {
		e := &state.elements[i]
		if e.first_child == -1 {
			continue
		}

		main := e.style.dir == .Row ? 0 : 1
		cross := 1 - main
		content_main := e.size[main] - _pad_total(e, main)
		content_cross := e.size[cross] - _pad_total(e, cross)

		// Resolve Pct on both axes, stretch Grow children on the cross
		// axis, and tally main-axis usage of everything that can't grow.
		used: f32
		grow_count := 0
		count := 0
		for c := e.first_child; c != -1; c = state.elements[c].next_sibling {
			child := &state.elements[c]
			for axis in 0 ..< 2 {
				if p, is_pct := _style_size(child.style, axis).(Pct); is_pct {
					avail := axis == main ? content_main : content_cross
					child.size[axis] = _clamp_axis(child.style, axis, p.fraction * avail)
				}
			}
			if _, is_grow := _style_size(child.style, cross).(Grow); is_grow {
				child.size[cross] = _clamp_axis(child.style, cross, content_cross)
			}
			if _, is_grow := _style_size(child.style, main).(Grow); is_grow {
				grow_count += 1
			} else {
				used += child.size[main]
			}
			count += 1
		}
		if count > 1 {
			used += e.style.gap * f32(count - 1)
		}

		// Distribute remaining main-axis space equally among Grow children.
		if grow_count > 0 {
			share := max((content_main - used) / f32(grow_count), 0)
			for c := e.first_child; c != -1; c = state.elements[c].next_sibling {
				child := &state.elements[c]
				if _, is_grow := _style_size(child.style, main).(Grow); is_grow {
					child.size[main] = _clamp_axis(child.style, main, share)
					used += child.size[main]
				}
			}
		}

		// Position children along the main axis (justify), then per-child on
		// the cross axis (align).
		leftover := max(content_main - used, 0)
		offset := _pad_lo(e, main)
		between: f32
		switch e.style.justify {
		case .Start:
		case .Center:
			offset += leftover / 2
		case .End:
			offset += leftover
		case .Between:
			if count > 1 {
				between = leftover / f32(count - 1)
			}
		}

		for c := e.first_child; c != -1; c = state.elements[c].next_sibling {
			child := &state.elements[c]
			child.pos[main] = e.pos[main] + offset
			cross_off := _pad_lo(e, cross)
			switch e.style.align {
			case .Start:
			case .Center:
				cross_off += (content_cross - child.size[cross]) / 2
			case .End:
				cross_off += content_cross - child.size[cross]
			}
			child.pos[cross] = e.pos[cross] + cross_off
			offset += child.size[main] + e.style.gap + between
		}
	}
}

// _fit_size is the content-derived size of an element along one axis:
// measured content for leaves, aggregated child sizes for boxes.
@(private)
_fit_size :: proc(e: ^Element, axis: int, is_main: bool) -> f32 {
	pad := _pad_total(e, axis)
	if e.kind != .Box {
		return e.content[axis] + pad
	}

	total: f32
	count := 0
	for c := e.first_child; c != -1; c = state.elements[c].next_sibling {
		child := state.elements[c]
		if is_main {
			total += child.size[axis]
		} else {
			total = max(total, child.size[axis])
		}
		count += 1
	}
	if is_main && count > 1 {
		total += e.style.gap * f32(count - 1)
	}
	return total + pad
}
