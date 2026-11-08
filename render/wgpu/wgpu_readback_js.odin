#+build js
package renderer_wgpu

// Pixel readback is desktop only: on web, buffer maps resolve on a later
// browser task, so a blocking read inside the frame is impossible.

import "base:runtime"

import core "../../core"

@(private = "package")
renderer_read_pixels :: proc(
	allocator: runtime.Allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	return
}

@(private = "package")
renderer_read_texture :: proc(
	handle: core.Texture_Handle,
	allocator: runtime.Allocator,
) -> (
	pixels: []u8,
	width, height: int,
	ok: bool,
) {
	return
}
