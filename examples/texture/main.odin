// odin run examples/texture
// odin run tools/build_web -- examples/texture --serve

package main

import w "../.."

checkerboard: w.Texture
logo: w.Texture

main :: proc() {
	w.init(1280, 720, "Texture Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	logo = w.load_texture(#load("logo.png"))
	checkerboard = create_checkerboard()
}

frame :: proc(dt: f32) {
	w.clear(w.DARK_GRAY)

	w.draw_texture(logo, {50, 50})
	w.draw_texture_rect(logo, {0, 0, 400, 400}, {450, 50, 200, 200})

	w.draw_texture(checkerboard, {50, 500})
	w.draw_texture_rect(
		checkerboard,
		w.Rect{0, 0, f32(checkerboard.width), f32(checkerboard.height)},
		w.Rect{200, 500, 256, 256},
	)

	w.present()
}

shutdown :: proc() {
	w.destroy_texture(&checkerboard)
	w.destroy_texture(&logo)
}

create_checkerboard :: proc() -> w.Texture {
	// Generate a 16x16 checkerboard pattern from raw RGBA8 pixel data.
	SIZE :: 16
	TILE :: 4
	pixels: [SIZE * SIZE * 4]u8

	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			i := (y * SIZE + x) * 4
			is_white := ((x / TILE) + (y / TILE)) % 2 == 0
			val: u8 = is_white ? 255 : 60
			pixels[i + 0] = val // R
			pixels[i + 1] = val // G
			pixels[i + 2] = val // B
			pixels[i + 3] = 255 // A
		}
	}

	return w.load_texture(pixels[:], SIZE, SIZE)
}
