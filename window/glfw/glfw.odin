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
glfw_on_resize: proc()

// Returns a Window_Backend vtable for GLFW.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = glfw_init,
		shutdown = glfw_shutdown,
		poll_events = glfw_poll_events,
		get_surface = glfw_get_surface,
		get_framebuffer_size = glfw_get_framebuffer_size,
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
