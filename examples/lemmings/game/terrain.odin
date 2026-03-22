package game

Terrain :: struct {
	width:  i32,
	height: i32,
	mask:   []u8, // 1 = solid, 0 = empty
	pixels: []u32, // RGBA pixel data (CPU-side buffer)
	dirty:  bool,
}

terrain_create :: proc(width, height: i32, image_pixels: [^]u8) -> Terrain {
	size := int(width * height)

	mask := make([]u8, size)
	pixels := make([]u32, size)

	for i in 0 ..< size {
		r := image_pixels[i * 4 + 0]
		g := image_pixels[i * 4 + 1]
		b := image_pixels[i * 4 + 2]
		a := image_pixels[i * 4 + 3]

		// Store as RGBA u32 (assuming little-endian: ABGR in memory)
		pixels[i] = u32(r) | (u32(g) << 8) | (u32(b) << 16) | (u32(a) << 24)

		// Solid if alpha > 128
		mask[i] = a > 128 ? 1 : 0
	}

	return Terrain{width = width, height = height, mask = mask, pixels = pixels, dirty = true}
}

terrain_destroy :: proc(terrain: ^Terrain) {
	delete(terrain.mask)
	delete(terrain.pixels)
}

terrain_is_solid :: proc(terrain: ^Terrain, x, y: i32) -> bool {
	if x < 0 || x >= terrain.width || y < 0 || y >= terrain.height {
		return false
	}
	return terrain.mask[y * terrain.width + x] == 1
}

terrain_remove_circle :: proc(terrain: ^Terrain, cx, cy: i32, radius: i32) {
	for dy in -radius ..= radius {
		for dx in -radius ..= radius {
			if dx * dx + dy * dy <= radius * radius {
				terrain_remove_pixel(terrain, cx + dx, cy + dy)
			}
		}
	}
}

terrain_remove_rect :: proc(terrain: ^Terrain, r: Rect) {
	for dy in 0 ..< r.h {
		for dx in 0 ..< r.w {
			terrain_remove_pixel(terrain, i32(r.x + dx), i32(r.y + dy))
		}
	}
}

terrain_remove_pixel :: proc(terrain: ^Terrain, x, y: i32) {
	if x < 0 || x >= terrain.width || y < 0 || y >= terrain.height {
		return
	}

	idx := y * terrain.width + x
	if terrain.mask[idx] == 1 {
		terrain.mask[idx] = 0
		terrain.pixels[idx] = 0x00000000
		terrain.dirty = true
	}
}

// terrain_add_pixel :: proc(terrain: ^Terrain, x, y: i32, color: u32) {
// 	if x < 0 || x >= terrain.width || y < 0 || y >= terrain.height {
// 		return
// 	}

// 	idx := y * terrain.width + x
// 	terrain.mask[idx] = 1
// 	terrain.pixels[idx] = color
// 	terrain.dirty = true
// }

// Get the size in bytes for GPU upload
// terrain_get_pixel_size :: proc(terrain: ^Terrain) -> uint {
// 	return uint(terrain.width * terrain.height * 4)
// }
