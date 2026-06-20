#+build !darwin
#+build !js
// Non-macOS desktop backend wiring — uses SDL3 for windowing.

package backend

import "../audio/miniaudio"
import gamepad_sdl3 "../gamepad/sdl3"
import "../render/wgpu"
import "../window/sdl3"

default :: proc() -> Backends {
	return Backends {
		window = sdl3.backend(),
		renderer = wgpu.backend(),
		audio = miniaudio.backend(),
		gamepad = gamepad_sdl3.backend(),
	}
}
