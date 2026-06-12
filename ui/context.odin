// UI state: the per-frame element tree, retained cross-frame state keyed by
// element id, and the frame lifecycle (begin, close, end-of-frame passes).
package ui

import w ".."
import "base:runtime"
import "core:hash"
import "core:mem"

@(private)
Element_Kind :: enum {
	Box,
	Text,
	Image,
}

@(private)
Element :: struct {
	id:           u64,
	kind:         Element_Kind,
	style:        Style,
	text:         string,
	texture:      w.Texture,

	// tree links — indices into state.elements, -1 = none
	parent:       i32,
	first_child:  i32,
	last_child:   i32,
	next_sibling: i32,

	// layout results
	content:      Vec2, // intrinsic content size (measured text, texture dims)
	pad:          [4]f32, // resolved padding: left, right, top, bottom
	size:         Vec2,
	pos:          Vec2, // absolute, pre-transform
	xform:        Xform, // accumulated hover/press transform
}

// Uniform scale + translate: p' = p * scale + translate.
@(private)
Xform :: struct {
	scale:     f32,
	translate: Vec2,
}

@(private)
Buttons :: [w.Mouse_Button]bool

// Retained survives across frames, keyed by element id. Interaction fields
// are recomputed at frame begin from the previous frame's geometry.
@(private)
Retained :: struct {
	last_frame:   u64,
	hover_t:      f32, // 0..1 hover transition progress (linear; smoothed on use)
	press_t:      f32,
	hovered:      bool,
	prev_hovered: bool,
	held:         Buttons,
	clicked:      Buttons,
	released:     Buttons,
}

// Hit is the previous frame's geometry snapshot used for pointer resolution,
// stored in draw order so the last containing rect is the topmost element.
@(private)
Hit :: struct {
	id:       u64,
	parent:   i32,
	rect:     w.Rect,
	cursor:   Cursor,
	disabled: bool,
}

@(private)
State :: struct {
	initialized:   bool,
	theme:         Theme,
	frame_index:   u64,
	dt:            f32,
	in_frame:      bool,
	elements:      [dynamic]Element,
	open_stack:    [dynamic]i32,
	retained:      map[u64]Retained,
	prev_hits:     [dynamic]Hit,
	gc_scratch:    [dynamic]u64,
	active_cursor: Cursor, // non-default cursor we set, to restore on leave
}

@(private)
state: State

@(private)
ROOT_ID :: u64(0x9e3779b97f4a7c15)

@(private)
_init :: proc(theme: Theme) {
	state.initialized = true
	_set_theme(theme)
}

@(private)
_shutdown :: proc() {
	delete(state.elements)
	delete(state.open_stack)
	delete(state.retained)
	delete(state.prev_hits)
	delete(state.gc_scratch)
	state = {}
}

@(private)
_frame_begin :: proc() -> bool {
	assert(state.initialized, "call ui.init() before ui.frame()")
	assert(!state.in_frame, "ui.frame() is already open")
	state.frame_index += 1
	state.dt = w.get_frame_time()

	_process_input()

	clear(&state.elements)
	clear(&state.open_stack)

	sw, sh := w.get_screen_size()
	append(
		&state.elements,
		Element {
			id = ROOT_ID,
			kind = .Box,
			style = Style{w = f32(sw), h = f32(sh)},
			parent = -1,
			first_child = -1,
			last_child = -1,
			next_sibling = -1,
		},
	)
	append(&state.open_stack, 0)
	_touch_retained(ROOT_ID)
	state.in_frame = true
	return true
}

@(private)
_frame_end :: proc(opened: bool) {
	if !opened {
		return
	}
	pop(&state.open_stack) // root
	assert(len(state.open_stack) == 0, "unbalanced ui scopes at end of frame")
	state.in_frame = false

	_layout()
	_animate()
	_apply_transforms()
	_render()
	_gc_retained()
}

// _declare creates an element under the innermost open container and links it
// into the tree. Returns its index into state.elements.
@(private)
_declare :: proc(
	kind: Element_Kind,
	style: Style,
	text: string,
	texture: w.Texture,
	idx: int,
	loc: runtime.Source_Code_Location,
) -> i32 {
	assert(state.in_frame, "ui elements must be declared inside ui.frame()")
	parent := state.open_stack[len(state.open_stack) - 1]

	e := Element {
		id           = _compute_id(state.elements[parent].id, loc, idx),
		kind         = kind,
		style        = style,
		text         = text,
		texture      = texture,
		parent       = parent,
		first_child  = -1,
		last_child   = -1,
		next_sibling = -1,
	}
	_resolve_style(&e)

	i := i32(len(state.elements))
	append(&state.elements, e)

	p := &state.elements[parent]
	if p.first_child == -1 {
		p.first_child = i
	} else {
		state.elements[p.last_child].next_sibling = i
	}
	p.last_child = i

	_touch_retained(e.id)
	return i
}

@(private)
_open :: proc(style: Style, idx: int, loc: runtime.Source_Code_Location) -> bool {
	append(&state.open_stack, _declare(.Box, style, "", {}, idx, loc))
	return true
}

@(private)
_close :: proc() {
	pop(&state.open_stack)
}

@(private)
_scope_end :: proc(opened: bool) {
	if opened {
		_close()
	}
}

// Element ids hash the call site seeded by the parent's id, so the same proc
// declaring elements from different parents yields distinct ids. idx
// disambiguates loop iterations sharing one call site.
@(private)
_compute_id :: proc(parent_id: u64, loc: runtime.Source_Code_Location, idx: int) -> u64 {
	h := hash.fnv64a(transmute([]u8)loc.file_path, parent_id)
	nums := [3]u64{u64(loc.line), u64(loc.column), u64(idx + 1)}
	return hash.fnv64a(mem.slice_to_bytes(nums[:]), h)
}

// _touch_retained marks the id live this frame, creating its entry on first
// sight so interaction and animation state accumulate from the next frame.
@(private)
_touch_retained :: proc(id: u64) {
	r := state.retained[id] // zero value if missing
	r.last_frame = state.frame_index
	state.retained[id] = r
}

@(private)
_current_retained :: proc() -> Retained {
	assert(state.in_frame, "ui queries must be called inside ui.frame()")
	i := state.open_stack[len(state.open_stack) - 1]
	return state.retained[state.elements[i].id]
}

// Drop retained state for ids that were not declared this frame.
@(private)
_gc_retained :: proc() {
	clear(&state.gc_scratch)
	for id, r in state.retained {
		if r.last_frame != state.frame_index {
			append(&state.gc_scratch, id)
		}
	}
	for id in state.gc_scratch {
		delete_key(&state.retained, id)
	}
}
