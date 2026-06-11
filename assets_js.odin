#+build js
package engine

// Web side of the asset registry. There is no disk on wasm, so dev mode
// degrades to registry-only resolution and nothing is watched.

@(private = "package")
asset_read_disk :: proc(path: string) -> ([]u8, bool) {
	_ = path
	return nil, false
}

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
