#+build !js
// Desktop backend wiring — selects SDL3 for windowing and wgpu for rendering.

package backend

import "../render/wgpu"
import "../window/sdl3"

default :: proc() -> Backends {
	return Backends{window = sdl3.backend(), renderer = wgpu.backend()}
}
