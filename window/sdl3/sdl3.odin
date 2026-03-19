#+build !js
// SDL3 window backend for desktop platforms.

package window_sdl3

import "core:fmt"

import SDL "vendor:sdl3"
import "vendor:wgpu"
import "vendor:wgpu/sdl3glue"

import core "../../core"

@(private = "file")
sdl3_window: ^SDL.Window

@(private = "file")
sdl3_should_quit: bool

@(private = "file")
sdl3_on_resize: proc()

// Returns a Window_Backend vtable for SDL3.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = sdl3_init,
		shutdown = sdl3_shutdown,
		poll_events = sdl3_poll_events,
		get_surface = sdl3_get_surface,
		get_framebuffer_size = sdl3_get_framebuffer_size,
	}
}

@(private = "file")
sdl3_init :: proc(width, height: int, title: string, on_resize: proc()) {
	sdl3_on_resize = on_resize
	if !SDL.Init({.VIDEO}) {
		fmt.panicf("SDL.Init error: %s", SDL.GetError())
	}

	sdl3_window = SDL.CreateWindow(
		fmt.ctprintf("%s", title),
		i32(width),
		i32(height),
		{.RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	if sdl3_window == nil {
		fmt.panicf("SDL.CreateWindow error: %s", SDL.GetError())
	}

	sdl3_should_quit = false
}

@(private = "file")
sdl3_shutdown :: proc() {
	if sdl3_window != nil {
		SDL.DestroyWindow(sdl3_window)
		sdl3_window = nil
	}
	SDL.Quit()
}

@(private = "file")
sdl3_poll_events :: proc() -> bool {
	e: SDL.Event
	for SDL.PollEvent(&e) {
		#partial switch e.type {
		case .QUIT:
			sdl3_should_quit = true
		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
			if sdl3_on_resize != nil {
				sdl3_on_resize()
			}
		}
	}
	return !sdl3_should_quit
}

@(private = "file")
sdl3_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return sdl3glue.GetSurface(instance, sdl3_window)
}

@(private = "file")
sdl3_get_framebuffer_size :: proc() -> (width: u32, height: u32) {
	w, h: i32
	SDL.GetWindowSizeInPixels(sdl3_window, &w, &h)
	return u32(w), u32(h)
}
