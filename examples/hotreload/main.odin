// Asset registry + hot reload example.
//
// Release (assets embedded in the binary, runs from any directory):
//	odin run examples/hotreload
//	odin run tools/build_web -- examples/hotreload --serve
//
// Dev mode (assets read from disk and hot-reloaded on save):
//	cd examples/hotreload && odin run . -define:W2D_DEV=true
//
// In dev mode, edit assets/player.png or assets/effect.wgsl in another
// program and save — the running game picks up the change within ~250ms.
package main

import w "../.."
import ta "../../tools/tracking_allocator"

// Embed the assets directory at compile time and register it with the engine.
// In dev builds the registry is bypassed in favor of the live files on disk.
embedded_assets := #load_directory("assets")

player: w.Texture
effect: w.Shader
click: w.Audio_Source

main :: proc() {
	context.allocator = ta.init()
	defer {
		ta.print()
		ta.destroy()
	}
	w.init(1280, 720, "Hot Reload Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	w.register_assets("assets", embedded_assets)

	player = w.load_texture_from_file("assets/player.png")

	effect = w.load_shader_from_file("assets/effect.wgsl")
	w.set_shader_uniform(&effect, "intensity", f32(0.4))
	w.set_shader_uniform(&effect, "line_spacing", f32(4.0))

	w.init_audio()
	click = w.load_audio("assets/click.wav")
}

frame :: proc(dt: f32) {
	w.clear(w.DARK_GRAY)

	// Draw the texture twice: plain, and through the custom shader.
	w.draw_texture(player, {160, 200})

	w.set_shader(&effect)
	w.set_shader_uniform(&effect, "time", f32(w.get_time()))
	w.draw_texture(player, {700, 200})
	w.reset_shader()

	if w.key_went_down(.Space) {
		w.play_audio(click)
	}

	when w.DEV {
		w.draw_text(
			"DEV MODE: edit assets/player.png or assets/effect.wgsl and save",
			{50, 50},
			20,
		)
	} else {
		w.draw_text(
			"Release mode (assets embedded) — for hot reload run: cd examples/hotreload && odin run . -define:W2D_DEV=true",
			{50, 50},
			18,
		)
	}
	w.draw_text("SPACE plays a click", {50, 84}, 20)

	w.draw_stats()
	w.present()
}

shutdown :: proc() {
	w.destroy_audio(click)
	w.shutdown_audio()
	w.destroy_shader(&effect)
	w.destroy_texture(&player)
}
