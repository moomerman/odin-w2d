package core

import "vendor:wgpu"

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

	// Create a wgpu surface for the window.
	get_surface:          proc(instance: wgpu.Instance) -> wgpu.Surface,

	// Get the framebuffer size in physical pixels.
	get_framebuffer_size: proc() -> (width: u32, height: u32),

	// Return buffered input events since the last call, then clear the buffer.
	get_events:           proc() -> []Event,
}
