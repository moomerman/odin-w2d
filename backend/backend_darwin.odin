#+build darwin
#+build !js
// macOS backend wiring. The native Cocoa window backend is preferred over
// SDL3 for windowing for two reasons: vendor:sdl3 links system:SDL3 on macOS
// (a brew dependency for developers and a dylib to bundle for players), while
// Cocoa keeps the window path self-contained; and momentum scrolling
// (get_scroll_delta's include_momentum) needs NSEvent.momentumPhase, which
// SDL does not expose.
//
// Gamepad input, however, does use SDL3: SDL's gamepad subsystem runs
// independently of windowing and brings hot-plug, the SDL_GameControllerDB
// mapping database, and rumble for free, which is not worth reimplementing
// against the native GameController framework. So this target links SDL3 for
// gamepad input while keeping Cocoa for the window.
//
// To A/B-test windowing against SDL3 (requires `brew install sdl3`), temporarily
// swap the import and backend call to ../window/sdl3 — Odin forbids imports
// inside `when` blocks, so this cannot be a #config switch.

package backend

import "../audio/miniaudio"
import gamepad_sdl3 "../gamepad/sdl3"
import "../render/wgpu"
import "../window/darwin"

default :: proc() -> Backends {
	return Backends {
		window = darwin.backend(),
		renderer = wgpu.backend(),
		audio = miniaudio.backend(),
		gamepad = gamepad_sdl3.backend(),
	}
}
