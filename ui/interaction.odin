// Interaction: pointer resolution at frame begin, against the previous
// frame's geometry (prev_hits, in draw order). The topmost element under the
// pointer and all its ancestors count as hovered, so containers respond to
// hovers and clicks on their children. Presses latch onto the hovered chain
// and resolve to a click only if released while still hovered.
package ui

import w ".."

@(private)
_process_input :: proc() {
	mouse := w.get_mouse_position()

	// Reset per-frame signals; keep last frame's hover for enter/exit edges.
	for _, &r in state.retained {
		r.prev_hovered = r.hovered
		r.hovered = false
		r.clicked = {}
		r.released = {}
	}

	// Topmost element under the pointer: last containing rect in draw order.
	hot := -1
	for hit, i in state.prev_hits {
		if _rect_contains(hit.rect, mouse) {
			hot = i
		}
	}

	went_down: Buttons
	went_up: Buttons
	for b in w.Mouse_Button {
		went_down[b] = w.mouse_button_went_down(b)
		went_up[b] = w.mouse_button_went_up(b)
	}

	// Mark the hot element and its ancestors hovered; presses latch on.
	// The innermost element requesting a cursor wins.
	cursor: Cursor = .Default
	for j := hot; j != -1; j = int(state.prev_hits[j].parent) {
		hit := state.prev_hits[j]
		if hit.disabled {
			continue
		}
		if cursor == .Default {
			cursor = hit.cursor
		}
		r := state.retained[hit.id]
		r.hovered = true
		for b in w.Mouse_Button {
			if went_down[b] {
				r.held[b] = true
			}
		}
		state.retained[hit.id] = r
	}

	// Releases resolve clicks: clicked = released over the element the press
	// started on.
	for _, &r in state.retained {
		for b in w.Mouse_Button {
			if went_up[b] && r.held[b] {
				r.released[b] = true
				r.clicked[b] = r.hovered
				r.held[b] = false
			}
		}
	}

	// Own the system cursor only while a hovered element requests one, and
	// restore the default exactly once on leave.
	if cursor != state.active_cursor {
		w.set_cursor(cursor)
		state.active_cursor = cursor
	}
}

@(private)
_rect_contains :: proc(r: w.Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
}
