#+build js
// Web gamepad backend, backed by the browser Gamepad API (navigator.getGamepads).
// The JS shim in gamepad_js.js packs a numeric snapshot into the wasm heap each
// poll; this side unpacks it into Gamepad_State.
//
// Browser caveats: the page sees a controller only after the user presses a
// button on it (a security gate), and reliable button/axis layout requires the
// "standard" mapping — most Xbox/PS pads and Switch Pro (in Chromium) report it.

package gamepad_js

import core "../../core"

@(private = "file")
N_BUTTONS :: len(core.Gamepad_Button)

@(private = "file")
N_AXES :: len(core.Gamepad_Axis)

// Floats per pad in the packed buffer: 1 connected flag + buttons + axes.
@(private = "file")
SLOTS_PER_PAD :: 1 + N_BUTTONS + N_AXES

// Scratch buffer the JS shim writes each poll, then we unpack.
@(private = "file")
packed: [core.MAX_GAMEPADS * SLOTS_PER_PAD]f32

// Per-pad name bytes, kept alive between polls so Gamepad_State.name stays valid.
@(private = "file")
name_bufs: [core.MAX_GAMEPADS][64]u8

foreign import gamepad_js "gamepad_js"

@(default_calling_convention = "contextless")
foreign gamepad_js {
	// Writes SLOTS_PER_PAD floats per pad into the buffer (connected, buttons, axes).
	_js_poll_gamepads :: proc(ptr: [^]f32, len: int) ---
	// Writes up to max_len UTF-8 bytes of the pad's id into ptr; returns byte count.
	_js_get_gamepad_name :: proc(index: int, ptr: [^]u8, max_len: int) -> int ---
	// Best-effort dual-rumble via the gamepad's vibrationActuator.
	_js_set_gamepad_vibration :: proc(index: int, left, right: f32, duration_ms: int) ---
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
gamepad_init :: proc() {}

@(private = "file")
gamepad_shutdown :: proc() {}

@(private = "file")
gamepad_poll :: proc(state: ^[core.MAX_GAMEPADS]core.Gamepad_State) {
	_js_poll_gamepads(&packed[0], len(packed))

	for i in 0 ..< core.MAX_GAMEPADS {
		base := i * SLOTS_PER_PAD
		s := &state[i]
		s^ = {}

		if packed[base] == 0 {
			continue
		}
		s.connected = true

		for button in core.Gamepad_Button {
			s.button_held[button] = packed[base + 1 + int(button)] != 0
		}
		for axis in core.Gamepad_Axis {
			s.axes[axis] = packed[base + 1 + N_BUTTONS + int(axis)]
		}

		n := _js_get_gamepad_name(i, &name_bufs[i][0], len(name_bufs[i]))
		s.name = string(name_bufs[i][:n])
	}
}

@(private = "file")
gamepad_set_vibration :: proc(gamepad: core.Gamepad_Index, left, right: f32, duration: f32) {
	if gamepad < 0 || gamepad >= core.MAX_GAMEPADS {
		return
	}
	// The Web vibration API needs a finite duration; "until changed" (0) maps to
	// a short window that the caller refreshes by calling again each frame.
	ms := duration > 0 ? int(duration * 1000) : 200
	_js_set_gamepad_vibration(gamepad, left, right, ms)
}
