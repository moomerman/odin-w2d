// Package ui is an immediate-mode UI library for w2d.
//
// Declare the element tree every frame inside `if ui.frame() { ... }`.
// Layout runs when the frame scope closes (Clay-style passes: fit sizing,
// then grow/percent resolution, then positioning), and render commands are
// emitted via w2d draw calls. Interaction resolves against the previous
// frame's geometry — the standard immediate-mode one-frame latency,
// imperceptible at 60fps.
//
// Identity: elements are keyed by call site (#caller_location) combined with
// the parent chain; pass `idx` when declaring elements in a loop, or two
// iterations would share hover/click state. Retained state (hover/press
// transition timers) lives in a map keyed by element id and is collected
// when an id goes undeclared.
//
// This file is the public API surface; the implementation lives in the
// sibling files (context, style, layout, interaction, animation, render).
package ui

import w ".."

Color :: w.Color
Vec2 :: w.Vec2
Rect :: w.Rect
Font :: w.Font
Cursor :: w.System_Cursor

// --- Sizing -----------------------------------------------------------------

// Size of an element along one axis.
//   nil (zero value) — fit: size to content
//   f32              — fixed pixels (`w = 120`)
//   Grow             — fill remaining space in the parent (`w = ui.GROW`)
//   Pct              — fraction of the parent (`w = ui.pct(50)`)
Size :: union {
	f32,
	Grow,
	Pct,
}

Grow :: struct {}
GROW :: Grow{}

// A struct rather than `distinct f32` so that bare numbers assigned to a Size
// field unambiguously pick the fixed-pixel f32 variant.
Pct :: struct {
	fraction: f32,
}

// pct(50) = 50% of the parent's size along this axis.
pct :: proc(v: f32) -> Pct {
	return Pct{v / 100}
}

Dir :: enum {
	Col, // children stack vertically (zero value)
	Row, // children flow horizontally
}

// Cross-axis alignment of children. Zero value = Start.
Align :: enum {
	Start,
	Center,
	End,
}

// Main-axis distribution of children. Zero value = Start.
Justify :: enum {
	Start,
	Center,
	End,
	Between, // distribute free space between children
}

// --- Style ------------------------------------------------------------------

// Style is designed so the zero value is a sensible default for every field:
// fit-sized, unpadded, transparent, theme-inherited text. Padding follows
// Tailwind specificity — pl/pr/pt/pb override px/py, which override p.
Style :: struct {
	// layout
	dir:                        Dir,
	w, h:                       Size,
	min_w, min_h, max_w, max_h: f32, // 0 = unconstrained
	p, px, py, pl, pr, pt, pb:  f32, // padding
	gap:                        f32, // space between children on the main axis
	align:                      Align,
	justify:                    Justify,

	// appearance — Maybe colors distinguish "unset" (nil: transparent for bg,
	// theme-inherited for fg) from an explicit value, so merge can override a
	// preset's color with BLANK.
	bg:                         Maybe(Color), // nil = transparent (not drawn)
	radius:                     f32, // corner radius
	border:                     f32, // outline thickness, 0 = none
	border_color:               Maybe(Color),

	// text (label/button)
	fg:                         Maybe(Color), // nil = inherit theme
	font:                       Font, // zero = theme font
	font_size:                  f32, // zero = theme size

	// interaction + animation
	hover:                      Overrides,
	press:                      Overrides,
	transition:                 f32, // seconds to ease toward hover/press overrides; 0 = instant
	cursor:                     Cursor, // shown while hovered; zero = leave unchanged
	disabled:                   bool, // suppresses hover/press/click
}

// Overrides are the animatable properties applied on hover/press.
// Maybe fields distinguish "leave alone" (nil) from "set to zero"
// (e.g. fade to transparent). Eased over Style.transition seconds.
Overrides :: struct {
	bg:           Maybe(Color),
	fg:           Maybe(Color),
	border_color: Maybe(Color),
	scale:        f32, // multiplier around the element center; 0 = unchanged
	offset:       Vec2, // translation in pixels
}

Theme :: struct {
	font:       Font, // zero = engine default font
	font_size:  f32, // zero = 16
	fg:         Color, // zero = WHITE
	button:     Style, // base style merged under every button's style arg
	transition: f32, // reserved: default transition for widgets
}

// --- Lifecycle ----------------------------------------------------------------

// init prepares the UI state. Call from your init proc, before the first
// frame. A zero theme gets sensible defaults (16px default font, white text,
// a subtle translucent button style).
init :: proc(theme := Theme{}) {
	_init(theme)
}

shutdown :: proc() {
	_shutdown()
}

set_theme :: proc(theme: Theme) {
	_set_theme(theme)
}

// frame opens the UI for declaration; layout and rendering run when the scope
// closes. The root spans the screen. Always returns true:
//   if ui.frame() { ... }
@(deferred_out = _frame_end)
frame :: proc() -> bool {
	return _frame_begin()
}

// --- Containers -----------------------------------------------------------------

// box opens a container; children declared inside the if-body are laid out
// according to style. Always returns true (the bool exists to drive the
// deferred scope close):
//   if ui.box({dir = .Row, p = 12, gap = 8}) { ... }
@(deferred_out = _scope_end)
box :: proc(style := Style{}, idx := -1, loc := #caller_location) -> bool {
	return _open(style, idx, loc)
}

// hbox is box with dir = .Row.
@(deferred_out = _scope_end)
hbox :: proc(style := Style{}, idx := -1, loc := #caller_location) -> bool {
	s := style
	s.dir = .Row
	return _open(s, idx, loc)
}

// vbox is box with dir = .Col.
@(deferred_out = _scope_end)
vbox :: proc(style := Style{}, idx := -1, loc := #caller_location) -> bool {
	s := style
	s.dir = .Col
	return _open(s, idx, loc)
}

// spacer consumes free space on the parent's main axis (or a fixed amount).
spacer :: proc(size: Size = GROW, idx := -1, loc := #caller_location) {
	assert(state.in_frame, "ui.spacer must be called inside ui.frame()")
	s: Style
	parent := state.elements[state.open_stack[len(state.open_stack) - 1]]
	if parent.style.dir == .Row {
		s.w = size
	} else {
		s.h = size
	}
	_ = _declare(.Box, s, "", {}, idx, loc)
}

// --- Widgets ----------------------------------------------------------------------

// label draws text. The string must stay valid until the frame scope closes
// (frame-temp allocations are fine).
label :: proc(text: string, style := Style{}, idx := -1, loc := #caller_location) {
	_ = _declare(.Text, style, text, {}, idx, loc)
}

// button is a label with the theme's button style merged underneath and a
// click result. Returns true on click (release over the element the press
// started on):
//   if ui.button("Play", {bg = ACCENT}) { start() }
button :: proc(text: string, style := Style{}, idx := -1, loc := #caller_location) -> bool {
	s := merge(state.theme.button, style)
	i := _declare(.Text, s, text, {}, idx, loc)
	return state.retained[state.elements[i].id].clicked[.Left]
}

image :: proc(texture: w.Texture, style := Style{}, idx := -1, loc := #caller_location) {
	_ = _declare(.Image, style, "", texture, idx, loc)
}

// --- Interaction queries ------------------------------------------------------
// These report on the innermost open container, making any box interactive:
//   if ui.vbox({...}) {
//       if ui.clicked() { select(item) }
//   }

hovered :: proc() -> bool {
	return _current_retained().hovered
}

clicked :: proc(btn := w.Mouse_Button.Left) -> bool {
	return _current_retained().clicked[btn]
}

held :: proc(btn := w.Mouse_Button.Left) -> bool {
	return _current_retained().held[btn]
}

Signal :: struct {
	hovered:  bool,
	entered:  bool, // hover began this frame
	exited:   bool, // hover ended this frame
	held:     bool,
	clicked:  bool,
	released: bool,
	hover_t:  f32, // eased 0..1 hover transition progress, for custom effects
}

signal :: proc() -> Signal {
	r := _current_retained()
	return Signal {
		hovered = r.hovered,
		entered = r.hovered && !r.prev_hovered,
		exited = !r.hovered && r.prev_hovered,
		held = r.held[.Left],
		clicked = r.clicked[.Left],
		released = r.released[.Left],
		hover_t = _smooth(r.hover_t),
	}
}
