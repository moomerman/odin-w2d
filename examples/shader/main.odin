// odin run examples/shader
// odin run tools/build_web -- examples/shader --serve

package main

import w "../.."

logo: w.Texture
scanline_shader: w.Shader

main :: proc() {
	w.init(1280, 720, "Shader Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	logo = w.load_texture(#load("../texture/logo.png"))
	scanline_shader = w.load_shader(#load("scanline.wgsl"))

	// Set initial uniform values
	w.set_shader_uniform(&scanline_shader, "intensity", f32(0.3))
	w.set_shader_uniform(&scanline_shader, "line_spacing", f32(3.0))
}

frame :: proc(dt: f32) {
	w.clear(w.DARK_GRAY)

	// Draw some quads with the default shader
	w.draw_rect({50, 50, 200, 200}, w.BLUE)
	w.draw_rect({300, 50, 200, 200}, w.GREEN)

	// Switch to the scanline shader
	w.set_shader(&scanline_shader)
	w.set_shader_uniform(&scanline_shader, "time", f32(w.get_time()))

	// These draws use the scanline effect
	w.draw_texture(logo, {50, 300})
	w.draw_rect({600, 300, 200, 200}, w.RED)

	// Switch back to default
	w.reset_shader()

	// This draw uses the default shader again
	w.draw_rect({600, 50, 200, 200}, w.ORANGE)

	w.draw_stats()
	w.present()
}

shutdown :: proc() {
	w.destroy_shader(&scanline_shader)
	w.destroy_texture(&logo)
}
