// odin run examples/hello
// odin run tools/build_web -- examples/hello --serve
package main

import w "../.."

main :: proc() {
	w.init(1280, 720, "Hello WGPU 2D!")
	w.run(init, frame, shutdown)
}

init :: proc() {}

frame :: proc(dt: f32) {
	w.clear(w.LIGHT_BLUE)
	w.draw_rect({50, 50, 200, 100}, w.DARK_BLUE)
	w.draw_rect({100, 100, 300, 200}, w.RED)
	w.draw_rect({450, 150, 200, 200}, w.BLUE)
	w.draw_rect({700, 100, 250, 300}, w.GREEN)
	w.draw_rect({200, 400, 400, 100}, w.ORANGE)
	w.draw_rect({650, 450, 150, 150}, w.PURPLE)
	w.present()
}

shutdown :: proc() {}
