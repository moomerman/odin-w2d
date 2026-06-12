#+build darwin
#+build !js
// macOS backend wiring. The native Cocoa window backend is preferred over
// SDL3 for two reasons: vendor:sdl3 links system:SDL3 on macOS (a brew
// dependency for developers and a dylib to bundle for players), while Cocoa
// keeps builds fully self-contained; and momentum scrolling
// (get_scroll_delta's include_momentum) needs NSEvent.momentumPhase, which
// SDL does not expose.
//
// To A/B-test against SDL3 (requires `brew install sdl3`), temporarily swap
// the import and backend call to ../window/sdl3 — Odin forbids imports
// inside `when` blocks, so this cannot be a #config switch.

package backend

import "../audio/miniaudio"
import "../render/wgpu"
import "../window/darwin"

default :: proc() -> Backends {
	return Backends {
		window = darwin.backend(),
		renderer = wgpu.backend(),
		audio = miniaudio.backend(),
	}
}
