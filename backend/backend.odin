// Shared types for backend wiring. The build-tagged files in this package
// provide the platform-specific `default` proc.

package backend

import core "../core"

Backends :: struct {
	window:   core.Window_Backend,
	renderer: core.Render_Backend,
}
