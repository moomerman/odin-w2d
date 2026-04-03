#+build !js
// Desktop platform — blocking event loop for native windowing backends.

package engine

// Desktop blocking event loop. Calls the stored frame_proc each iteration.
@(private = "package")
platform_run :: proc() {
	for {
		// On macOS the Metal backend creates autoreleased ObjC objects each
		// frame (via wgpu's Metal backend and SDL3).  Without draining the
		// pool they accumulate and leak.
		pool := _autorelease_pool_begin()
		defer _autorelease_pool_end(pool)

		if !ctx.window.poll_events() {
			break
		}
		if ctx.renderer.is_initialized() {
			if !ctx.init_called {
				if ctx.init_proc != nil {
					ctx.init_proc()
				}
				ctx.init_called = true
			}
			if ctx.frame_proc != nil {
				process_input()
				calculate_frame_time()
				ctx.audio.update()
				ctx.frame_proc(ctx.frame_time)
			}
		}
	}

	if ctx.shutdown_proc != nil {
		ctx.shutdown_proc()
	}
	engine_shutdown()
}
