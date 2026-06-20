package core

// Maximum number of simultaneously-tracked gamepads.
MAX_GAMEPADS :: 4

// Identifies a gamepad slot, 0 to MAX_GAMEPADS-1. Slot 0 is "player one".
Gamepad_Index :: int

// Logical gamepad buttons, named by physical position rather than vendor label
// so the same code works across Xbox (A/B/X/Y), PlayStation
// (Cross/Circle/Square/Triangle), and Switch layouts.
Gamepad_Button :: enum {
	// Face buttons.
	South, // Xbox A    / PS Cross    / Switch B
	East, // Xbox B     / PS Circle   / Switch A
	West, // Xbox X     / PS Square   / Switch Y
	North, // Xbox Y    / PS Triangle / Switch X
	// Shoulders.
	Left_Shoulder,
	Right_Shoulder,
	// Triggers, as a threshold-based digital view of the analog trigger axes.
	Left_Trigger,
	Right_Trigger,
	// Stick clicks (L3 / R3).
	Left_Stick,
	Right_Stick,
	// D-pad.
	Dpad_Up,
	Dpad_Down,
	Dpad_Left,
	Dpad_Right,
	// Menu buttons.
	Start,
	Select,
	Guide,
}

// Analog gamepad axes. Sticks range -1..1 (negative = left/up), triggers 0..1.
Gamepad_Axis :: enum {
	Left_X,
	Left_Y,
	Right_X,
	Right_Y,
	Left_Trigger,
	Right_Trigger,
}

// Per-frame snapshot of one gamepad, filled by the gamepad backend's `poll`.
// The engine diffs successive snapshots to derive went-down / went-up edges.
Gamepad_State :: struct {
	connected:   bool,
	name:        string, // backend-owned; valid until the next poll
	button_held: [Gamepad_Button]bool,
	axes:        [Gamepad_Axis]f32,
}

// Gamepad_Backend abstracts over platform gamepad sources (SDL3 on desktop,
// the browser Gamepad API on web). Decoupled from Window_Backend because macOS
// pairs the native Cocoa window with SDL3 gamepad input.
Gamepad_Backend :: struct {
	// Initialize the gamepad subsystem.
	init:          proc(),

	// Tear down the gamepad subsystem and release any open controllers.
	shutdown:      proc(),

	// Fill the snapshot array with the current state of every slot. Slots with
	// no controller have `connected = false`.
	poll:          proc(state: ^[MAX_GAMEPADS]Gamepad_State),

	// Set rumble motor intensities (0..1). duration <= 0 means "until changed".
	set_vibration: proc(gamepad: Gamepad_Index, left, right: f32, duration: f32),
}
