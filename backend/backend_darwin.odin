#+build darwin
#+build !js

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
