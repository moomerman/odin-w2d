#+build !js
// SDL3 gamepad backend. Serves every desktop platform (macOS, Linux, Windows):
// SDL's gamepad subsystem runs independently of windowing, so it pairs with the
// native Cocoa window backend on macOS just as it does with the SDL3 window
// backend elsewhere. Brings hot-plug, the SDL_GameControllerDB mapping
// database, and rumble for free.

package gamepad_sdl3

import "core:strings"

import SDL "vendor:sdl3"

import core "../../core"

// Trigger axis value (0..32767) above which the digital trigger button reads
// as pressed.
@(private = "file")
TRIGGER_BUTTON_THRESHOLD :: f32(0.5)

// Open controller handles, one per slot. nil = empty slot.
@(private = "file")
handles: [core.MAX_GAMEPADS]^SDL.Gamepad

// Name strings handed out in the last poll, freed and rebuilt each poll so the
// snapshot's `name` stays valid until the following poll.
@(private = "file")
names: [core.MAX_GAMEPADS]string

// Maps our position-named buttons onto SDL's button enum. The two trigger
// entries are .INVALID — triggers are analog axes in SDL, so the digital
// trigger buttons are derived from the axis value instead.
@(private = "file")
BUTTON_MAP := [core.Gamepad_Button]SDL.GamepadButton {
	.South          = .SOUTH,
	.East           = .EAST,
	.West           = .WEST,
	.North          = .NORTH,
	.Left_Shoulder  = .LEFT_SHOULDER,
	.Right_Shoulder = .RIGHT_SHOULDER,
	.Left_Trigger   = .INVALID,
	.Right_Trigger  = .INVALID,
	.Left_Stick     = .LEFT_STICK,
	.Right_Stick    = .RIGHT_STICK,
	.Dpad_Up        = .DPAD_UP,
	.Dpad_Down      = .DPAD_DOWN,
	.Dpad_Left      = .DPAD_LEFT,
	.Dpad_Right     = .DPAD_RIGHT,
	.Start          = .START,
	.Select         = .BACK,
	.Guide          = .GUIDE,
}

backend :: proc() -> core.Gamepad_Backend {
	return core.Gamepad_Backend {
		init = gamepad_init,
		shutdown = gamepad_shutdown,
		poll = gamepad_poll,
		set_vibration = gamepad_set_vibration,
	}
}

@(private = "file")
gamepad_init :: proc() {
	// Refcounted: harmless that the SDL3 window backend may have already inited
	// {.VIDEO}, and works standalone under the Cocoa window backend on macOS.
	_ = SDL.Init({.GAMEPAD})
}

@(private = "file")
gamepad_shutdown :: proc() {
	for &handle in handles {
		if handle != nil {
			SDL.CloseGamepad(handle)
			handle = nil
		}
	}
	for &name in names {
		delete(name)
		name = ""
	}
	SDL.QuitSubSystem({.GAMEPAD})
}

@(private = "file")
gamepad_poll :: proc(state: ^[core.MAX_GAMEPADS]core.Gamepad_State) {
	SDL.UpdateGamepads()

	// Refresh the slot -> handle assignment from the set of connected devices.
	// SDL ids are stable while a controller stays plugged in, so a controller
	// keeps its slot across frames; unplugged controllers free their slot.
	assign_slots()

	for handle, i in handles {
		s := &state[i]
		s^ = {}
		if handle == nil {
			continue
		}

		s.connected = true
		s.name = names[i]

		for axis in core.Gamepad_Axis {
			raw := SDL.GetGamepadAxis(handle, SDL.GamepadAxis(axis))
			s.axes[axis] = f32(raw) / 32767.0
		}

		for button in core.Gamepad_Button {
			sdl_button := BUTTON_MAP[button]
			if sdl_button == .INVALID {
				continue
			}
			s.button_held[button] = SDL.GetGamepadButton(handle, sdl_button)
		}
		// Derive the digital trigger buttons from the analog axes.
		s.button_held[.Left_Trigger] = s.axes[.Left_Trigger] > TRIGGER_BUTTON_THRESHOLD
		s.button_held[.Right_Trigger] = s.axes[.Right_Trigger] > TRIGGER_BUTTON_THRESHOLD
	}
}

@(private = "file")
gamepad_set_vibration :: proc(gamepad: core.Gamepad_Index, left, right: f32, duration: f32) {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return
	}
	handle := handles[gamepad]
	if handle == nil {
		return
	}
	lo := u16(clamp(left, 0, 1) * 0xFFFF)
	hi := u16(clamp(right, 0, 1) * 0xFFFF)
	// duration <= 0 means "until changed"; SDL has no infinite value, so use a
	// long window that the caller refreshes by calling again each frame.
	ms := duration > 0 ? u32(duration * 1000) : u32(0xFFFFFFFF)
	_ = SDL.RumbleGamepad(handle, lo, hi, ms)
}

// Reconcile open handles with the currently connected controllers. Keeps a
// controller in its existing slot, closes handles for unplugged controllers,
// and assigns newly connected controllers to the lowest free slot.
@(private = "file")
assign_slots :: proc() {
	count: i32
	ids := SDL.GetGamepads(&count)

	// Drop handles whose controller is no longer connected.
	for &handle, i in handles {
		if handle == nil {
			continue
		}
		id := SDL.GetGamepadID(handle)
		still_present := false
		for j in 0 ..< count {
			if ids[j] == id {
				still_present = true
				break
			}
		}
		if !still_present {
			SDL.CloseGamepad(handle)
			handle = nil
			delete(names[i])
			names[i] = ""
		}
	}

	// Assign any connected controller that does not yet occupy a slot.
	for j in 0 ..< count {
		id := ids[j]
		if find_slot(id) >= 0 {
			continue
		}
		slot := free_slot()
		if slot < 0 {
			break // all MAX_GAMEPADS slots in use
		}
		handle := SDL.OpenGamepad(id)
		if handle == nil {
			continue
		}
		handles[slot] = handle
		names[slot] = strings.clone_from_cstring(SDL.GetGamepadName(handle))
	}
}

@(private = "file")
find_slot :: proc(id: SDL.JoystickID) -> int {
	for handle, i in handles {
		if handle != nil && SDL.GetGamepadID(handle) == id {
			return i
		}
	}
	return -1
}

@(private = "file")
free_slot :: proc() -> int {
	for handle, i in handles {
		if handle == nil {
			return i
		}
	}
	return -1
}
