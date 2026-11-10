#+build js
package engine

import "core"

// Automation (see automation.odin) is driven by environment variables and
// writes screenshots to disk; neither exists on web, so these are no-ops.

@(private = "package")
Automation_Config :: struct {
	headless:   bool,
	scale:      f32,
	record:     bool, // W2D_RECORD is set: the timestep must be fixed
	frame_time: f32,
}

@(private = "package")
automation_configure :: proc() -> Automation_Config {
	return {scale = 1}
}

@(private = "package")
automation_begin_frame :: proc() {}

@(private = "package")
automation_present :: proc() {}

@(private = "package")
automation_end_frame :: proc() {}

@(private = "package")
automation_finish :: proc() {}

@(private = "package")
automation_record_event :: proc(event: core.Event) {}

@(private = "package")
automation_record_frame :: proc() {}
