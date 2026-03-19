#+build !js
// Desktop platform — uses SDL3 for windowing and wgpu for rendering.

package engine

// Desktop blocking event loop. Calls the stored frame_proc each iteration.
@(private = "package")
platform_run :: proc() {
	for ctx.window.poll_events() {
		if ctx.renderer.is_initialized() && ctx.frame_proc != nil {
			calculate_frame_time()
			ctx.frame_proc(ctx.frame_time)
		}
	}

	if ctx.shutdown_proc != nil {
		ctx.shutdown_proc()
	}
	engine_shutdown()
}
