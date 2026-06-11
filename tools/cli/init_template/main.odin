package main

import w2 "../../.."

// texture: w2.Texture

main :: proc() {
	w2.init(1024, 768, "w2d init")
	w2.run(init, frame, shutdown)
}

init :: proc() {
	// w2.init_audio()
	// w2.register_assets("assets", #load_directory("assets"))
	// texture = w2.load_texture_from_file("assets/texture.png")
}

frame :: proc(dt: f32) {
	{ 	// input
	}

	{ 	// update
	}

	{ 	// draw
		w2.clear(w2.GREEN)

		// w2.draw_texture(texture, {})
	}

	w2.present()
	free_all(context.temp_allocator)
}

shutdown :: proc() {
	// w2.destroy_texture(&texture)
}
