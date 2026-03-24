package nav2d

// 2D Navigation Mesh for Point-and-Click Adventure Games
//
// Usage:
//   1. Define your walkable polygon (counter-clockwise winding)
//   2. Define hole polygons (clockwise winding) for obstacles
//   3. Call bake() to produce a Nav_Mesh
//   4. Call find_path() at runtime to get a smooth path
//   5. Call destroy() when done
//
// Example:
//   // Room shaped like a rectangle with a table cut out
//   outer := [][2]f32{{0,0}, {800,0}, {800,600}, {0,600}}
//   holes := [][][2]f32{
//       {{300,200}, {500,200}, {500,400}, {300,400}},  // table
//   }
//   mesh := nav2d.bake(outer, holes) or_else panic("bake failed")
//   defer nav2d.destroy(&mesh)
//
//   path := nav2d.find_path(&mesh, {50, 300}, {750, 300})
//   defer delete(path)
//   // path is a []Vec2 of waypoints to follow

import "core:math"
import "core:slice"

Vec2 :: [2]f32

// A triangle is 3 indices into the nav mesh vertex array.
Triangle :: [3]i32

Nav_Mesh :: struct {
	vertices:  []Vec2,
	triangles: []Triangle,
	// For each triangle, the index of the adjacent triangle on each edge.
	// adjacency[i][e] is the triangle sharing edge (tri[e], tri[(e+1)%3]).
	// -1 means no neighbor (boundary edge).
	adjacency: [][3]i32,
}

// -- Public API ---------------------------------------------------------------

Bake_Error :: enum {
	None,
	Too_Few_Vertices,
	Triangulation_Failed,
	Degenerate_Polygon,
}

// Bake a navigation mesh from an outer polygon boundary and optional holes.
//
// `outer` must be counter-clockwise wound.
// Each hole must be clockwise wound.
//
// Returns a Nav_Mesh that the caller must later destroy().
bake :: proc(
	outer: []Vec2,
	holes: [][]Vec2 = nil,
	allocator := context.allocator,
) -> (
	mesh: Nav_Mesh,
	err: Bake_Error,
) {
	if len(outer) < 3 {
		err = .Too_Few_Vertices
		return
	}

	// Collect all vertices and build merged polygon index ring.
	all_verts := make([dynamic]Vec2, allocator)
	for v in outer do append(&all_verts, v)
	for hole in holes {
		for v in hole do append(&all_verts, v)
	}

	// Build the merged polygon ring (outer + holes connected via bridges).
	ring := _merge_holes(outer, holes, all_verts[:], allocator) or_return

	// Ear-clip triangulate the merged polygon ring.
	tris := _ear_clip(ring, all_verts[:], allocator) or_return
	defer delete(ring)

	// Build adjacency.
	adj := _build_adjacency(tris, allocator)

	mesh = Nav_Mesh {
		vertices  = all_verts[:],
		triangles = tris,
		adjacency = adj,
	}
	return
}

destroy :: proc(mesh: ^Nav_Mesh) {
	delete(mesh.vertices)
	delete(mesh.triangles)
	delete(mesh.adjacency)
	mesh^ = {}
}

// Find a smoothed path from `start` to `goal` within the nav mesh.
//
// If `goal` is outside the mesh, the nearest point on the mesh boundary is used.
// Returns an empty slice if no path exists or start is outside the mesh.
find_path :: proc(mesh: ^Nav_Mesh, start, goal: Vec2, allocator := context.allocator) -> []Vec2 {
	// Clamp goal to mesh if outside.
	actual_goal := goal
	goal_tri := _find_containing_triangle(mesh, goal)
	if goal_tri < 0 {
		actual_goal = _nearest_point_on_mesh(mesh, goal)
		goal_tri = _find_containing_triangle(mesh, actual_goal)
		if goal_tri < 0 {
			// Try with a small epsilon nudge for edge cases (pun intended).
			// If still not found, bail.
			return nil
		}
	}

	start_tri := _find_containing_triangle(mesh, start)
	if start_tri < 0 {
		return nil
	}

	if start_tri == goal_tri {
		// Same triangle - direct line.
		result := make([]Vec2, 2, allocator)
		result[0] = start
		result[1] = actual_goal
		return result
	}

	// A* over triangle adjacency graph.
	tri_path := _astar(mesh, start_tri, goal_tri, start, actual_goal, allocator)
	if tri_path == nil {
		return nil
	}
	defer delete(tri_path)

	// Funnel algorithm to produce a smooth polyline path.
	return _funnel(mesh, tri_path, start, actual_goal, allocator)
}

// Test if a point is inside the walkable area of the nav mesh.
point_in_mesh :: proc(mesh: ^Nav_Mesh, p: Vec2) -> bool {
	return _find_containing_triangle(mesh, p) >= 0
}

// Find the closest point on the mesh boundary to a given point.
nearest_point_on_mesh_boundary :: proc(mesh: ^Nav_Mesh, p: Vec2) -> Vec2 {
	return _nearest_point_on_mesh(mesh, p)
}


// -- Geometry utilities (public) ----------------------------------------------

cross2d :: proc(a, b: Vec2) -> f32 {
	return a.x * b.y - a.y * b.x
}

dot2d :: proc(a, b: Vec2) -> f32 {
	return a.x * b.x + a.y * b.y
}

length2d :: proc(v: Vec2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

dist2d :: proc(a, b: Vec2) -> f32 {
	return length2d(b - a)
}

dist_sq :: proc(a, b: Vec2) -> f32 {
	d := b - a
	return d.x * d.x + d.y * d.y
}

// Closest point on line segment ab to point p.
closest_point_on_segment :: proc(a, b, p: Vec2) -> Vec2 {
	ab := b - a
	len_sq := dot2d(ab, ab)
	if len_sq < 1e-12 do return a
	t := clamp(dot2d(p - a, ab) / len_sq, 0, 1)
	return a + ab * t
}


// -- Internal: Hole merging ---------------------------------------------------

@(private = "file")
_merge_holes :: proc(
	outer: []Vec2,
	holes: [][]Vec2,
	all_verts: []Vec2,
	allocator := context.allocator,
) -> (
	ring: []i32,
	err: Bake_Error,
) {
	if len(holes) == 0 {
		// No holes: ring is just 0..n-1
		r := make([]i32, len(outer), allocator)
		for i in 0 ..< len(outer) {
			r[i] = i32(i)
		}
		return r, .None
	}

	// We need to merge each hole into the outer polygon by creating bridge edges.
	// Strategy: for each hole, find its rightmost vertex, cast a ray to the right,
	// find the nearest visible vertex on the current merged polygon, and splice
	// the hole in at that point.

	// Build initial ring from outer polygon.
	merged := make([dynamic]i32, allocator)
	for i in 0 ..< len(outer) {
		append(&merged, i32(i))
	}

	// Sort holes by the x-coordinate of their rightmost vertex (descending)
	// so we process from right to left.
	Hole_Info :: struct {
		index:        int,
		rightmost_x:  f32,
		rightmost_vi: int, // vertex index in all_verts
	}
	hole_infos := make([dynamic]Hole_Info, allocator)
	defer delete(hole_infos)

	vert_offset := len(outer)
	for hi in 0 ..< len(holes) {
		hole := holes[hi]
		best_x: f32 = math.F32_MIN
		best_vi := 0
		for vi in 0 ..< len(hole) {
			global_vi := vert_offset + vi
			if all_verts[global_vi].x > best_x {
				best_x = all_verts[global_vi].x
				best_vi = global_vi
			}
		}
		append(&hole_infos, Hole_Info{index = hi, rightmost_x = best_x, rightmost_vi = best_vi})
		vert_offset += len(hole)
	}

	slice.sort_by(hole_infos[:], proc(a, b: Hole_Info) -> bool {
		return a.rightmost_x > b.rightmost_x
	})

	// For each hole, find the best bridge point on the merged polygon and splice it in.
	for hi_info in hole_infos[:] {
		hi := hi_info.index
		hole := holes[hi]
		offset := 0
		for hh in 0 ..< hi {
			offset += len(holes[hh])
		}
		hole_global_start := i32(len(outer) + offset)

		// Find the rightmost vertex index within this hole (local).
		rightmost_local := 0
		best_x: f32 = math.F32_MIN
		for vi in 0 ..< len(hole) {
			gv := int(hole_global_start) + vi
			if all_verts[gv].x > best_x {
				best_x = all_verts[gv].x
				rightmost_local = vi
			}
		}

		bridge_hole_vi := hole_global_start + i32(rightmost_local)
		bridge_hole_pos := all_verts[bridge_hole_vi]

		// Find the best bridge target on the merged ring.
		// Cast a ray to the right from bridge_hole_pos and find the nearest
		// edge intersection. Then pick the closest visible vertex near that point.
		best_merged_idx := _find_bridge_target(merged[:], all_verts, bridge_hole_pos)

		if best_merged_idx < 0 {
			// Fallback: find closest vertex on merged ring.
			best_dist: f32 = math.F32_MAX
			for mi in 0 ..< len(merged) {
				d := dist_sq(bridge_hole_pos, all_verts[merged[mi]])
				if d < best_dist {
					best_dist = d
					best_merged_idx = i32(mi)
				}
			}
		}

		// Splice: insert at best_merged_idx.
		// New sequence: ...merged[best_merged_idx], hole vertices starting from rightmost
		// going around, back to rightmost, then merged[best_merged_idx] again...
		splice := make([dynamic]i32, allocator)
		// Everything up to and including the bridge point.
		for i in 0 ..= int(best_merged_idx) {
			append(&splice, merged[i])
		}
		// Hole vertices starting from the rightmost, going around the hole.
		for i in 0 ..< len(hole) {
			idx := (rightmost_local + i) % len(hole)
			append(&splice, hole_global_start + i32(idx))
		}
		// Close the bridge: back to the rightmost hole vertex, then the bridge target again.
		append(&splice, bridge_hole_vi)
		append(&splice, merged[best_merged_idx])
		// Rest of the merged ring.
		for i in int(best_merged_idx) + 1 ..< len(merged) {
			append(&splice, merged[i])
		}

		delete(merged)
		merged = splice
	}

	return merged[:], .None
}

// Find the nearest vertex on the merged polygon that is visible from `from`
// (i.e. the connecting line does not cross any polygon edge).
@(private = "file")
_find_bridge_target :: proc(ring: []i32, verts: []Vec2, from: Vec2) -> i32 {
	n := len(ring)
	best_dist: f32 = math.F32_MAX
	best_idx: i32 = -1

	for i in 0 ..< n {
		target := verts[ring[i]]
		d := dist_sq(from, target)
		if d >= best_dist do continue

		// Check if the segment from→target crosses any ring edge.
		visible := true
		for j in 0 ..< n {
			k := (j + 1) % n
			// Skip edges that share the target vertex.
			if j == i || k == i do continue
			if _segments_cross(from, target, verts[ring[j]], verts[ring[k]]) {
				visible = false
				break
			}
		}

		if visible {
			best_dist = d
			best_idx = i32(i)
		}
	}

	return best_idx
}

// Test if two line segments properly cross (interior intersection only,
// not endpoint touching).
@(private = "file")
_segments_cross :: proc(p1, q1, p2, q2: Vec2) -> bool {
	d1 := cross2d(q2 - p2, p1 - p2)
	d2 := cross2d(q2 - p2, q1 - p2)
	d3 := cross2d(q1 - p1, p2 - p1)
	d4 := cross2d(q1 - p1, q2 - p1)

	if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
		return true
	}
	return false
}


// -- Internal: Ear clipping triangulation ------------------------------------

@(private = "file")
_ear_clip :: proc(
	ring: []i32,
	verts: []Vec2,
	allocator := context.allocator,
) -> (
	tris: []Triangle,
	err: Bake_Error,
) {
	if len(ring) < 3 {
		err = .Too_Few_Vertices
		return
	}

	result := make([dynamic]Triangle, 0, len(ring) - 2, allocator)
	_ear_clip_into(&result, ring, verts, allocator)

	if len(result) == 0 {
		err = .Triangulation_Failed
		return
	}

	return result[:], .None
}

// Core ear-clip loop that appends triangles into `out`. When stuck on a
// weakly-simple polygon (duplicate vertex from bridge slit), splits at
// the duplicate and recurses on each sub-ring.
@(private = "file")
_ear_clip_into :: proc(
	out: ^[dynamic]Triangle,
	ring: []i32,
	verts: []Vec2,
	allocator := context.allocator,
) {
	n := len(ring)
	if n < 3 do return

	indices := make([dynamic]i32, n, allocator)
	defer delete(indices)
	for idx in 0 ..< n {
		indices[idx] = ring[idx]
	}

	remaining := n
	fail_count := 0
	i := 0

	for remaining > 2 {
		ia := i % remaining
		ib := (i + 1) % remaining
		ic := (i + 2) % remaining

		vi_a := indices[ia]
		vi_b := indices[ib]
		vi_c := indices[ic]

		// Collapse consecutive duplicate vertex indices (bridge slit remnants).
		if vi_a == vi_b || vi_b == vi_c {
			ordered_remove(&indices, ib)
			remaining -= 1
			fail_count = 0
			if i >= remaining do i = 0
			continue
		}

		if fail_count > remaining {
			// Stuck — look for a non-consecutive duplicate vertex and split there.
			if _split_at_duplicate(out, indices[:remaining], verts, allocator) {
				return // sub-rings handled the rest
			}
			break // truly stuck, return what we have
		}

		a := verts[vi_a]
		b := verts[vi_b]
		c := verts[vi_c]

		if cross2d(b - a, c - a) > 0 {
			is_ear := true
			for k in 0 ..< remaining {
				if k == ia || k == ib || k == ic do continue
				if indices[k] == vi_a || indices[k] == vi_b || indices[k] == vi_c do continue
				if _point_strictly_in_triangle(verts[indices[k]], a, b, c) {
					is_ear = false
					break
				}
			}

			if is_ear {
				append(out, Triangle{vi_a, vi_b, vi_c})
				ordered_remove(&indices, ib)
				remaining -= 1
				fail_count = 0
				if i >= remaining do i = 0
				continue
			}
		}

		i += 1
		if i >= remaining do i = 0
		fail_count += 1
	}
}

// Find a vertex index that appears more than once in the ring. Split into
// two sub-rings at that point and ear-clip each. Returns true if a split
// was performed.
@(private = "file")
_split_at_duplicate :: proc(
	out: ^[dynamic]Triangle,
	indices: []i32,
	verts: []Vec2,
	allocator := context.allocator,
) -> bool {
	n := len(indices)
	for a in 0 ..< n {
		for b in a + 1 ..< n {
			if indices[a] != indices[b] do continue

			// Found duplicate at positions a and b.
			// Sub-ring 1: a .. b (the loop between the two occurrences).
			len1 := b - a
			if len1 >= 3 {
				sub1 := make([]i32, len1, allocator)
				defer delete(sub1)
				for si in 0 ..< len1 {
					sub1[si] = indices[a + si]
				}
				_ear_clip_into(out, sub1, verts, allocator)
			}

			// Sub-ring 2: b .. n, 0 .. a (the rest, wrapping around).
			len2 := n - b + a
			if len2 >= 3 {
				sub2 := make([]i32, len2, allocator)
				defer delete(sub2)
				for si in 0 ..< (n - b) {
					sub2[si] = indices[b + si]
				}
				for si in 0 ..< a {
					sub2[n - b + si] = indices[si]
				}
				_ear_clip_into(out, sub2, verts, allocator)
			}
			return true
		}
	}
	return false
}

@(private = "file")
_point_in_triangle :: proc(p, a, b, c: Vec2) -> bool {
	d1 := cross2d(b - a, p - a)
	d2 := cross2d(c - b, p - b)
	d3 := cross2d(a - c, p - c)

	has_neg := (d1 < 0) || (d2 < 0) || (d3 < 0)
	has_pos := (d1 > 0) || (d2 > 0) || (d3 > 0)

	return !(has_neg && has_pos)
}

// Strict variant: points exactly on a triangle edge are NOT considered inside.
// Used by the ear clipper so that collinear vertices along bridge slits do not
// block ear detection.
@(private = "file")
_point_strictly_in_triangle :: proc(p, a, b, c: Vec2) -> bool {
	d1 := cross2d(b - a, p - a)
	d2 := cross2d(c - b, p - b)
	d3 := cross2d(a - c, p - c)

	return (d1 > 0 && d2 > 0 && d3 > 0) || (d1 < 0 && d2 < 0 && d3 < 0)
}


// -- Internal: Adjacency graph -----------------------------------------------

@(private = "file")
_build_adjacency :: proc(tris: []Triangle, allocator := context.allocator) -> [][3]i32 {
	n := len(tris)
	adj := make([][3]i32, n, allocator)
	for i in 0 ..< n {
		adj[i] = {-1, -1, -1}
	}

	// For each edge, find the other triangle sharing that edge.
	// An edge is identified by its two vertex indices (order-independent).
	Edge :: struct {
		v0, v1: i32,
	}
	Edge_Info :: struct {
		tri_idx:  i32,
		edge_idx: i32, // which edge of that triangle (0, 1, or 2)
	}

	edge_map := make(map[u64]Edge_Info, allocator = allocator)
	defer delete(edge_map)

	make_edge_key :: proc(a, b: i32) -> u64 {
		lo := min(a, b)
		hi := max(a, b)
		return u64(lo) << 32 | u64(hi)
	}

	for ti in 0 ..< i32(n) {
		tri := tris[ti]
		for e in 0 ..< i32(3) {
			v0 := tri[e]
			v1 := tri[(e + 1) % 3]
			key := make_edge_key(v0, v1)

			if other, ok := edge_map[key]; ok {
				adj[ti][e] = other.tri_idx
				adj[other.tri_idx][other.edge_idx] = ti
			} else {
				edge_map[key] = Edge_Info {
					tri_idx  = ti,
					edge_idx = e,
				}
			}
		}
	}

	return adj
}


// -- Internal: Triangle lookup -----------------------------------------------

@(private = "file")
_find_containing_triangle :: proc(mesh: ^Nav_Mesh, p: Vec2) -> i32 {
	for ti in 0 ..< i32(len(mesh.triangles)) {
		tri := mesh.triangles[ti]
		a := mesh.vertices[tri[0]]
		b := mesh.vertices[tri[1]]
		c := mesh.vertices[tri[2]]
		if _point_in_triangle(p, a, b, c) do return ti
	}
	return -1
}


// -- Internal: Nearest point on mesh boundary --------------------------------

@(private = "file")
_nearest_point_on_mesh :: proc(mesh: ^Nav_Mesh, p: Vec2) -> Vec2 {
	best_point := Vec2{0, 0}
	best_dist: f32 = math.F32_MAX

	for ti in 0 ..< len(mesh.triangles) {
		tri := mesh.triangles[ti]
		for e in 0 ..< 3 {
			// Only check boundary edges (no neighbor).
			if mesh.adjacency[ti][e] >= 0 do continue

			a := mesh.vertices[tri[e]]
			b := mesh.vertices[tri[(e + 1) % 3]]
			cp := closest_point_on_segment(a, b, p)
			d := dist_sq(p, cp)
			if d < best_dist {
				best_dist = d
				best_point = cp
			}
		}
	}

	return best_point
}


// -- Internal: A* over triangle graph ----------------------------------------

@(private = "file")
_astar :: proc(
	mesh: ^Nav_Mesh,
	start_tri, goal_tri: i32,
	start_pos, goal_pos: Vec2,
	allocator := context.allocator,
) -> []i32 {
	n := i32(len(mesh.triangles))

	_tri_center :: proc(mesh: ^Nav_Mesh, ti: i32) -> Vec2 {
		tri := mesh.triangles[ti]
		a := mesh.vertices[tri[0]]
		b := mesh.vertices[tri[1]]
		c := mesh.vertices[tri[2]]
		return (a + b + c) / 3.0
	}

	g_score := make([]f32, n, allocator)
	defer delete(g_score)
	f_score := make([]f32, n, allocator)
	defer delete(f_score)
	came_from := make([]i32, n, allocator)
	defer delete(came_from)
	in_open := make([]bool, n, allocator)
	defer delete(in_open)
	closed := make([]bool, n, allocator)
	defer delete(closed)

	for i in 0 ..< n {
		g_score[i] = math.F32_MAX
		f_score[i] = math.F32_MAX
		came_from[i] = -1
	}

	g_score[start_tri] = 0
	f_score[start_tri] = dist2d(start_pos, goal_pos)

	// Simple open set as a dynamic array (adequate for adventure game scale navmeshes).
	open := make([dynamic]i32, allocator)
	defer delete(open)
	append(&open, start_tri)
	in_open[start_tri] = true

	for len(open) > 0 {
		// Find node with lowest f_score.
		best_oi := 0
		best_f: f32 = math.F32_MAX
		for oi in 0 ..< len(open) {
			f := f_score[open[oi]]
			if f < best_f {
				best_f = f
				best_oi = oi
			}
		}

		current := open[best_oi]
		if current == goal_tri {
			// Reconstruct path.
			path := make([dynamic]i32, allocator)
			c := current
			for c >= 0 {
				// Prepend.
				inject_at(&path, 0, c)
				c = came_from[c]
			}
			return path[:]
		}

		// Remove from open set.
		ordered_remove(&open, best_oi)
		in_open[current] = false
		closed[current] = true

		// Explore neighbors.
		for e in 0 ..< 3 {
			neighbor := mesh.adjacency[current][e]
			if neighbor < 0 || closed[neighbor] do continue

			// Cost: distance between triangle centers.
			cur_center := _tri_center(mesh, current)
			nb_center := _tri_center(mesh, neighbor)
			tentative_g := g_score[current] + dist2d(cur_center, nb_center)

			if tentative_g < g_score[neighbor] {
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + dist2d(nb_center, goal_pos)

				if !in_open[neighbor] {
					append(&open, neighbor)
					in_open[neighbor] = true
				}
			}
		}
	}

	return nil // no path
}


// -- Internal: Funnel algorithm (Simple Stupid Funnel) -----------------------

@(private = "file")
_funnel :: proc(
	mesh: ^Nav_Mesh,
	tri_path: []i32,
	start, goal: Vec2,
	allocator := context.allocator,
) -> []Vec2 {
	if len(tri_path) == 0 do return nil

	if len(tri_path) == 1 {
		result := make([]Vec2, 2, allocator)
		result[0] = start
		result[1] = goal
		return result
	}

	// Build the portal (channel) edges.
	// For each pair of consecutive triangles, find the shared edge.
	Portal :: struct {
		left, right: Vec2,
	}

	portals := make([dynamic]Portal, allocator)
	defer delete(portals)

	// First portal: start point on both sides.
	append(&portals, Portal{left = start, right = start})

	for i in 0 ..< len(tri_path) - 1 {
		ti_a := tri_path[i]
		ti_b := tri_path[i + 1]
		l, r := _find_shared_edge(mesh, ti_a, ti_b, start)
		append(&portals, Portal{left = l, right = r})
	}

	// Last portal: goal point on both sides.
	append(&portals, Portal{left = goal, right = goal})

	// Simple Stupid Funnel Algorithm.
	// Uses manual index so we can restart the scan when the funnel flips.
	path := make([dynamic]Vec2, allocator)
	append(&path, start)

	apex := start
	left := start
	right := start
	apex_idx := 0
	left_idx := 0
	right_idx := 0

	i := 1
	for i < len(portals) {
		pl := portals[i].left
		pr := portals[i].right

		// Try to tighten the right side of the funnel.
		if cross2d(pr - apex, right - apex) <= 0 {
			if apex == right || cross2d(pr - apex, left - apex) > 0 {
				// Tighten right.
				right = pr
				right_idx = i
			} else {
				// Right crossed over left — left becomes new apex.
				append(&path, left)
				apex = left
				apex_idx = left_idx
				left = apex
				right = apex
				left_idx = apex_idx
				right_idx = apex_idx
				// Restart scan from just after the new apex.
				i = apex_idx + 1
				continue
			}
		}

		// Try to tighten the left side of the funnel.
		if cross2d(pl - apex, left - apex) >= 0 {
			if apex == left || cross2d(pl - apex, right - apex) < 0 {
				// Tighten left.
				left = pl
				left_idx = i
			} else {
				// Left crossed over right — right becomes new apex.
				append(&path, right)
				apex = right
				apex_idx = right_idx
				left = apex
				right = apex
				left_idx = apex_idx
				right_idx = apex_idx
				// Restart scan from just after the new apex.
				i = apex_idx + 1
				continue
			}
		}

		i += 1
	}

	// Add goal if not already the last point.
	last := path[len(path) - 1]
	if last.x != goal.x || last.y != goal.y {
		append(&path, goal)
	}

	return path[:]
}

// Given two adjacent triangles, find the shared edge and return it as
// (left, right) relative to the direction of travel.
@(private = "file")
_find_shared_edge :: proc(
	mesh: ^Nav_Mesh,
	tri_a, tri_b: i32,
	reference: Vec2,
) -> (
	left, right: Vec2,
) {
	ta := mesh.triangles[tri_a]
	tb := mesh.triangles[tri_b]

	// Find the two vertices shared between tri_a and tri_b.
	shared: [2]i32
	count := 0
	for i in 0 ..< 3 {
		for j in 0 ..< 3 {
			if ta[i] == tb[j] {
				if count < 2 {
					shared[count] = ta[i]
					count += 1
				}
			}
		}
	}

	if count < 2 {
		// Shouldn't happen with valid adjacency, but handle gracefully.
		return mesh.vertices[ta[0]], mesh.vertices[ta[1]]
	}

	s0 := mesh.vertices[shared[0]]
	s1 := mesh.vertices[shared[1]]

	// Determine which is left and which is right.
	// The "third" vertex of tri_a (the one not on the shared edge) should be
	// on the left side of the portal when moving from tri_a to tri_b.
	// We use the cross product to determine orientation.
	third_vi: i32 = -1
	for i in 0 ..< 3 {
		if ta[i] != shared[0] && ta[i] != shared[1] {
			third_vi = ta[i]
			break
		}
	}

	third := mesh.vertices[third_vi]
	// If third is to the left of s0->s1, then s0 is right and s1 is left.
	if cross2d(s1 - s0, third - s0) > 0 {
		return s1, s0
	}
	return s0, s1
}
