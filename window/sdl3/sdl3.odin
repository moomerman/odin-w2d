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

@(private = "file")
sdl3_current_cursor: ^SDL.Cursor

// Returns a Window_Backend vtable for SDL3.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = sdl3_init,
		shutdown = sdl3_shutdown,
		poll_events = sdl3_poll_events,
		get_surface = sdl3_get_surface,
		get_framebuffer_size = sdl3_get_framebuffer_size,
		get_events = sdl3_get_events,
		set_cursor_visible = sdl3_set_cursor_visible,
		set_system_cursor = sdl3_set_system_cursor,
		set_custom_cursor = sdl3_set_custom_cursor,
		set_window_mode = sdl3_set_window_mode,
	}
}

@(private = "file")
sdl3_init :: proc(width, height: int, title: string, on_resize: proc()) {
	sdl3_on_resize = on_resize
	if !SDL.Init({.VIDEO}) {
		fmt.panicf("SDL.Init error: %s", SDL.GetError())
	}

	// Disable mouse auto-capture on click. This can cause click delays on macOS
	// when window managers like Magnet intercept mouse events for drag detection.
	SDL.SetHint(SDL.HINT_MOUSE_AUTO_CAPTURE, "0")

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
	delete(sdl3_events)
	if sdl3_current_cursor != nil {
		SDL.DestroyCursor(sdl3_current_cursor)
		sdl3_current_cursor = nil
	}
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
		case .MOUSE_WHEEL:
			append(
				&sdl3_events,
				core.Event(
					core.Mouse_Scroll_Event {
						delta = {e.wheel.x, e.wheel.y},
						pos = {e.wheel.mouse_x, e.wheel.mouse_y},
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
sdl3_get_surface :: proc(instance: rawptr) -> rawptr {
	return sdl3glue.GetSurface(wgpu.Instance(instance), sdl3_window)
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

@(private = "file")
sdl3_set_cursor_visible :: proc(visible: bool) {
	if visible {
		_ = SDL.ShowCursor()
	} else {
		_ = SDL.HideCursor()
	}
}

@(private = "file")
sdl3_set_system_cursor :: proc(cursor: core.System_Cursor) {
	sdl_cursor: SDL.SystemCursor
	switch cursor {
	case .Default:
		sdl_cursor = .DEFAULT
	case .Text:
		sdl_cursor = .TEXT
	case .Crosshair:
		sdl_cursor = .CROSSHAIR
	case .Pointer:
		sdl_cursor = .POINTER
	case .Resize_EW:
		sdl_cursor = .EW_RESIZE
	case .Resize_NS:
		sdl_cursor = .NS_RESIZE
	case .Resize_NWSE:
		sdl_cursor = .NWSE_RESIZE
	case .Resize_NESW:
		sdl_cursor = .NESW_RESIZE
	case .Move:
		sdl_cursor = .MOVE
	case .Not_Allowed:
		sdl_cursor = .NOT_ALLOWED
	}
	new_cursor := SDL.CreateSystemCursor(sdl_cursor)
	if new_cursor != nil {
		_ = SDL.SetCursor(new_cursor)
		if sdl3_current_cursor != nil {
			SDL.DestroyCursor(sdl3_current_cursor)
		}
		sdl3_current_cursor = new_cursor
	}
}

@(private = "file")
sdl3_set_custom_cursor :: proc(pixels: []u8, width, height, hot_x, hot_y: int) {
	surface := SDL.CreateSurfaceFrom(
		i32(width),
		i32(height),
		.RGBA32,
		raw_data(pixels),
		i32(width * 4),
	)
	if surface == nil {
		fmt.eprintf("SDL.CreateSurfaceFrom error: %s\n", SDL.GetError())
		return
	}
	new_cursor := SDL.CreateColorCursor(surface, i32(hot_x), i32(hot_y))
	SDL.DestroySurface(surface)
	if new_cursor == nil {
		fmt.eprintf("SDL.CreateColorCursor error: %s\n", SDL.GetError())
		return
	}
	_ = SDL.SetCursor(new_cursor)
	if sdl3_current_cursor != nil {
		SDL.DestroyCursor(sdl3_current_cursor)
	}
	sdl3_current_cursor = new_cursor
}

@(private = "file")
sdl3_set_window_mode :: proc(mode: core.Window_Mode) {
	switch mode {
	case .Windowed:
		SDL.SetWindowFullscreen(sdl3_window, false)
		SDL.SetWindowBordered(sdl3_window, true)
		SDL.SetWindowResizable(sdl3_window, true)
	case .Windowed_Fixed:
		SDL.SetWindowFullscreen(sdl3_window, false)
		SDL.SetWindowBordered(sdl3_window, true)
		SDL.SetWindowResizable(sdl3_window, false)
	case .Fullscreen:
		SDL.SetWindowFullscreen(sdl3_window, true)
	case .Borderless:
		SDL.SetWindowFullscreen(sdl3_window, false)
		SDL.SetWindowBordered(sdl3_window, false)
		display := SDL.GetDisplayForWindow(sdl3_window)
		bounds: SDL.Rect
		if SDL.GetDisplayBounds(display, &bounds) {
			SDL.SetWindowPosition(sdl3_window, bounds.x, bounds.y)
			SDL.SetWindowSize(sdl3_window, bounds.w, bounds.h)
		}
	}
}
