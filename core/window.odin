package core

Window_Mode :: enum {
	Windowed, // Resizable window with title bar
	Windowed_Fixed, // Non-resizable window with title bar
	Fullscreen, // Exclusive fullscreen
	Borderless, // Borderless window covering the entire screen
}

// Window_Backend abstracts over different windowing libraries (SDL3, GLFW, JS).
// Each backend provides an implementation of these procedures.
Window_Backend :: struct {
	// Create the window with the given dimensions and title.
	// on_resize is called when the framebuffer size changes so the engine
	// can reconfigure the renderer.
	init:                 proc(width, height: int, title: string, on_resize: proc()),

	// Destroy the window and clean up platform resources.
	shutdown:             proc(),

	// Poll for window/input events. Returns false when the user has requested to close the window.
	poll_events:          proc() -> bool,

	// Create a GPU surface for the window. The instance and return value are
	// renderer-specific opaque pointers (e.g. wgpu.Instance / wgpu.Surface).
	get_surface:          proc(instance: rawptr) -> rawptr,

	// Get the framebuffer size in physical pixels.
	get_framebuffer_size: proc() -> (width: u32, height: u32),

	// Return buffered input events since the last call, then clear the buffer.
	get_events:           proc() -> []Event,

	// Cursor control.
	set_cursor_visible:   proc(visible: bool),
	set_system_cursor:    proc(cursor: System_Cursor),
	set_custom_cursor:    proc(pixels: []u8, width, height, hot_x, hot_y: int),

	// Window mode control.
	set_window_mode:      proc(mode: Window_Mode),
}
