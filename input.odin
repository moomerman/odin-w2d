package engine

import "core"

// Number of mouse buttons we track.
@(private = "file")
MOUSE_BUTTON_COUNT :: len(core.Mouse_Button)

@(private = "package")
Input_State :: struct {
	mouse_pos:       Vec2,
	mouse_delta:     Vec2,
	mouse_held:      [MOUSE_BUTTON_COUNT]bool,
	mouse_went_down: [MOUSE_BUTTON_COUNT]bool,
	mouse_went_up:   [MOUSE_BUTTON_COUNT]bool,
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
			} else {
				input.mouse_held[btn] = false
				input.mouse_went_up[btn] = true
			}
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
