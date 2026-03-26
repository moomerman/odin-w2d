// odin run examples/slug-text
//
// Demonstrates GPU-evaluated Bezier text rendering (Slug algorithm)
// alongside the engine's built-in fontstash text. Slug renders crisp,
// resolution-independent text at any size or rotation.
package main

import "vendor:wgpu"

import w "../.."
import slug "../../.deps/github.com/moomerman/odin-slug/slug"
import slug_wgpu "../../.deps/github.com/moomerman/odin-slug/slug/backends/wgpu"

ROBOTO :: #load("../../fonts/roboto.ttf")
MONO :: #load("BerkeleyMono-Regular.ttf")

slug_renderer: slug_wgpu.Renderer

main :: proc() {
	w.init(1280, 720, "Slug Text Rendering")
	w.run(init, frame, shutdown)
}

init :: proc() {
	device := wgpu.Device(w.get_gpu_device())
	queue := wgpu.Queue(w.get_gpu_queue())
	format := wgpu.TextureFormat(w.get_surface_format())

	slug_wgpu.init(&slug_renderer, device, queue, format)

	// Load fonts into slug — slot 0 = Roboto, slot 1 = Berkeley Mono.
	slug_wgpu.load_fonts_shared_mem(&slug_renderer, {ROBOTO, MONO})

	// Hook slug flush into the render pass before present.
	w.set_pre_present_callback(proc(pass: rawptr, width, height: u32) {
		slug_wgpu.flush(&slug_renderer, wgpu.RenderPassEncoder(pass), width, height)
	})
}

frame :: proc(dt: f32) {
	w.clear(w.DARK_GRAY)

	t := f32(w.get_time())
	ctx := slug_wgpu.ctx(&slug_renderer)
	font := slug.active_font(ctx)

	slug.begin(ctx)

	// --- Left column: engine fontstash text ---

	w.draw_text("Engine text (fontstash)", {40, 30}, 28, w.LIGHT_GRAY)
	w.draw_text("Rasterized glyphs in a texture atlas.", {40, 65}, 18)
	w.draw_text("Red", {40, 100}, 24, w.RED)
	w.draw_text("Green", {100, 100}, 24, w.GREEN)
	w.draw_text("Blue", {190, 100}, 24, w.BLUE)
	w.draw_text_outlined("Outlined text", {40, 140}, 32, w.WHITE, w.BLACK)

	// --- Right column: slug GPU Bezier text ---

	// Slug uses baseline-left coordinates. Ascent converts top-left to baseline.
	ascent := font.ascent

	slug.draw_text(ctx, "Slug text (GPU Bezier)", 640, 30 + ascent * 28, 28, slug.LIGHT_GRAY)
	slug.draw_text(
		ctx,
		"Per-pixel curve evaluation, crisp at any size.",
		640,
		65 + ascent * 18,
		18,
		slug.WHITE,
	)

	// Colors
	slug.draw_text(ctx, "Red", 640, 100 + ascent * 24, 24, slug.RED)
	slug.draw_text(ctx, "Green", 700, 100 + ascent * 24, 24, slug.GREEN)
	slug.draw_text(ctx, "Blue", 800, 100 + ascent * 24, 24, slug.BLUE)

	// Outlined
	slug.draw_text_outlined(ctx, "Outlined text", 640, 140 + ascent * 32, 32, slug.WHITE)

	// --- Resolution independence showcase ---

	slug.draw_text(ctx, "HUGE", 640, 200 + ascent * 96, 96, slug.ORANGE)
	slug.draw_text(ctx, "Crisp at any size!", 640, 310 + ascent * 14, 14, slug.LIGHT_GRAY)

	// Custom font (slot 1 = Berkeley Mono)
	slug.use_font(ctx, 1)
	slug.draw_text(ctx, "Berkeley Mono (Slug)", 640, 350 + ascent * 22, 22, slug.LIGHT_GRAY)
	slug.use_font(ctx, 0) // switch back to Roboto

	// --- Effects showcase (slug only) ---

	y_base: f32 = 420

	// Rainbow
	slug.draw_text_rainbow(ctx, "Rainbow text!", 40, y_base + ascent * 36, 36, t)

	// Wobble
	slug.draw_text_wobble(
		ctx,
		"Wobble wobble",
		40,
		y_base + 60 + ascent * 32,
		32,
		t,
		6.0,
		4.0,
		0.5,
		slug.Color{0.4, 0.75, 1.0, 1.0},
	)

	// Shake
	slug.draw_text_shake(ctx, "DANGER!", 380, y_base + 60 + ascent * 32, 32, 3.0, t, slug.RED)

	// Wave
	slug.draw_text_on_wave(
		ctx,
		"Flowing wave text",
		40,
		y_base + 130 + ascent * 28,
		28,
		12.0,
		250.0,
		t * 2.0,
		slug.Color{0.78, 0.48, 1.0, 1.0},
	)

	// Shadow
	slug.draw_text_shadow(ctx, "Drop shadow", 640, y_base + ascent * 36, 36, slug.WHITE, 3.0)

	// Gradient
	slug.draw_text_gradient(
		ctx,
		"Gradient text",
		640,
		y_base + 50 + ascent * 36,
		36,
		slug.YELLOW,
		slug.RED,
	)

	// Pulse
	slug.draw_text_pulse(ctx, "Pulsing!", 640, y_base + 100 + ascent * 32, 32, slug.GREEN, t, 0.4)

	// Typewriter
	slug.draw_text_typewriter(
		ctx,
		"The quick brown fox jumps over the lazy dog.",
		640,
		y_base + 150 + ascent * 20,
		20,
		slug.LIGHT_GRAY,
		t,
		8.0,
	)

	// Rotated
	slug.draw_text_rotated(ctx, "Rotated!", 900, 600, 28, t * 0.5, slug.Color{0.4, 0.75, 1.0, 1.0})

	// Circular
	slug.draw_text_on_circle(
		ctx,
		"* CIRCULAR TEXT * AROUND A POINT *",
		300,
		620,
		80,
		t * 0.3,
		16,
		slug.ORANGE,
	)

	slug.end(ctx)

	// Stats bar (engine text)
	w.draw_stats()

	w.present()
}

shutdown :: proc() {
	slug_wgpu.destroy(&slug_renderer)
}
