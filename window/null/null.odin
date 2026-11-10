// Null window backend: no OS window, no GPU surface and no OS events.
//
// Used by init_headless for tests and CI. The renderer sees a nil surface
// and draws every frame into its offscreen target, so drawing, readback
// (read_pixels, save_screenshot) and render textures work as usual; nothing
// is ever shown. Input comes from the engine's inject_* procs, or, to test
// how the engine treats window input, from push_event.
//
// `scale` stands in for a display's backing scale factor: the framebuffer is
// the logical size multiplied by it, so HiDPI code paths can be exercised on
// any machine.

package window_null

import core "../../core"

@(private = "file")
state: struct {
	width:     int,
	height:    int,
	scale:     f32,
	on_resize: proc(),
	events:    [dynamic]core.Event,
}

// Returns a Window_Backend vtable for a window that does not exist.
backend :: proc(scale: f32 = 1) -> core.Window_Backend {
	state.scale = scale > 0 ? scale : 1
	return core.Window_Backend {
		init = null_init,
		shutdown = null_shutdown,
		poll_events = null_poll_events,
		get_surface = null_get_surface,
		get_framebuffer_size = null_get_framebuffer_size,
		get_window_size = null_get_window_size,
		get_events = null_get_events,
		set_cursor_visible = null_set_cursor_visible,
		set_system_cursor = null_set_system_cursor,
		set_custom_cursor = null_set_custom_cursor,
		set_window_mode = null_set_window_mode,
	}
}

// Change the logical size, as a user resizing a window would. Calls the
// engine's resize callback when the size changes.
resize :: proc(width, height: int) {
	if width == state.width && height == state.height {
		return
	}
	state.width = width
	state.height = height
	if state.on_resize != nil {
		state.on_resize()
	}
}

// Queue an event as if the OS had delivered it to the window: the engine
// receives it from get_events at the start of the next frame.
push_event :: proc(event: core.Event) {
	append(&state.events, event)
}

@(private = "file")
null_init :: proc(width, height: int, _: string, on_resize: proc()) {
	state.width = width
	state.height = height
	state.on_resize = on_resize
}

@(private = "file")
null_shutdown :: proc() {
	delete(state.events)
	state = {}
}

// Never asks to close; headless programs end with the engine's quit().
@(private = "file")
null_poll_events :: proc() -> bool {
	return true
}

// No surface: the renderer treats nil as "always draw offscreen".
@(private = "file")
null_get_surface :: proc(_: rawptr) -> rawptr {
	return nil
}

@(private = "file")
null_get_framebuffer_size :: proc() -> (width: u32, height: u32) {
	return u32(f32(state.width) * state.scale + 0.5), u32(f32(state.height) * state.scale + 0.5)
}

@(private = "file")
null_get_window_size :: proc() -> (width: u32, height: u32) {
	return u32(state.width), u32(state.height)
}

@(private = "file")
null_get_events :: proc() -> []core.Event {
	result := state.events[:]
	clear(&state.events) // the slice stays valid until the next push_event
	return result
}

@(private = "file")
null_set_cursor_visible :: proc(_: bool) {}

@(private = "file")
null_set_system_cursor :: proc(_: core.System_Cursor) {}

@(private = "file")
null_set_custom_cursor :: proc(_: []u8, _, _, _, _: int) {}

@(private = "file")
null_set_window_mode :: proc(_: core.Window_Mode) {}
