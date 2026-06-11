#+build !js
package engine

// Desktop side of the asset registry: disk reads and (in dev mode) the file
// watch list that drives hot reloading. See assets.odin for the registry.

import "core:os"

// Read an asset from disk relative to the current working directory.
@(private = "package")
asset_read_disk :: proc(path: string) -> ([]u8, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return nil, false
	}
	return data, true
}

when DEV {
	// Watch list scaffolding — filled in by the hot reload milestone (M2).

	@(private = "package")
	assets_watch_add_texture :: proc(path: string, handle: Texture_Handle, width, height: int) {
		_ = path
		_ = handle
		_ = width
		_ = height
	}

	@(private = "package")
	assets_watch_add_shader :: proc(path: string, handle: Shader_Handle) {
		_ = path
		_ = handle
	}

	@(private = "package")
	assets_watch_shutdown :: proc() {
	}

	// Poll watched assets for changes. Called once per frame from the
	// platform loop; throttled internally.
	@(private = "package")
	assets_poll :: proc() {
	}
}
