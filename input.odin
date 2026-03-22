package engine

import "core"

@(private = "file")
MOUSE_BUTTON_COUNT :: len(core.Mouse_Button)

@(private = "file")
KEY_COUNT :: int(max(core.Key)) + 1

@(private = "package")
Input_State :: struct {
	mouse_pos:        Vec2,
	mouse_delta:      Vec2,
	mouse_held:       [MOUSE_BUTTON_COUNT]bool,
	mouse_went_down:  [MOUSE_BUTTON_COUNT]bool,
	mouse_went_up:    [MOUSE_BUTTON_COUNT]bool,
	mouse_deferred_up: [MOUSE_BUTTON_COUNT]bool,
	key_held:         [KEY_COUNT]bool,
	key_went_down:    [KEY_COUNT]bool,
	key_went_up:      [KEY_COUNT]bool,
}

@(private = "package")
input: Input_State

// Process input events from the window backend. Called once per frame
// before the user's frame callback.
@(private = "package")
process_input :: proc() {
	// Clear per-frame state.
	input.mouse_delta = {}
	input.mouse_went_down = {}
	input.mouse_went_up = {}
	input.key_went_down = {}
	input.key_went_up = {}

	// Apply deferred mouse-up events from the previous frame. If a new
	// down event arrives this frame it will cancel the defer below.
	for btn in 0 ..< MOUSE_BUTTON_COUNT {
		if input.mouse_deferred_up[btn] {
			input.mouse_deferred_up[btn] = false
			input.mouse_held[btn] = false
			input.mouse_went_up[btn] = true
		}
	}

	// Drain events from the window backend.
	for event in ctx.window.get_events() {
		switch e in event {
		case core.Mouse_Move_Event:
			input.mouse_pos = e.pos
			input.mouse_delta += e.delta
		case core.Mouse_Button_Event:
			input.mouse_pos = e.pos
			btn := int(e.button)
			if e.down {
				input.mouse_held[btn] = true
				input.mouse_went_down[btn] = true
				input.mouse_deferred_up[btn] = false
			} else {
				input.mouse_held[btn] = false
				input.mouse_went_up[btn] = true
			}
		case core.Key_Event:
			k := int(e.key)
			if e.down {
				if !e.repeat {
					input.key_went_down[k] = true
				}
				input.key_held[k] = true
			} else {
				input.key_held[k] = false
				input.key_went_up[k] = true
			}
		}
	}

	// macOS trackpads can deliver DOWN+UP in the same event batch when the
	// user clicks, then send a sustained DOWN ~500ms later once the OS
	// confirms a hold/drag. When both fire in the same frame, keep held
	// true and defer the UP by several frames to bridge the gap.
	for btn in 0 ..< MOUSE_BUTTON_COUNT {
		if input.mouse_went_down[btn] && input.mouse_went_up[btn] {
			input.mouse_held[btn] = true
			input.mouse_went_up[btn] = false
			input.mouse_deferred_up[btn] = true
		}
	}
}

//------------//
// PUBLIC API //
//------------//

// Get the current mouse position in window coordinates.
get_mouse_position :: proc() -> Vec2 {
	return input.mouse_pos
}

// Get the mouse movement delta since the last frame.
get_mouse_delta :: proc() -> Vec2 {
	return input.mouse_delta
}

// Returns true if the mouse button was pressed this frame.
mouse_button_went_down :: proc(button: Mouse_Button) -> bool {
	return input.mouse_went_down[int(button)]
}

// Returns true if the mouse button was released this frame.
mouse_button_went_up :: proc(button: Mouse_Button) -> bool {
	return input.mouse_went_up[int(button)]
}

// Returns true if the mouse button is currently held down.
mouse_button_is_held :: proc(button: Mouse_Button) -> bool {
	return input.mouse_held[int(button)]
}

// Returns true if the key was pressed this frame (ignores repeats).
key_went_down :: proc(key: Key) -> bool {
	return input.key_went_down[int(key)]
}

// Returns true if the key was released this frame.
key_went_up :: proc(key: Key) -> bool {
	return input.key_went_up[int(key)]
}

// Returns true if the key is currently held down.
key_is_held :: proc(key: Key) -> bool {
	return input.key_held[int(key)]
}

// Show the OS cursor.
show_cursor :: proc() {
	if ctx.window.set_cursor_visible != nil {
		ctx.window.set_cursor_visible(true)
	}
}

// Hide the OS cursor.
hide_cursor :: proc() {
	if ctx.window.set_cursor_visible != nil {
		ctx.window.set_cursor_visible(false)
	}
}

// Set the cursor to a system cursor shape.
set_cursor :: proc(cursor: System_Cursor) {
	if ctx.window.set_system_cursor != nil {
		ctx.window.set_system_cursor(cursor)
	}
}

// Set a custom cursor from RGBA pixel data.
set_custom_cursor :: proc(pixels: []u8, width, height: int, hot_x: int = 0, hot_y: int = 0) {
	if ctx.window.set_custom_cursor != nil {
		ctx.window.set_custom_cursor(pixels, width, height, hot_x, hot_y)
	}
}
