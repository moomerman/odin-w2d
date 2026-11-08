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
