// odin run examples/lighting
// odin run tools/build_web -- examples/lighting --serve
//
// Exercises shader and blend-mode features that are easy to regress:
//   - left:   lights computed in a shader from array<T, N> uniforms
//   - right:  a light map built with .Additive blending in a render
//             texture, then composited onto the scene with .Multiply
//   - corner: a shader that fails to compile on first load. The error is
//             logged, the app keeps running, and draws fall back to the
//             default shader (white square).

package main

import "core:fmt"
import "core:math"

import w "../.."

// Intentionally invalid WGSL.
BROKEN_WGSL :: `
@fragment fn fs_main() -> @location(0) vec4<f32> { return this is not wgsl; }
`

lights_shader: w.Shader
broken_shader: w.Shader
light_map: w.Render_Texture

main :: proc() {
	w.init(800, 400, "Lighting Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	lights_shader = w.load_shader(#load("lights.wgsl"))

	ok: bool
	broken_shader, ok = w.load_shader(BROKEN_WGSL)
	fmt.println("broken shader compiled:", ok, "(expected false)")

	light_map = w.create_render_texture(400, 400)
}

frame :: proc(dt: f32) {
	t := f32(w.get_time())
	w.clear(w.DARK_GRAY)

	// Left: three orbiting lights, passed to the shader as arrays. pos is a
	// fixed array of vec4s; col is a slice of [3]f32 that the engine copies
	// into the 16-byte vec3 array stride.
	pos: [3][4]f32
	for i in 0 ..< 3 {
		a := t + f32(i) * math.TAU / 3
		pos[i] = {200 + math.cos(a) * 70, 200 + math.sin(a) * 70, 180, 0}
	}
	col := [][3]f32{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}

	w.set_shader(&lights_shader)
	w.set_shader_uniform(&lights_shader, "count", u32(len(pos)))
	w.set_shader_uniform(&lights_shader, "pos", pos)
	w.set_shader_uniform(&lights_shader, "col", col)
	w.draw_rect({0, 0, 400, 400}, w.WHITE)
	w.reset_shader()

	// Right: build a light map additively (overlaps mix to yellow, cyan,
	// magenta and white), then multiply it over a white scene. The blend
	// mode persists across the render-target switch.
	w.set_render_texture(light_map, w.BLACK)
	w.set_blend_mode(.Additive)
	w.draw_circle({150, 150}, 120, {255, 0, 0, 255}, 48)
	w.draw_circle({250, 150}, 120, {0, 255, 0, 255}, 48)
	w.draw_circle({200, 250}, 120, {0, 0, 255, 255}, 48)
	w.reset_render_texture()
	w.reset_blend_mode()

	w.draw_rect({400, 0, 400, 400}, w.WHITE)
	w.set_blend_mode(.Multiply)
	w.draw_texture(light_map.texture, {400, 0})
	w.reset_blend_mode()

	// Corner: the broken shader falls back to the default pipeline.
	w.set_shader(&broken_shader)
	w.draw_rect({760, 360, 30, 30}, w.WHITE)
	w.reset_shader()

	w.present()
}

shutdown :: proc() {
	w.destroy_render_texture(&light_map)
	w.destroy_shader(&broken_shader)
	w.destroy_shader(&lights_shader)
}
