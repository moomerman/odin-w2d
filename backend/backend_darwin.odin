#+build darwin
#+build !js

package backend

import "../audio/miniaudio"
import "../render/wgpu"
import "../window/darwin"
// import "../window/glfw"
// import "../window/sdl3"

default :: proc() -> Backends {
	return Backends {
		window = darwin.backend(),
		renderer = wgpu.backend(),
		audio = miniaudio.backend(),
	}
}
