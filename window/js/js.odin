#+build js
package window_js

import "core:encoding/base64"
import "core:fmt"
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
		set_cursor_visible = js_set_cursor_visible,
		set_system_cursor = js_set_system_cursor,
		set_custom_cursor = js_set_custom_cursor,
		set_window_mode = js_set_window_mode,
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

	js.add_event_listener("wgpu-canvas", .Wheel, nil, js_wheel_callback)

	js.add_window_event_listener(.Key_Down, nil, js_key_callback)
	js.add_window_event_listener(.Key_Up, nil, js_key_callback)
}

@(private = "file")
js_shutdown :: proc() {
	js.remove_window_event_listener(.Resize, nil, js_size_callback)

	js.remove_event_listener("wgpu-canvas", .Mouse_Move, nil, js_mouse_move_callback)
	js.remove_event_listener("wgpu-canvas", .Mouse_Down, nil, js_mouse_button_callback)
	js.remove_event_listener("wgpu-canvas", .Mouse_Up, nil, js_mouse_button_callback)

	js.remove_event_listener("wgpu-canvas", .Wheel, nil, js_wheel_callback)

	js.remove_window_event_listener(.Key_Down, nil, js_key_callback)
	js.remove_window_event_listener(.Key_Up, nil, js_key_callback)
}

@(private = "file")
js_poll_events :: proc() -> bool {
	return true
}

@(private = "file")
js_get_surface :: proc(instance: rawptr) -> rawptr {
	return wgpu.InstanceCreateSurface(
		wgpu.Instance(instance),
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

@(private = "file")
js_key_callback :: proc(e: js.Event) {
	key, ok := js_code_to_key(e.key.code)
	if !ok do return
	append(
		&js_events,
		core.Event(core.Key_Event{key = key, down = e.kind == .Key_Down, repeat = e.key.repeat}),
	)
}

@(private = "file")
js_set_cursor_visible :: proc(visible: bool) {
	if visible {
		js.evaluate(`document.getElementById("wgpu-canvas").style.cursor = "default";`)
	} else {
		js.evaluate(`document.getElementById("wgpu-canvas").style.cursor = "none";`)
	}
}

@(private = "file")
js_set_system_cursor :: proc(cursor: core.System_Cursor) {
	css_value: string
	switch cursor {
	case .Default:
		css_value = "default"
	case .Text:
		css_value = "text"
	case .Crosshair:
		css_value = "crosshair"
	case .Pointer:
		css_value = "pointer"
	case .Resize_EW:
		css_value = "ew-resize"
	case .Resize_NS:
		css_value = "ns-resize"
	case .Resize_NWSE:
		css_value = "nwse-resize"
	case .Resize_NESW:
		css_value = "nesw-resize"
	case .Move:
		css_value = "move"
	case .Not_Allowed:
		css_value = "not-allowed"
	}
	js.evaluate(
		fmt.tprintf(`document.getElementById("wgpu-canvas").style.cursor = "%s";`, css_value),
	)
}

@(private = "file")
js_set_custom_cursor :: proc(pixels: []u8, width, height, hot_x, hot_y: int) {
	b64 := base64.encode(pixels)
	defer delete(b64)
	js.evaluate(
		fmt.tprintf(
			`(function(){{var w=%d,h=%d,hx=%d,hy=%d;var b=atob("%s");var a=new Uint8ClampedArray(b.length);for(var i=0;i<b.length;i++)a[i]=b.charCodeAt(i);var c=document.createElement("canvas");c.width=w;c.height=h;var ctx=c.getContext("2d");ctx.putImageData(new ImageData(a,w,h),0,0);document.getElementById("wgpu-canvas").style.cursor="url("+c.toDataURL()+") "+hx+" "+hy+", auto";}})();`,
			width,
			height,
			hot_x,
			hot_y,
			b64,
		),
	)
}

@(private = "file")
js_code_to_key :: proc(code: string) -> (core.Key, bool) {
	// Map DOM KeyboardEvent.code strings to our Key enum.
	switch code {
	// Letters
	case "KeyA":
		return .A, true
	case "KeyB":
		return .B, true
	case "KeyC":
		return .C, true
	case "KeyD":
		return .D, true
	case "KeyE":
		return .E, true
	case "KeyF":
		return .F, true
	case "KeyG":
		return .G, true
	case "KeyH":
		return .H, true
	case "KeyI":
		return .I, true
	case "KeyJ":
		return .J, true
	case "KeyK":
		return .K, true
	case "KeyL":
		return .L, true
	case "KeyM":
		return .M, true
	case "KeyN":
		return .N, true
	case "KeyO":
		return .O, true
	case "KeyP":
		return .P, true
	case "KeyQ":
		return .Q, true
	case "KeyR":
		return .R, true
	case "KeyS":
		return .S, true
	case "KeyT":
		return .T, true
	case "KeyU":
		return .U, true
	case "KeyV":
		return .V, true
	case "KeyW":
		return .W, true
	case "KeyX":
		return .X, true
	case "KeyY":
		return .Y, true
	case "KeyZ":
		return .Z, true
	// Digits
	case "Digit1":
		return .Key_1, true
	case "Digit2":
		return .Key_2, true
	case "Digit3":
		return .Key_3, true
	case "Digit4":
		return .Key_4, true
	case "Digit5":
		return .Key_5, true
	case "Digit6":
		return .Key_6, true
	case "Digit7":
		return .Key_7, true
	case "Digit8":
		return .Key_8, true
	case "Digit9":
		return .Key_9, true
	case "Digit0":
		return .Key_0, true
	// Common keys
	case "Enter":
		return .Return, true
	case "Escape":
		return .Escape, true
	case "Backspace":
		return .Backspace, true
	case "Tab":
		return .Tab, true
	case "Space":
		return .Space, true
	// Punctuation
	case "Minus":
		return .Minus, true
	case "Equal":
		return .Equals, true
	case "BracketLeft":
		return .Left_Bracket, true
	case "BracketRight":
		return .Right_Bracket, true
	case "Backslash":
		return .Backslash, true
	case "Semicolon":
		return .Semicolon, true
	case "Quote":
		return .Apostrophe, true
	case "Backquote":
		return .Grave, true
	case "Comma":
		return .Comma, true
	case "Period":
		return .Period, true
	case "Slash":
		return .Slash, true
	// Function keys
	case "F1":
		return .F1, true
	case "F2":
		return .F2, true
	case "F3":
		return .F3, true
	case "F4":
		return .F4, true
	case "F5":
		return .F5, true
	case "F6":
		return .F6, true
	case "F7":
		return .F7, true
	case "F8":
		return .F8, true
	case "F9":
		return .F9, true
	case "F10":
		return .F10, true
	case "F11":
		return .F11, true
	case "F12":
		return .F12, true
	// Navigation
	case "Insert":
		return .Insert, true
	case "Home":
		return .Home, true
	case "PageUp":
		return .Page_Up, true
	case "Delete":
		return .Delete, true
	case "End":
		return .End, true
	case "PageDown":
		return .Page_Down, true
	// Arrows
	case "ArrowRight":
		return .Right, true
	case "ArrowLeft":
		return .Left, true
	case "ArrowDown":
		return .Down, true
	case "ArrowUp":
		return .Up, true
	// Modifiers
	case "ControlLeft":
		return .Left_Ctrl, true
	case "ShiftLeft":
		return .Left_Shift, true
	case "AltLeft":
		return .Left_Alt, true
	case "MetaLeft":
		return .Left_Super, true
	case "ControlRight":
		return .Right_Ctrl, true
	case "ShiftRight":
		return .Right_Shift, true
	case "AltRight":
		return .Right_Alt, true
	case "MetaRight":
		return .Right_Super, true
	}
	return {}, false
}

@(private = "file")
js_wheel_callback :: proc(e: js.Event) {
	// DOM convention: positive deltaY = scroll down, we want positive Y = up.
	dx := f32(-e.wheel.delta[0])
	dy := f32(-e.wheel.delta[1])

	// Normalize line/page modes to approximate pixel values.
	switch e.wheel.delta_mode {
	case .Pixel:
	// Already in pixels.
	case .Line:
		dx *= 20
		dy *= 20
	case .Page:
		dx *= 400
		dy *= 400
	}

	append(
		&js_events,
		core.Event(
			core.Mouse_Scroll_Event {
				delta = {dx, dy},
				pos = {f32(e.mouse.client[0]), f32(e.mouse.client[1])},
			},
		),
	)
}

@(private = "file")
js_set_window_mode :: proc(mode: core.Window_Mode) {
	switch mode {
	case .Fullscreen, .Borderless:
		js.evaluate(`document.documentElement.requestFullscreen();`)
	case .Windowed, .Windowed_Fixed:
		js.evaluate(`if(document.fullscreenElement)document.exitFullscreen();`)
	}
}
