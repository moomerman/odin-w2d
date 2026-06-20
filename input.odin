package engine

import "core"

@(private = "file")
MOUSE_BUTTON_COUNT :: len(core.Mouse_Button)

@(private = "file")
KEY_COUNT :: int(max(core.Key)) + 1

@(private = "package")
Input_State :: struct {
	mouse_pos:                Vec2,
	mouse_delta:              Vec2,
	scroll_delta:             Vec2,
	scroll_delta_no_momentum: Vec2,
	mouse_held:               [MOUSE_BUTTON_COUNT]bool,
	mouse_went_down:          [MOUSE_BUTTON_COUNT]bool,
	mouse_went_up:            [MOUSE_BUTTON_COUNT]bool,
	mouse_deferred_up:        [MOUSE_BUTTON_COUNT]bool,
	key_held:                 [KEY_COUNT]bool,
	key_went_down:            [KEY_COUNT]bool,
	key_went_up:              [KEY_COUNT]bool,
	// Gamepad snapshots. The backend fills `gamepads_curr` each frame; `gamepads_prev`
	// holds the previous frame so the accessors can derive went-down / went-up edges.
	gamepads_curr:            [core.MAX_GAMEPADS]core.Gamepad_State,
	gamepads_prev:            [core.MAX_GAMEPADS]core.Gamepad_State,
	// The gamepad subsystem inits lazily on first use, so games that never touch a
	// gamepad don't pay its startup cost (~hundreds of ms on some platforms).
	gamepad_active:           bool,
}

@(private = "package")
input: Input_State

// Process input events from the window backend. Called once per frame
// before the user's frame callback.
@(private = "package")
process_input :: proc() {
	// Clear per-frame state.
	input.mouse_delta = {}
	input.scroll_delta = {}
	input.scroll_delta_no_momentum = {}
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
		case core.Mouse_Scroll_Event:
			input.scroll_delta += e.delta
			if !e.momentum {
				input.scroll_delta_no_momentum += e.delta
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

	// Poll gamepads once the subsystem has been activated by first use. Keep last
	// frame's snapshot so the went-down / went-up accessors can diff against it.
	if input.gamepad_active {
		input.gamepads_prev = input.gamepads_curr
		ctx.gamepad.poll(&input.gamepads_curr)
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

// Get the scroll wheel delta since the last frame.
// Positive Y = up/away from user, positive X = right.
// Set include_momentum to false to ignore OS-generated inertia events
// (macOS trackpad/Magic Mouse momentum scrolling).
get_scroll_delta :: proc(include_momentum: bool = true) -> Vec2 {
	return include_momentum ? input.scroll_delta : input.scroll_delta_no_momentum
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

//---------//
// GAMEPAD //
//---------//

// Initialize the gamepad subsystem. Opt-in (like init_audio) so games that
// don't use a gamepad pay none of its startup cost. Call this once, before
// `run()` — on macOS the underlying SDL gamepad init must happen before the
// native window's event loop starts. Until it is called, the gamepad queries
// below report no controllers and vibration is a no-op.
init_gamepad :: proc() {
	if input.gamepad_active {
		return
	}
	input.gamepad_active = true
	ctx.gamepad.init()
}

// Shut down the gamepad subsystem and release any open controllers. Optional —
// the engine also does this automatically on exit if init_gamepad was called.
shutdown_gamepad :: proc() {
	if !input.gamepad_active {
		return
	}
	ctx.gamepad.shutdown()
	input.gamepad_active = false
}

// Returns true if a controller is connected in the given slot (0..3).
// Out-of-range slots return false.
is_gamepad_connected :: proc(gamepad: Gamepad_Index) -> bool {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return false
	}
	return input.gamepads_curr[gamepad].connected
}

// Returns the human-readable name of the controller in the given slot, or ""
// if the slot is empty or out of range. The string is valid until the next frame.
get_gamepad_name :: proc(gamepad: Gamepad_Index) -> string {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return ""
	}
	return input.gamepads_curr[gamepad].name
}

// Returns true if the gamepad button was pressed this frame.
gamepad_button_went_down :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return false
	}
	return(
		input.gamepads_curr[gamepad].button_held[button] &&
		!input.gamepads_prev[gamepad].button_held[button] \
	)
}

// Returns true if the gamepad button was released this frame.
gamepad_button_went_up :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return false
	}
	return(
		!input.gamepads_curr[gamepad].button_held[button] &&
		input.gamepads_prev[gamepad].button_held[button] \
	)
}

// Returns true if the gamepad button is currently held down.
gamepad_button_is_held :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return false
	}
	return input.gamepads_curr[gamepad].button_held[button]
}

// Returns the value of an analog axis. Sticks range -1..1 (negative = left/up),
// triggers range 0..1. Disconnected or out-of-range slots return 0.
get_gamepad_axis :: proc(gamepad: Gamepad_Index, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return 0
	}
	return input.gamepads_curr[gamepad].axes[axis]
}

// Set the rumble motor intensities (0..1) for a controller. `left` drives the
// low-frequency (heavy) motor, `right` the high-frequency (light) motor.
// `duration` is in seconds; 0 means "until changed" (refresh by calling each
// frame). No-op for empty or out-of-range slots, or backends without rumble.
set_gamepad_vibration :: proc(gamepad: Gamepad_Index, left, right: f32, duration: f32 = 0) {
	ctx.gamepad.set_vibration(gamepad, left, right, duration)
}

// Show the OS cursor.
show_cursor :: proc() {
	ctx.window.set_cursor_visible(true)
}

// Hide the OS cursor.
hide_cursor :: proc() {
	ctx.window.set_cursor_visible(false)
}

// Set the cursor to a system cursor shape.
set_cursor :: proc(cursor: System_Cursor) {
	ctx.window.set_system_cursor(cursor)
}

// Set a custom cursor from RGBA pixel data.
set_custom_cursor :: proc(pixels: []u8, width, height: int, hot_x: int = 0, hot_y: int = 0) {
	ctx.window.set_custom_cursor(pixels, width, height, hot_x, hot_y)
}
