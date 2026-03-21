#+build !js
// GLFW window backend for desktop platforms.

package window_glfw

import "core:strings"

import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

import core "../../core"

@(private = "file")
glfw_window: glfw.WindowHandle

@(private = "file")
glfw_should_quit: bool

@(private = "file")
glfw_was_resized: bool

@(private = "file")
glfw_title: cstring

@(private = "file")
glfw_current_cursor: glfw.CursorHandle

@(private = "file")
glfw_on_resize: proc()

// Returns a Window_Backend vtable for GLFW.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = glfw_init,
		shutdown = glfw_shutdown,
		poll_events = glfw_poll_events,
		get_surface = glfw_get_surface,
		get_framebuffer_size = glfw_get_framebuffer_size,
		set_cursor_visible = glfw_set_cursor_visible,
		set_system_cursor = glfw_set_system_cursor,
		set_custom_cursor = glfw_set_custom_cursor,
	}
}

@(private = "file")
glfw_init :: proc(width, height: int, title: string, on_resize: proc()) {
	glfw_on_resize = on_resize

	if !glfw.Init() {
		panic("[window/glfw] glfw.Init failed")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	glfw_title = strings.clone_to_cstring(title)
	glfw_window = glfw.CreateWindow(i32(width), i32(height), glfw_title, nil, nil)
	if glfw_window == nil {
		panic("[window/glfw] glfw.CreateWindow failed")
	}

	glfw_should_quit = false
	glfw_was_resized = false

	glfw.SetFramebufferSizeCallback(glfw_window, glfw_framebuffer_size_callback)
}

@(private = "file")
glfw_shutdown :: proc() {
	if glfw_current_cursor != nil {
		glfw.DestroyCursor(glfw_current_cursor)
		glfw_current_cursor = nil
	}
	if glfw_window != nil {
		glfw.DestroyWindow(glfw_window)
		glfw_window = nil
	}
	if glfw_title != nil {
		delete(glfw_title)
		glfw_title = nil
	}
	glfw.Terminate()
}

@(private = "file")
glfw_poll_events :: proc() -> bool {
	glfw_was_resized = false
	glfw.PollEvents()

	if glfw_was_resized {
		if glfw_on_resize != nil {
			glfw_on_resize()
		}
	}

	if glfw.WindowShouldClose(glfw_window) {
		glfw_should_quit = true
	}

	return !glfw_should_quit
}

@(private = "file")
glfw_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, glfw_window)
}

@(private = "file")
glfw_get_framebuffer_size :: proc() -> (width: u32, height: u32) {
	iw, ih := glfw.GetFramebufferSize(glfw_window)
	return u32(iw), u32(ih)
}

@(private = "file")
glfw_framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	glfw_was_resized = true
}

@(private = "file")
glfw_set_cursor_visible :: proc(visible: bool) {
	glfw.SetInputMode(glfw_window, glfw.CURSOR, visible ? glfw.CURSOR_NORMAL : glfw.CURSOR_HIDDEN)
}

@(private = "file")
glfw_set_system_cursor :: proc(cursor: core.System_Cursor) {
	shape: i32
	switch cursor {
	case .Default:     shape = glfw.ARROW_CURSOR
	case .Text:        shape = glfw.IBEAM_CURSOR
	case .Crosshair:   shape = glfw.CROSSHAIR_CURSOR
	case .Pointer:     shape = glfw.POINTING_HAND_CURSOR
	case .Resize_EW:   shape = glfw.RESIZE_EW_CURSOR
	case .Resize_NS:   shape = glfw.RESIZE_NS_CURSOR
	case .Resize_NWSE: shape = glfw.RESIZE_NWSE_CURSOR
	case .Resize_NESW: shape = glfw.RESIZE_NESW_CURSOR
	case .Move:        shape = glfw.RESIZE_ALL_CURSOR
	case .Not_Allowed: shape = glfw.NOT_ALLOWED_CURSOR
	}
	new_cursor := glfw.CreateStandardCursor(shape)
	if new_cursor != nil {
		glfw.SetCursor(glfw_window, new_cursor)
		if glfw_current_cursor != nil {
			glfw.DestroyCursor(glfw_current_cursor)
		}
		glfw_current_cursor = new_cursor
	}
}

@(private = "file")
glfw_set_custom_cursor :: proc(pixels: []u8, width, height, hot_x, hot_y: int) {
	image := glfw.Image {
		width  = i32(width),
		height = i32(height),
		pixels = raw_data(pixels),
	}
	new_cursor := glfw.CreateCursor(&image, i32(hot_x), i32(hot_y))
	if new_cursor != nil {
		glfw.SetCursor(glfw_window, new_cursor)
		if glfw_current_cursor != nil {
			glfw.DestroyCursor(glfw_current_cursor)
		}
		glfw_current_cursor = new_cursor
	}
}
