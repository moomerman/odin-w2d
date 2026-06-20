#+build js
// Web backend wiring — selects JS canvas for windowing and wgpu for rendering.

package backend

import "../audio/webaudio"
import gamepad_js "../gamepad/js"
import "../render/wgpu"
import "../window/js"

default :: proc() -> Backends {
	return Backends {
		window = js.backend(),
		renderer = wgpu.backend(),
		audio = webaudio.backend(),
		gamepad = gamepad_js.backend(),
	}
}
