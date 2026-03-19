#+build js
package window_js

import "core:sys/wasm/js"
import "vendor:wgpu"

import core "../../core"

@(private = "file")
js_on_resize: proc()

@(private = "file")
js_events: [dynamic]core.Event

// Returns a Window_Backend vtable for JS/WASM.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = js_init,
		shutdown = js_shutdown,
		poll_events = js_poll_events,
		get_surface = js_get_surface,
		get_framebuffer_size = js_get_framebuffer_size,
		get_events = js_get_events,
	}
}

@(private = "file")
js_init :: proc(width, height: int, title: string, on_resize: proc()) {
	js_on_resize = on_resize
	ok := js.add_window_event_listener(.Resize, nil, js_size_callback)
	assert(ok)

	js.add_event_listener("wgpu-canvas", .Mouse_Move, nil, js_mouse_move_callback)
	js.add_event_listener("wgpu-canvas", .Mouse_Down, nil, js_mouse_button_callback)
	js.add_event_listener("wgpu-canvas", .Mouse_Up, nil, js_mouse_button_callback)
}

@(private = "file")
js_shutdown :: proc() {
	js.remove_window_event_listener(.Resize, nil, js_size_callback)

	js.remove_event_listener("wgpu-canvas", .Mouse_Move, nil, js_mouse_move_callback)
	js.remove_event_listener("wgpu-canvas", .Mouse_Down, nil, js_mouse_button_callback)
	js.remove_event_listener("wgpu-canvas", .Mouse_Up, nil, js_mouse_button_callback)
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
js_get_events :: proc() -> []core.Event {
	events := js_events[:]
	clear(&js_events)
	return events
}

@(private = "file")
js_size_callback :: proc(e: js.Event) {
	if js_on_resize != nil {
		js_on_resize()
	}
}

@(private = "file")
js_mouse_move_callback :: proc(e: js.Event) {
	append(
		&js_events,
		core.Event(
			core.Mouse_Move_Event {
				pos = {f32(e.mouse.client[0]), f32(e.mouse.client[1])},
				delta = {f32(e.mouse.movement[0]), f32(e.mouse.movement[1])},
			},
		),
	)
}

@(private = "file")
js_mouse_button_callback :: proc(e: js.Event) {
	btn: core.Mouse_Button
	switch e.mouse.button {
	case 0:
		btn = .Left
	case 1:
		btn = .Middle
	case 2:
		btn = .Right
	case:
		return
	}
	append(
		&js_events,
		core.Event(
			core.Mouse_Button_Event {
				button = btn,
				down = e.kind == .Mouse_Down,
				pos = {f32(e.mouse.client[0]), f32(e.mouse.client[1])},
			},
		),
	)
}
