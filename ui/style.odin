// Style resolution: theme defaults, Tailwind-style padding specificity, and
// the merge composition primitive.
package ui

import w ".."

// merge returns base with every non-zero field of over applied on top — the
// composition primitive for style presets:
//   BTN :: ui.Style{px = 14, py = 8, radius = 6}
//   ui.button("Quit", ui.merge(BTN, {bg = RED}))
// Zero means "unset" here, so a zero-valued field of over (e.g. dir = .Col,
// transition = 0) cannot override a non-zero base field.
merge :: proc(base, over: Style) -> Style {
	out := base

	if over.dir != .Col {out.dir = over.dir}
	if over.w != nil {out.w = over.w}
	if over.h != nil {out.h = over.h}
	if over.min_w != 0 {out.min_w = over.min_w}
	if over.min_h != 0 {out.min_h = over.min_h}
	if over.max_w != 0 {out.max_w = over.max_w}
	if over.max_h != 0 {out.max_h = over.max_h}
	if over.p != 0 {out.p = over.p}
	if over.px != 0 {out.px = over.px}
	if over.py != 0 {out.py = over.py}
	if over.pl != 0 {out.pl = over.pl}
	if over.pr != 0 {out.pr = over.pr}
	if over.pt != 0 {out.pt = over.pt}
	if over.pb != 0 {out.pb = over.pb}
	if over.gap != 0 {out.gap = over.gap}
	if over.align != .Start {out.align = over.align}
	if over.justify != .Start {out.justify = over.justify}

	if over.bg != (Color{}) {out.bg = over.bg}
	if over.radius != 0 {out.radius = over.radius}
	if over.border != 0 {out.border = over.border}
	if over.border_color != (Color{}) {out.border_color = over.border_color}

	if over.fg != (Color{}) {out.fg = over.fg}
	if over.font != 0 {out.font = over.font}
	if over.font_size != 0 {out.font_size = over.font_size}

	out.hover = _merge_overrides(base.hover, over.hover)
	out.press = _merge_overrides(base.press, over.press)
	if over.transition != 0 {out.transition = over.transition}
	if over.cursor != .Default {out.cursor = over.cursor}
	if over.disabled {out.disabled = true}

	return out
}

@(private)
_merge_overrides :: proc(base, over: Overrides) -> Overrides {
	out := base
	if over.bg != nil {out.bg = over.bg}
	if over.fg != nil {out.fg = over.fg}
	if over.border_color != nil {out.border_color = over.border_color}
	if over.scale != 0 {out.scale = over.scale}
	if over.offset != (Vec2{}) {out.offset = over.offset}
	return out
}

@(private)
_set_theme :: proc(theme: Theme) {
	t := theme
	if t.font_size == 0 {
		t.font_size = 16
	}
	if t.fg == (Color{}) {
		t.fg = w.WHITE
	}
	if t.button == (Style{}) {
		t.button = Style {
			px = 14,
			py = 8,
			radius = 6,
			bg = {255, 255, 255, 20},
			hover = {bg = Color{255, 255, 255, 45}},
			press = {offset = {0, 1}},
			transition = 0.12,
			cursor = .Pointer,
		}
	}
	state.theme = t
}

// _resolve_style bakes theme inheritance and padding specificity into the
// element at declaration time, and measures intrinsic content (text, image)
// so the layout fit pass has it available.
@(private)
_resolve_style :: proc(e: ^Element) {
	s := &e.style

	pad_l, pad_r, pad_t, pad_b := s.p, s.p, s.p, s.p
	if s.px != 0 {
		pad_l, pad_r = s.px, s.px
	}
	if s.py != 0 {
		pad_t, pad_b = s.py, s.py
	}
	if s.pl != 0 {pad_l = s.pl}
	if s.pr != 0 {pad_r = s.pr}
	if s.pt != 0 {pad_t = s.pt}
	if s.pb != 0 {pad_b = s.pb}
	e.pad = {pad_l, pad_r, pad_t, pad_b}

	if s.fg == (Color{}) {
		s.fg = state.theme.fg
	}
	if s.font == 0 {
		s.font = state.theme.font != 0 ? state.theme.font : w.get_default_font()
	}
	if s.font_size == 0 {
		s.font_size = state.theme.font_size
	}

	switch e.kind {
	case .Text:
		e.content = w.measure_text_ex(s.font, e.text, s.font_size)
	case .Image:
		e.content = {f32(e.texture.width), f32(e.texture.height)}
	case .Box:
		e.content = {}
	}
}
