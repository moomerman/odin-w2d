#+build !js
package engine

import "core:image"
import "core:image/png"
import "core:slice"

// read_pixels, then encode the result as a PNG at path. Same timing rules
// as read_pixels. Desktop only.
save_screenshot :: proc(path: string) -> bool {
	pixels, width, height, ok := read_pixels()
	if !ok {
		return false
	}
	defer delete(pixels)
	return save_png(path, pixels, width, height)
}

// read_render_texture, then encode the result as a PNG at path: the
// texture's exact pixel size, straight alpha. Same timing rules as
// read_render_texture. Desktop only.
save_render_texture :: proc(rt: Render_Texture, path: string) -> bool {
	pixels, width, height, ok := read_render_texture(rt)
	if !ok {
		return false
	}
	defer delete(pixels)
	return save_png(path, pixels, width, height)
}

// Encode tightly packed RGBA8 as a PNG file.
@(private = "file")
save_png :: proc(path: string, pixels: []u8, width, height: int) -> bool {
	img := image.Image {
		width    = width,
		height   = height,
		channels = 4,
		depth    = 8,
		pixels   = slice.into_dynamic(pixels),
	}
	// into_dynamic wraps the slice with len 0; grow to cap without allocating.
	non_zero_resize(&img.pixels, len(pixels))
	return png.save_to_file(path, &img) == nil
}
