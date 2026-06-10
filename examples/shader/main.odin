// odin run examples/shader
// odin run tools/build_web -- examples/shader --serve

package main

import "core:math"

import w "../.."

logo: w.Texture
lut: w.Texture
scanline_shader: w.Shader
lut_shader: w.Shader

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

	// Build a 256x1 fire-palette gradient (black -> red -> yellow -> white)
	// and bind it to the LUT shader's group-1 texture binding.
	pixels: [256 * 4]u8
	for i in 0 ..< 256 {
		t := f32(i) / 255.0
		r := clamp(t * 3.0, 0.0, 1.0)
		g := clamp(t * 3.0 - 1.0, 0.0, 1.0)
		b := clamp(t * 3.0 - 2.0, 0.0, 1.0)
		pixels[i * 4 + 0] = u8(r * 255.0)
		pixels[i * 4 + 1] = u8(g * 255.0)
		pixels[i * 4 + 2] = u8(b * 255.0)
		pixels[i * 4 + 3] = 255
	}
	lut = w.load_texture(pixels[:], 256, 1)

	lut_shader = w.load_shader(#load("lut.wgsl"))
	w.set_shader_texture(&lut_shader, "lut", lut)
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

	// Switch to the LUT shader, fading the effect in and out over time
	w.set_shader(&lut_shader)
	mix_amount := f32(math.sin(w.get_time()) * 0.5 + 0.5)
	w.set_shader_uniform(&lut_shader, "mix_amount", mix_amount)
	w.draw_texture(logo, {850, 300})

	// Switch back to default
	w.reset_shader()

	// This draw uses the default shader again
	w.draw_rect({600, 50, 200, 200}, w.ORANGE)

	w.draw_stats()
	w.present()
}

shutdown :: proc() {
	w.destroy_shader(&lut_shader)
	w.destroy_shader(&scanline_shader)
	w.destroy_texture(&lut)
	w.destroy_texture(&logo)
}
