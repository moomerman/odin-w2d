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

@(private = "file")
sdl3_events: [dynamic]core.Event

// Returns a Window_Backend vtable for SDL3.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = sdl3_init,
		shutdown = sdl3_shutdown,
		poll_events = sdl3_poll_events,
		get_surface = sdl3_get_surface,
		get_framebuffer_size = sdl3_get_framebuffer_size,
		get_events = sdl3_get_events,
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
		case .MOUSE_MOTION:
			append(
				&sdl3_events,
				core.Event(
					core.Mouse_Move_Event {
						pos = {e.motion.x, e.motion.y},
						delta = {e.motion.xrel, e.motion.yrel},
					},
				),
			)
		case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
			btn: core.Mouse_Button
			switch e.button.button {
			case 1:
				btn = .Left
			case 2:
				btn = .Middle
			case 3:
				btn = .Right
			case:
				continue
			}
			append(
				&sdl3_events,
				core.Event(
					core.Mouse_Button_Event {
						button = btn,
						down = e.type == .MOUSE_BUTTON_DOWN,
						pos = {e.button.x, e.button.y},
					},
				),
			)
		case .KEY_DOWN, .KEY_UP:
			// SDL scancodes map directly to our Key enum values.
			sc := u16(e.key.scancode)
			if sc == 0 || sc > u16(max(core.Key)) {
				continue
			}
			key := core.Key(sc)
			append(
				&sdl3_events,
				core.Event(core.Key_Event{key = key, down = e.key.down, repeat = e.key.repeat}),
			)
		}
	}
	return !sdl3_should_quit
}

@(private = "file")
sdl3_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return sdl3glue.GetSurface(instance, sdl3_window)
}

@(private = "file")
sdl3_get_events :: proc() -> []core.Event {
	events := sdl3_events[:]
	clear(&sdl3_events)
	return events
}

@(private = "file")
sdl3_get_framebuffer_size :: proc() -> (width: u32, height: u32) {
	w, h: i32
	SDL.GetWindowSizeInPixels(sdl3_window, &w, &h)
	return u32(w), u32(h)
}
