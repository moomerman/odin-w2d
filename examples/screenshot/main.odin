// Screenshot example — draw a known picture, read it back, save a PNG and exit.
// Also checks read_pixels and read_render_texture against the colours drawn.
// Exits with status 1 if any check fails. Desktop only.
//
// odin run examples/screenshot
package main

import "core:fmt"
import "core:os"

import w "../.."

RT_SIZE :: 8
RT_FILL :: w.Color{10, 200, 30, 255}
RT_HALF :: w.Color{250, 120, 5, 255}

// A frame is only skipped while the surface is lost or resizing (an
// occluded or not-yet-shown window draws offscreen instead), so readback
// normally succeeds on the first frame. Try each frame until a screenshot
// lands, for up to this many seconds.
TIMEOUT :: 5.0

rt: w.Render_Texture
failures: int
saved: bool

main :: proc() {
	w.init(640, 360, "Screenshot Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	rt = w.create_render_texture(RT_SIZE, RT_SIZE)
}

frame :: proc(dt: f32) {
	if saved || w.get_time() > TIMEOUT {
		if !saved {
			fail("no frame could be read back in %v seconds", TIMEOUT)
		}
		// Between frames (no pass active): the standalone readback path.
		check_render_texture("between frames")
		fmt.println(failures == 0 ? "ok" : "FAILED")
		os.exit(failures == 0 ? 0 : 1)
	}

	w.clear({40, 40, 40, 255})

	// Render texture: a known fill, with the right half overdrawn opaquely.
	w.set_render_texture(rt, RT_FILL)
	w.draw_rect({RT_SIZE / 2, 0, RT_SIZE / 2, RT_SIZE}, RT_HALF)
	w.reset_render_texture()

	// An asymmetric picture: orientation and channel order are both visible.
	w.draw_rect({0, 0, 320, 180}, w.RED) // top-left
	w.draw_rect({320, 0, 320, 180}, w.GREEN) // top-right
	w.draw_rect({0, 180, 320, 180}, w.BLUE) // bottom-left
	w.draw_circle({480, 270}, 60, w.YELLOW) // bottom-right, on grey
	w.draw_text("TOP LEFT", {16, 16}, 32, w.WHITE)
	w.draw_texture_rect(rt.texture, {0, 0, RT_SIZE, RT_SIZE}, {280, 140, 80, 80})

	// Readback fails only when this frame was skipped; try again next frame.
	if _, _, _, ok := w.read_pixels(context.temp_allocator); ok {
		check_render_texture("in frame")
		check_screen()
		// Drawing continues after a readback: this lands in the screenshot.
		w.draw_rect({600, 320, 40, 40}, w.MAGENTA)
		if w.save_screenshot("screenshot.png") {
			fmt.println("wrote screenshot.png")
		} else {
			fail("save_screenshot failed")
		}
		saved = true
	}

	w.present()
	free_all(context.temp_allocator)
}

shutdown :: proc() {
	w.destroy_render_texture(&rt)
}

check_render_texture :: proc(label: string) {
	pixels, width, height, ok := w.read_render_texture(rt)
	defer delete(pixels)
	if !ok || width != RT_SIZE || height != RT_SIZE || len(pixels) != RT_SIZE * RT_SIZE * 4 {
		fail(
			"%s: read_render_texture ok=%v size=%dx%d len=%d",
			label,
			ok,
			width,
			height,
			len(pixels),
		)
		return
	}
	for y in 0 ..< RT_SIZE {
		for x in 0 ..< RT_SIZE {
			want := x < RT_SIZE / 2 ? RT_FILL : RT_HALF
			i := (y * RT_SIZE + x) * 4
			got := w.Color{pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]}
			if got != want {
				fail("%s: render texture (%d,%d) = %v, want %v", label, x, y, got, want)
				return
			}
		}
	}
}

check_screen :: proc() {
	pixels, width, height, ok := w.read_pixels()
	defer delete(pixels)
	sw, sh := w.get_screen_size()
	if !ok || width < sw || height < sh || len(pixels) != width * height * 4 {
		fail("read_pixels ok=%v size=%dx%d len=%d", ok, width, height, len(pixels))
		return
	}
	scale := width / sw
	probe :: proc(pixels: []u8, width, scale, x, y: int, want: w.Color) -> bool {
		i := ((y * scale) * width + x * scale) * 4
		got := w.Color{pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]}
		if got != want {
			fail("screen (%d,%d) = %v, want %v", x, y, got, want)
			return false
		}
		return true
	}
	probe(pixels, width, scale, 200, 100, w.RED)
	probe(pixels, width, scale, 600, 100, w.GREEN)
	probe(pixels, width, scale, 100, 300, w.BLUE)
	probe(pixels, width, scale, 620, 340, {40, 40, 40, 255})
	probe(pixels, width, scale, 480, 270, w.YELLOW)
	fmt.printfln("read_pixels: %dx%d (scale %d)", width, height, scale)
}

fail :: proc(format: string, args: ..any) {
	failures += 1
	fmt.eprintfln(format, ..args)
}
