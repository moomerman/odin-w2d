#+build !js
package engine

// Desktop side of the asset registry: disk reads and (in dev mode) the file
// watch list that drives hot reloading. See assets.odin for the registry.

import "core:fmt"
import "core:image"
import "core:os"
import "core:strings"
import "core:time"

// Only referenced in dev builds.
_ :: fmt
_ :: image
_ :: strings
_ :: time

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
	@(private = "file")
	ASSET_POLL_INTERVAL :: 0.25 // seconds between mtime sweeps

	@(private = "file")
	Watched_Kind :: enum {
		Texture,
		Shader,
	}

	@(private = "file")
	Watched_Asset :: struct {
		path:    string, // cloned, owned by the watch list
		kind:    Watched_Kind,
		mtime:   time.Time,
		texture: Texture_Handle,
		shader:  Shader_Handle,
		width:   int, // textures: last-known dimensions
		height:  int,
	}

	@(private = "file")
	watch_state: struct {
		entries:   [dynamic]Watched_Asset,
		last_poll: f64,
	}

	@(private = "package")
	assets_watch_add_texture :: proc(path: string, handle: Texture_Handle, width, height: int) {
		entry := watch_find_or_append(path, .Texture)
		entry.texture = handle
		entry.width = width
		entry.height = height
	}

	@(private = "package")
	assets_watch_add_shader :: proc(path: string, handle: Shader_Handle) {
		entry := watch_find_or_append(path, .Shader)
		entry.shader = handle
	}

	// Find the watch entry for path+kind, or append a fresh one. Re-loading
	// the same asset (e.g. on a level restart) re-targets the existing entry
	// rather than duplicating it.
	@(private = "file")
	watch_find_or_append :: proc(path: string, kind: Watched_Kind) -> ^Watched_Asset {
		for &entry in watch_state.entries {
			if entry.kind == kind && entry.path == path {
				return &entry
			}
		}
		mtime, _ := os.modification_time_by_path(path)
		append(
			&watch_state.entries,
			Watched_Asset{path = strings.clone(path), kind = kind, mtime = mtime},
		)
		return &watch_state.entries[len(watch_state.entries) - 1]
	}

	@(private = "package")
	assets_watch_shutdown :: proc() {
		for &entry in watch_state.entries {
			delete(entry.path)
		}
		delete(watch_state.entries)
		watch_state = {}
	}

	// Poll watched assets for changes and hot-reload any that were modified.
	// Called once per frame from the platform loop, between frames (no render
	// pass is active), and throttled internally to ASSET_POLL_INTERVAL.
	@(private = "package")
	assets_poll :: proc() {
		if ctx.elapsed_time - watch_state.last_poll < ASSET_POLL_INTERVAL {
			return
		}
		watch_state.last_poll = ctx.elapsed_time

		for &entry in watch_state.entries {
			mtime, mtime_err := os.modification_time_by_path(entry.path)
			if mtime_err != nil {
				// Editors often save via write-to-temp + rename; the file can
				// be momentarily absent. Retry next sweep.
				continue
			}
			// Compare with != rather than > — checkouts and copies can move
			// mtimes backwards.
			if mtime == entry.mtime {
				continue
			}

			data, read_ok := asset_read_disk(entry.path)
			if !read_ok || len(data) == 0 {
				continue // mid-write; retry next sweep
			}
			// If the file changed again while we were reading it, it is still
			// being written — drop this read and retry next sweep.
			mtime_after, after_err := os.modification_time_by_path(entry.path)
			if after_err != nil || mtime_after != mtime {
				delete(data)
				continue
			}

			// Record the mtime even when the new content fails to load, so a
			// broken file logs once per save instead of once per sweep.
			entry.mtime = mtime

			switch entry.kind {
			case .Texture:
				watch_reload_texture(&entry, data)
			case .Shader:
				if ctx.renderer.reload_shader(entry.shader, string(data)) {
					fmt.printfln("[assets] reloaded shader: %s", entry.path)
				} else {
					fmt.eprintfln(
						"[assets] shader reload failed, keeping previous: %s",
						entry.path,
					)
				}
			}
			delete(data)
		}
	}

	@(private = "file")
	watch_reload_texture :: proc(entry: ^Watched_Asset, data: []u8) {
		img, img_err := decode_image(data)
		if img_err != nil {
			fmt.eprintfln(
				"[assets] texture reload failed (%v), keeping previous: %s",
				img_err,
				entry.path,
			)
			return
		}
		defer image.destroy(img)

		if img.width != entry.width || img.height != entry.height {
			fmt.eprintfln(
				"[assets] %s resized %dx%d -> %dx%d — Texture structs held by the game keep the old size; keep dimensions stable for best results",
				entry.path,
				entry.width,
				entry.height,
				img.width,
				img.height,
			)
			entry.width = img.width
			entry.height = img.height
		}

		ctx.renderer.reload_texture(entry.texture, img.pixels.buf[:], img.width, img.height)
		fmt.printfln("[assets] reloaded texture: %s", entry.path)
	}
}
