// odin run examples/text
package main

import w "../.."

main :: proc() {
	w.init(1280, 720, "Text Rendering")
	w.run(init, frame, shutdown)
}

init :: proc() {}

frame :: proc(dt: f32) {
	w.clear(w.DARK_GRAY)

	// Different sizes
	w.draw_text("Hello, World!", {50, 50}, 48)
	w.draw_text("Text rendering with fontstash", {50, 120}, 32)
	w.draw_text("Small text at 16px", {50, 170}, 16)

	// Different colors
	w.draw_text("Red text", {50, 220}, 32, w.RED)
	w.draw_text("Green text", {50, 270}, 32, w.GREEN)
	w.draw_text("Blue text", {50, 320}, 32, w.BLUE)
	w.draw_text("Yellow text", {50, 370}, 32, w.YELLOW)

	// Measure text for positioning
	label := "Centered text"
	size := w.measure_text(label, 32)
	w.draw_text(label, {(1280 - size.x) / 2, 450}, 32, w.ORANGE)

	// Draw a rect behind measured text
	info := "Text with background"
	info_size := w.measure_text(info, 24)
	w.draw_rect({48, 518, info_size.x + 4, info_size.y + 4}, {0, 0, 0, 128})
	w.draw_text(info, {50, 520}, 24)

	// Outlined text
	w.draw_text_outlined("Outlined text!", {50, 580}, 48, w.WHITE, w.BLACK)
	w.draw_text_outlined("Thick outline", {50, 640}, 36, w.YELLOW, w.DARK_RED, 2)

	w.present()
}

shutdown :: proc() {}
