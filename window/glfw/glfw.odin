#+build !js
// GLFW window backend for desktop platforms.

package window_glfw

import "base:runtime"
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

@(private = "file")
glfw_events: [dynamic]core.Event

@(private = "file")
glfw_last_mouse_pos: [2]f64

@(private = "file")
glfw_mouse_pos_valid: bool

@(private = "file")
glfw_saved_pos: [2]i32

@(private = "file")
glfw_saved_size: [2]i32

// Returns a Window_Backend vtable for GLFW.
backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = glfw_init,
		shutdown = glfw_shutdown,
		poll_events = glfw_poll_events,
		get_surface = glfw_get_surface,
		get_framebuffer_size = glfw_get_framebuffer_size,
		get_events = glfw_get_events,
		set_cursor_visible = glfw_set_cursor_visible,
		set_system_cursor = glfw_set_system_cursor,
		set_custom_cursor = glfw_set_custom_cursor,
		set_window_mode = glfw_set_window_mode,
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
	glfw.SetCursorPosCallback(glfw_window, glfw_cursor_pos_callback)
	glfw.SetMouseButtonCallback(glfw_window, glfw_mouse_button_callback)
	glfw.SetKeyCallback(glfw_window, glfw_key_callback)
	glfw.SetScrollCallback(glfw_window, glfw_scroll_callback)
}

@(private = "file")
glfw_shutdown :: proc() {
	delete(glfw_events)
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
glfw_get_surface :: proc(instance: rawptr) -> rawptr {
	return glfwglue.GetSurface(wgpu.Instance(instance), glfw_window)
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
	case .Default:
		shape = glfw.ARROW_CURSOR
	case .Text:
		shape = glfw.IBEAM_CURSOR
	case .Crosshair:
		shape = glfw.CROSSHAIR_CURSOR
	case .Pointer:
		shape = glfw.POINTING_HAND_CURSOR
	case .Resize_EW:
		shape = glfw.RESIZE_EW_CURSOR
	case .Resize_NS:
		shape = glfw.RESIZE_NS_CURSOR
	case .Resize_NWSE:
		shape = glfw.RESIZE_NWSE_CURSOR
	case .Resize_NESW:
		shape = glfw.RESIZE_NESW_CURSOR
	case .Move:
		shape = glfw.RESIZE_ALL_CURSOR
	case .Not_Allowed:
		shape = glfw.NOT_ALLOWED_CURSOR
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

@(private = "file")
glfw_get_events :: proc() -> []core.Event {
	events := glfw_events[:]
	clear(&glfw_events)
	return events
}

@(private = "file")
glfw_cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	context = runtime.default_context()
	dx, dy: f64
	if glfw_mouse_pos_valid {
		dx = xpos - glfw_last_mouse_pos[0]
		dy = ypos - glfw_last_mouse_pos[1]
	}
	glfw_last_mouse_pos = {xpos, ypos}
	glfw_mouse_pos_valid = true
	append(
		&glfw_events,
		core.Event(
			core.Mouse_Move_Event{pos = {f32(xpos), f32(ypos)}, delta = {f32(dx), f32(dy)}},
		),
	)
}

@(private = "file")
glfw_mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = runtime.default_context()
	btn: core.Mouse_Button
	switch button {
	case glfw.MOUSE_BUTTON_1:
		btn = .Left
	case glfw.MOUSE_BUTTON_2:
		btn = .Right
	case glfw.MOUSE_BUTTON_3:
		btn = .Middle
	case:
		return
	}
	xpos, ypos := glfw.GetCursorPos(window)
	append(
		&glfw_events,
		core.Event(
			core.Mouse_Button_Event {
				button = btn,
				down = action == glfw.PRESS,
				pos = {f32(xpos), f32(ypos)},
			},
		),
	)
}

@(private = "file")
glfw_key_callback :: proc "c" (window: glfw.WindowHandle, glfw_key, scancode, action, mods: i32) {
	context = runtime.default_context()
	key, ok := glfw_map_key(glfw_key)
	if !ok {
		return
	}
	append(
		&glfw_events,
		core.Event(
			core.Key_Event {
				key = key,
				down = action == glfw.PRESS || action == glfw.REPEAT,
				repeat = action == glfw.REPEAT,
			},
		),
	)
}

@(private = "file")
glfw_map_key :: proc "c" (glfw_key: i32) -> (core.Key, bool) {
	// Letters: GLFW A(65)-Z(90) -> core A(4)-Z(29)
	if glfw_key >= glfw.KEY_A && glfw_key <= glfw.KEY_Z {
		return core.Key(u16(glfw_key - glfw.KEY_A) + u16(core.Key.A)), true
	}
	// Digits 1-9: GLFW 1(49)-9(57) -> core Key_1(30)-Key_9(38)
	if glfw_key >= glfw.KEY_1 && glfw_key <= glfw.KEY_9 {
		return core.Key(u16(glfw_key - glfw.KEY_1) + u16(core.Key.Key_1)), true
	}
	// F1-F12: GLFW F1(290)-F12(301) -> core F1(58)-F12(69)
	if glfw_key >= glfw.KEY_F1 && glfw_key <= glfw.KEY_F12 {
		return core.Key(u16(glfw_key - glfw.KEY_F1) + u16(core.Key.F1)), true
	}
	// Individual mappings
	switch glfw_key {
	case glfw.KEY_0:
		return .Key_0, true
	case glfw.KEY_SPACE:
		return .Space, true
	case glfw.KEY_ENTER, glfw.KEY_KP_ENTER:
		return .Return, true
	case glfw.KEY_ESCAPE:
		return .Escape, true
	case glfw.KEY_BACKSPACE:
		return .Backspace, true
	case glfw.KEY_TAB:
		return .Tab, true
	case glfw.KEY_MINUS:
		return .Minus, true
	case glfw.KEY_EQUAL:
		return .Equals, true
	case glfw.KEY_LEFT_BRACKET:
		return .Left_Bracket, true
	case glfw.KEY_RIGHT_BRACKET:
		return .Right_Bracket, true
	case glfw.KEY_BACKSLASH:
		return .Backslash, true
	case glfw.KEY_SEMICOLON:
		return .Semicolon, true
	case glfw.KEY_APOSTROPHE:
		return .Apostrophe, true
	case glfw.KEY_GRAVE_ACCENT:
		return .Grave, true
	case glfw.KEY_COMMA:
		return .Comma, true
	case glfw.KEY_PERIOD:
		return .Period, true
	case glfw.KEY_SLASH:
		return .Slash, true
	case glfw.KEY_INSERT:
		return .Insert, true
	case glfw.KEY_DELETE:
		return .Delete, true
	case glfw.KEY_HOME:
		return .Home, true
	case glfw.KEY_END:
		return .End, true
	case glfw.KEY_PAGE_UP:
		return .Page_Up, true
	case glfw.KEY_PAGE_DOWN:
		return .Page_Down, true
	case glfw.KEY_RIGHT:
		return .Right, true
	case glfw.KEY_LEFT:
		return .Left, true
	case glfw.KEY_DOWN:
		return .Down, true
	case glfw.KEY_UP:
		return .Up, true
	case glfw.KEY_LEFT_CONTROL:
		return .Left_Ctrl, true
	case glfw.KEY_LEFT_SHIFT:
		return .Left_Shift, true
	case glfw.KEY_LEFT_ALT:
		return .Left_Alt, true
	case glfw.KEY_LEFT_SUPER:
		return .Left_Super, true
	case glfw.KEY_RIGHT_CONTROL:
		return .Right_Ctrl, true
	case glfw.KEY_RIGHT_SHIFT:
		return .Right_Shift, true
	case glfw.KEY_RIGHT_ALT:
		return .Right_Alt, true
	case glfw.KEY_RIGHT_SUPER:
		return .Right_Super, true
	}
	return {}, false
}

@(private = "file")
glfw_scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	context = runtime.default_context()
	xpos, ypos := glfw.GetCursorPos(window)
	append(
		&glfw_events,
		core.Event(
			core.Mouse_Scroll_Event {
				delta = {f32(xoffset), f32(yoffset)},
				pos = {f32(xpos), f32(ypos)},
			},
		),
	)
}

@(private = "file")
glfw_set_window_mode :: proc(mode: core.Window_Mode) {
	switch mode {
	case .Windowed:
		glfw.SetWindowMonitor(glfw_window, nil, glfw_saved_pos.x, glfw_saved_pos.y, glfw_saved_size.x, glfw_saved_size.y, 0)
		glfw.SetWindowAttrib(glfw_window, glfw.DECORATED, glfw.TRUE)
		glfw.SetWindowAttrib(glfw_window, glfw.RESIZABLE, glfw.TRUE)
	case .Windowed_Fixed:
		glfw.SetWindowMonitor(glfw_window, nil, glfw_saved_pos.x, glfw_saved_pos.y, glfw_saved_size.x, glfw_saved_size.y, 0)
		glfw.SetWindowAttrib(glfw_window, glfw.DECORATED, glfw.TRUE)
		glfw.SetWindowAttrib(glfw_window, glfw.RESIZABLE, glfw.FALSE)
	case .Fullscreen:
		// Save current position/size for restoring later.
		glfw_saved_pos.x, glfw_saved_pos.y = glfw.GetWindowPos(glfw_window)
		glfw_saved_size.x, glfw_saved_size.y = glfw.GetWindowSize(glfw_window)
		monitor := glfw.GetPrimaryMonitor()
		vid_mode := glfw.GetVideoMode(monitor)
		glfw.SetWindowMonitor(glfw_window, monitor, 0, 0, vid_mode.width, vid_mode.height, vid_mode.refresh_rate)
	case .Borderless:
		// Save current position/size for restoring later.
		glfw_saved_pos.x, glfw_saved_pos.y = glfw.GetWindowPos(glfw_window)
		glfw_saved_size.x, glfw_saved_size.y = glfw.GetWindowSize(glfw_window)
		glfw.SetWindowAttrib(glfw_window, glfw.DECORATED, glfw.FALSE)
		_, _, mw, mh := glfw.GetMonitorWorkarea(glfw.GetPrimaryMonitor())
		glfw.SetWindowMonitor(glfw_window, nil, 0, 0, mw, mh, 0)
	}
}
