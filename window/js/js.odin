#+build js
package window_js

import "core:sys/wasm/js"
import "vendor:wgpu"

import core "../../core"

@(private = "file")
js_on_resize: proc()

// Returns a Window_Backend vtable for JS/WASM.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = js_init,
		shutdown = js_shutdown,
		poll_events = js_poll_events,
		get_surface = js_get_surface,
		get_framebuffer_size = js_get_framebuffer_size,
	}
}

@(private = "file")
js_init :: proc(width, height: int, title: string, on_resize: proc()) {
	js_on_resize = on_resize
	ok := js.add_window_event_listener(.Resize, nil, js_size_callback)
	assert(ok)
}

@(private = "file")
js_shutdown :: proc() {
	js.remove_window_event_listener(.Resize, nil, js_size_callback)
}

@(private = "file")
js_poll_events :: proc() -> bool {
	return true
}

@(private = "file")
js_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor {
			nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector {
				sType = .SurfaceSourceCanvasHTMLSelector,
				selector = "#wgpu-canvas",
			},
		},
	)
}

@(private = "file")
js_get_framebuffer_size :: proc() -> (width, height: u32) {
	rect := js.get_bounding_client_rect("body")
	dpi := js.device_pixel_ratio()
	return u32(f64(rect.width) * dpi), u32(f64(rect.height) * dpi)
}

@(private = "file")
js_size_callback :: proc(e: js.Event) {
	if js_on_resize != nil {
		js_on_resize()
	}
}
