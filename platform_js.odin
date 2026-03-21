#+build js
// Web platform — uses JS canvas for windowing and wgpu for rendering.

package engine

import "base:runtime"

@(private = "file")
js_ctx: runtime.Context

// On web, the runtime drives frames via the exported `step` proc.
// main() returns immediately after calling this.
@(private = "package")
platform_run :: proc() {
	js_ctx = context
	// Nothing to do — step() handles the frame loop.
}

// Called by the wasm runtime on each animation frame.
@(export)
step :: proc(dt: f32) -> bool {
	context = js_ctx

	if !ctx.initialized {
		return true
	}

	if ctx.init_called && ctx.frame_proc != nil {
		process_input()
		calculate_frame_time()
		if ctx.audio.update != nil {
			ctx.audio.update()
		}
		ctx.frame_proc(ctx.frame_time)
	}

	return true
}

@(fini)
js_fini :: proc "contextless" () {
	context = js_ctx
	if ctx.shutdown_proc != nil {
		ctx.shutdown_proc()
	}
	engine_shutdown()
}
