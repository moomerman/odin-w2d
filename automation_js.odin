#+build js
package engine

// Automation (see automation.odin) is driven by environment variables and
// writes screenshots to disk; neither exists on web, so these are no-ops.

@(private = "package")
Automation_Config :: struct {
	headless:   bool,
	scale:      f32,
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
