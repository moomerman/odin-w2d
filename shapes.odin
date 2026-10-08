package engine

import "core:math"

// Vector shapes built from the quad batcher: rounded rects, ellipses,
// polygons, stroked paths, Béziers and arcs. All respect the transform
// stack and the camera like every other draw call.

@(private = "file")
CORNER_SEGMENTS :: 6

// Filled rounded rectangle. `radius` is clamped to half the shorter side.
draw_rounded_rect :: proc(r: Rect, radius: f32, color: Color) {
	if radius <= 0.5 {
		draw_rect(r, color)
		return
	}
	buf: [4 * (CORNER_SEGMENTS + 1)]Vec2
	draw_polygon(rounded_rect_points(r, radius, buf[:]), color)
}

// Rounded rectangle outline, stroked along the edge with round joins.
draw_rounded_rect_outline :: proc(r: Rect, radius: f32, thickness: f32, color: Color) {
	buf: [4 * (CORNER_SEGMENTS + 1)]Vec2
	draw_polyline(rounded_rect_points(r, radius, buf[:]), thickness, color, closed = true)
}

@(private = "file")
rounded_rect_points :: proc(r: Rect, radius: f32, buf: []Vec2) -> []Vec2 {
	rad := min(radius, r.w / 2, r.h / 2)
	corners := [4]Vec2 {
		{r.x + r.w - rad, r.y + rad}, // top-right
		{r.x + r.w - rad, r.y + r.h - rad}, // bottom-right
		{r.x + rad, r.y + r.h - rad}, // bottom-left
		{r.x + rad, r.y + rad}, // top-left
	}
	n := 0
	for c, ci in corners {
		start := f32(ci) * math.PI / 2 - math.PI / 2
		for s in 0 ..= CORNER_SEGMENTS {
			a := start + f32(s) / CORNER_SEGMENTS * math.PI / 2
			buf[n] = {c.x + math.cos(a) * rad, c.y + math.sin(a) * rad}
			n += 1
		}
	}
	return buf[:n]
}

// Filled convex polygon, as a fan from the first vertex. Concave shapes
// need to be split by the caller.
draw_polygon :: proc(points: []Vec2, color: Color) {
	white := ctx.renderer.get_white_texture()
	for i in 1 ..< len(points) - 1 {
		emit_quad_ex({points[0], points[i], points[i + 1], points[i + 1]}, WHITE_UV, white, color)
	}
}

// Filled ellipse with radii rx, ry.
draw_ellipse :: proc(center: Vec2, rx, ry: f32, color: Color, segments: int = 24) {
	white := ctx.renderer.get_white_texture()
	prev := Vec2{center.x + rx, center.y}
	for i in 1 ..= segments {
		a := f32(i) / f32(segments) * math.TAU
		p := Vec2{center.x + math.cos(a) * rx, center.y + math.sin(a) * ry}
		emit_quad_ex({center, prev, p, p}, WHITE_UV, white, color)
		prev = p
	}
}

draw_ellipse_outline :: proc(
	center: Vec2,
	rx, ry: f32,
	thickness: f32,
	color: Color,
	segments: int = 32,
) {
	prev := Vec2{center.x + rx, center.y}
	for i in 1 ..= segments {
		a := f32(i) / f32(segments) * math.TAU
		p := Vec2{center.x + math.cos(a) * rx, center.y + math.sin(a) * ry}
		draw_line(prev, p, thickness, color)
		prev = p
	}
}

// Stroke a path with round caps and round joins. With `closed` the last
// point connects back to the first.
draw_polyline :: proc(points: []Vec2, thickness: f32, color: Color, closed: bool = false) {
	n := len(points)
	if n == 0 {
		return
	}
	segs := max(int(thickness), 6)
	if n == 1 {
		draw_circle(points[0], thickness / 2, color, segs)
		return
	}
	for i in 1 ..< n {
		draw_line(points[i - 1], points[i], thickness, color)
	}
	if closed {
		draw_line(points[n - 1], points[0], thickness, color)
	}
	// Round joins (and caps on an open path) are circles at the vertices.
	// Thin lines skip them — a 1 px join is invisible.
	if thickness >= 2 {
		for p in points {
			draw_circle(p, thickness / 2, color, segs)
		}
	}
}

// Stroked cubic Bézier from p0 to p3 with control points p1 and p2 (the
// SVG "C" command).
draw_bezier :: proc(p0, p1, p2, p3: Vec2, thickness: f32, color: Color, segments: int = 24) {
	n := clamp(segments, 1, 255)
	pts: [256]Vec2
	for i in 0 ..= n {
		pts[i] = bezier_point(p0, p1, p2, p3, f32(i) / f32(n))
	}
	draw_polyline(pts[:n + 1], thickness, color)
}

// Point on a cubic Bézier at parameter t in 0..1.
bezier_point :: proc(p0, p1, p2, p3: Vec2, t: f32) -> Vec2 {
	u := 1 - t
	return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
}

// Stroked circular arc from start_angle to end_angle (radians, clockwise on
// screen since y points down).
draw_arc :: proc(
	center: Vec2,
	radius: f32,
	start_angle, end_angle: f32,
	thickness: f32,
	color: Color,
	segments: int = 16,
) {
	n := clamp(segments, 1, 255)
	pts: [256]Vec2
	for i in 0 ..= n {
		a := start_angle + (end_angle - start_angle) * f32(i) / f32(n)
		pts[i] = {center.x + math.cos(a) * radius, center.y + math.sin(a) * radius}
	}
	draw_polyline(pts[:n + 1], thickness, color)
}

// Filled circle that fades from `center_color` at the middle to
// `edge_color` at the rim: a radial gradient from per-vertex colours.
// With an edge alpha of 0 this is a soft glow or a round shadow without
// baking a texture; use .Additive blend for light.
draw_circle_gradient :: proc(
	center: Vec2,
	radius: f32,
	center_color, edge_color: Color,
	segments: int = 32,
) {
	white := ctx.renderer.get_white_texture()
	step := math.TAU / f32(segments)
	for i in 0 ..< segments {
		a0 := step * f32(i)
		a1 := step * f32(i + 1)
		p1 := Vec2{center.x + math.cos(a0) * radius, center.y + math.sin(a0) * radius}
		p2 := Vec2{center.x + math.cos(a1) * radius, center.y + math.sin(a1) * radius}
		emit_quad_colors(
			{center, p1, p2, p2},
			WHITE_UV,
			white,
			{center_color, edge_color, edge_color, edge_color},
		)
	}
}
