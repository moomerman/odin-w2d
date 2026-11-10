// Shared types for backend wiring. The build-tagged files in this package
// provide the platform-specific `default` proc.

package backend

import core "../core"
import window_null "../window/null"

Backends :: struct {
	window:   core.Window_Backend,
	renderer: core.Render_Backend,
	audio:    core.Audio_Backend,
	gamepad:  core.Gamepad_Backend,
}

// The platform's default backends with the window replaced by the null
// window backend: no OS window and no surface. See window/null.
headless :: proc(scale: f32) -> Backends {
	backends := default()
	backends.window = window_null.backend(scale)
	return backends
}

// Resize the headless window (no-op effect unless `headless` backends are in use).
headless_resize :: proc(width, height: int) {
	window_null.resize(width, height)
}
