// Asset registry: a two-mode virtual file system for path-based asset loading.
//
// Release (default): games embed assets at compile time and register them once:
//
//	assets := #load_directory("assets")
//	w.register_assets("assets", assets)
//
// The `load_*_from_file` procs then resolve paths like "assets/player.png"
// from the in-memory registry — one self-contained binary on desktop and web,
// same as #load. Paths outside the registry fall back to a plain disk read on
// desktop (relative to the working directory), so loose files keep working.
//
// Dev (-define:W2D_DEV=true): the same loader calls read from disk relative to
// the current working directory (live files win over the registry), and on
// desktop the engine watches loaded files for changes, hot-reloading them in
// place behind their existing handles. See assets_desktop.odin.
package engine

import "base:runtime"
import "core:fmt"
import "core:strings"

// True when built with -define:W2D_DEV=true. Enables disk-first asset
// resolution and hot reloading on desktop. Web builds compile but degrade to
// registry-only resolution.
DEV :: #config(W2D_DEV, false)

@(private = "package")
Asset_Registry :: struct {
	// "assets/player.png" -> embedded bytes. Keys are cloned and owned by the
	// registry; values reference #load_directory data, which is static for the
	// program lifetime and must not be freed.
	files:              map[string][]u8,
	// Dev-mode disk reads for fonts. fontstash references the TTF bytes
	// without copying them, so they must outlive the font.
	retained_font_data: [dynamic][]u8,
}

@(private = "package")
asset_registry: Asset_Registry

// Register embedded assets under a path prefix. Call once per directory at
// startup, before any `load_*_from_file` calls:
//
//	w.register_assets("assets", #load_directory("assets"))
//
// #load_directory is non-recursive, so games with subdirectories register
// each one ("assets/sfx", "assets/music", ...). Paths use forward slashes.
register_assets :: proc(prefix: string, files: []runtime.Load_Directory_File) {
	clean_prefix := strings.trim_prefix(prefix, "./")
	for file in files {
		key := fmt.aprintf("%s/%s", clean_prefix, file.name)
		if key in asset_registry.files {
			fmt.eprintfln("[assets] duplicate asset registered, overwriting: %s", key)
			asset_registry.files[key] = file.data
			delete(key) // map keeps its existing key string
		} else {
			asset_registry.files[key] = file.data
		}
	}
}

// Resolve an asset path to its bytes. In dev mode the disk is checked first
// (live files win) with the registry as fallback; in release the registry is
// checked first, falling back to disk for unregistered paths (desktop only —
// there is no disk on web). `owned` is true when the caller is responsible
// for the returned memory (disk reads only).
@(private = "package")
asset_resolve :: proc(path: string) -> (data: []u8, owned: bool, ok: bool) {
	when DEV {
		if disk_data, disk_ok := asset_read_disk(path); disk_ok {
			return disk_data, true, true
		}
	}
	if reg_data, found := asset_registry.files[path]; found {
		return reg_data, false, true
	}
	when !DEV {
		if disk_data, disk_ok := asset_read_disk(path); disk_ok {
			return disk_data, true, true
		}
	}
	return nil, false, false
}

@(private = "file")
asset_resolve_or_panic :: proc(path: string) -> (data: []u8, owned: bool) {
	resolved, is_owned, ok := asset_resolve(path)
	if !ok {
		fmt.panicf(
			"[assets] asset not found: %q — not in the registry and not on disk " +
			"(disk paths resolve relative to the working directory; web builds " +
			"resolve from the registry only — did you call register_assets?)",
			path,
		)
	}
	return resolved, is_owned
}

// Load a texture from a registered asset path, or from a file on disk
// (desktop only). In dev mode the file is watched and hot-reloaded in place
// when it changes.
load_texture_from_file :: proc(path: string) -> Texture {
	data, owned := asset_resolve_or_panic(path)
	tex := load_texture(data)
	if owned {
		delete(data)
	}
	when DEV {
		assets_watch_add_texture(path, tex.handle, tex.width, tex.height)
	}
	return tex
}

// Load a custom WGSL shader from a registered asset path, or from a file on
// disk (desktop only). In dev mode the file is watched and recompiled in
// place when it changes; if the new source fails to compile, the previous
// shader is kept.
load_shader_from_file :: proc(path: string) -> Shader {
	data, owned := asset_resolve_or_panic(path)
	shader := load_shader(string(data))
	if owned {
		delete(data)
	}
	when DEV {
		assets_watch_add_shader(path, shader.handle)
	}
	return shader
}

// Load a TTF font from a registered asset path, or from a file on disk
// (desktop only). The font bytes are retained for the lifetime of the engine
// (the text system references them without copying). Fonts are not
// hot-reloaded.
load_font_from_file :: proc(path: string) -> Font {
	data, owned := asset_resolve_or_panic(path)
	font := load_font(data)
	if owned {
		append(&asset_registry.retained_font_data, data)
	}
	return font
}

// Free registry bookkeeping. Called internally from engine_shutdown.
@(private = "package")
assets_shutdown :: proc() {
	for key in asset_registry.files {
		delete(key)
	}
	delete(asset_registry.files)
	asset_registry.files = {}

	for data in asset_registry.retained_font_data {
		delete(data)
	}
	delete(asset_registry.retained_font_data)
	asset_registry.retained_font_data = {}

	when DEV {
		assets_watch_shutdown()
	}
}
