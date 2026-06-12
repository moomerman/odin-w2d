// Rendering: walk the element tree in declaration order (= draw order,
// parents behind children), emit w2d draw calls with hover/press overrides
// lerped in, and snapshot each element's final geometry for next frame's
// pointer resolution.
package ui

import w ".."
import "core:math"

@(private)
CORNER_SEGMENTS :: 6

@(private)
_render :: proc() {
	clear(&state.prev_hits)

	for i in 0 ..< len(state.elements) {
		e := &state.elements[i]
		r := state.retained[e.id]
		hover_k := _smooth(r.hover_t)
		press_k := _smooth(r.press_t)

		rect := _xform_rect(e.xform, e.pos, e.size)

		bg := _blend(e.style.bg, e.style.hover.bg, hover_k)
		bg = _blend(bg, e.style.press.bg, press_k)
		if bg.a > 0 {
			_draw_round_rect(rect, e.style.radius * e.xform.scale, bg)
		}

		if e.style.border > 0 {
			bc := _blend(e.style.border_color, e.style.hover.border_color, hover_k)
			bc = _blend(bc, e.style.press.border_color, press_k)
			if bc.a > 0 {
				w.draw_rect_outline(rect, e.style.border * e.xform.scale, bc)
			}
		}

		switch e.kind {
		case .Text:
			if len(e.text) > 0 {
				fg := _blend(e.style.fg, e.style.hover.fg, hover_k)
				fg = _blend(fg, e.style.press.fg, press_k)
				// Center the measured text inside the padded box, so
				// grow-sized buttons keep their caption centered.
				inner := e.pos + {e.pad[0], e.pad[2]}
				avail := e.size - {e.pad[0] + e.pad[1], e.pad[2] + e.pad[3]}
				inner += (avail - e.content) / 2
				pos := inner * e.xform.scale + e.xform.translate
				w.draw_text_ex(e.style.font, e.text, pos, e.style.font_size * e.xform.scale, fg)
			}
		case .Image:
			if e.texture.width > 0 {
				src := Rect{0, 0, f32(e.texture.width), f32(e.texture.height)}
				inner := _xform_rect(
					e.xform,
					e.pos + {e.pad[0], e.pad[2]},
					e.size - {e.pad[0] + e.pad[1], e.pad[2] + e.pad[3]},
				)
				w.draw_texture_rect(e.texture, src, inner)
			}
		case .Box:
		}

		append(
			&state.prev_hits,
			Hit {
				id = e.id,
				parent = e.parent,
				rect = rect,
				cursor = e.style.cursor,
				disabled = e.style.disabled,
			},
		)
	}
}

// _blend lerps base toward an override color by t; nil overrides leave the
// base untouched.
@(private)
_blend :: proc(base: Color, over: Maybe(Color), t: f32) -> Color {
	target, ok := over.?
	if !ok || t <= 0 {
		return base
	}
	if t >= 1 {
		return target
	}
	out: Color
	for i in 0 ..< 4 {
		out[i] = u8(f32(base[i]) + (f32(target[i]) - f32(base[i])) * t)
	}
	return out
}

// _draw_round_rect approximates a rounded rectangle with a cross of three
// rects plus quarter-disc fans at the corners. Regions never overlap, so
// translucent colors blend correctly. (An SDF rounded-rect primitive in the
// engine would supersede this.)
@(private)
_draw_round_rect :: proc(r: Rect, radius: f32, color: Color) {
	rad := min(radius, r.w / 2, r.h / 2)
	if rad < 1 {
		w.draw_rect(r, color)
		return
	}

	w.draw_rect({r.x + rad, r.y, r.w - 2 * rad, r.h}, color)
	w.draw_rect({r.x, r.y + rad, rad, r.h - 2 * rad}, color)
	w.draw_rect({r.x + r.w - rad, r.y + rad, rad, r.h - 2 * rad}, color)

	_draw_corner({r.x + rad, r.y + rad}, rad, math.PI, color) // top-left
	_draw_corner({r.x + r.w - rad, r.y + rad}, rad, math.PI * 1.5, color) // top-right
	_draw_corner({r.x + r.w - rad, r.y + r.h - rad}, rad, 0, color) // bottom-right
	_draw_corner({r.x + rad, r.y + r.h - rad}, rad, math.PI * 0.5, color) // bottom-left
}

// _draw_corner fans a quarter disc clockwise (in y-down screen space) from
// start_angle around center.
@(private)
_draw_corner :: proc(center: Vec2, radius: f32, start_angle: f32, color: Color) {
	step := math.PI * 0.5 / f32(CORNER_SEGMENTS)
	for i in 0 ..< CORNER_SEGMENTS {
		a0 := start_angle + f32(i) * step
		a1 := a0 + step
		p0 := center + Vec2{math.cos(a0), math.sin(a0)} * radius
		p1 := center + Vec2{math.cos(a1), math.sin(a1)} * radius
		w.draw_triangle({center, p0, p1}, color)
	}
}
