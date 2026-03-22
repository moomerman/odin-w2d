#+build darwin
#+build !js
// macOS backend wiring — uses native Cocoa window backend to avoid SDL3 event
// handling delays caused by window managers like Magnet.

package backend

import "../audio/miniaudio"
import "../render/wgpu"
// import "../window/sdl3"
import "../window/darwin"

default :: proc() -> Backends {
	return Backends {
		window = darwin.backend(),
		renderer = wgpu.backend(),
		audio = miniaudio.backend(),
	}
}
