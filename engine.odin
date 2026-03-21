package engine

import "core:time"

import "backend"

//-----------------------//
// ENGINE INTERNAL STATE //
//-----------------------//

@(private = "package")
Context :: struct {
	window:          Window_Backend,
	renderer:        Render_Backend,
	audio:           Audio_Backend,
	initialized:     bool,
	init_proc:       proc(),
	frame_proc:      proc(dt: f32),
	shutdown_proc:   proc(),
	init_called:     bool,

	// Timing
	start_time:      time.Time,
	prev_frame_time: time.Time,
	frame_time:      f32, // seconds since last frame
	elapsed_time:    f64, // seconds since init
}

@(private = "package")
ctx: Context

//------------//
// PUBLIC API //
//------------//

// Initialize the engine. The platform layer selects the appropriate
// window and renderer backends automatically.
init :: proc(width: int, height: int, title: string) {
	defaults := backend.default()
	ctx.window = defaults.window
	ctx.renderer = defaults.renderer
	ctx.audio = defaults.audio

	ctx.window.init(width, height, title, on_window_resize)

	ctx.start_time = time.now()
	ctx.prev_frame_time = ctx.start_time

	ctx.renderer.init(&ctx.window, on_renderer_initialized)
	ctx.initialized = true
}

// Run the game loop.
//
// `init_proc` is called once when the GPU device is fully initialized — use it
// for loading textures and other GPU resources. On desktop this fires
// synchronously before the first frame. On web it fires asynchronously once the
// adapter/device callbacks complete.
//
// `frame` is called every frame after `init_proc` has run. It receives the delta
// time (seconds since the previous frame) as its argument.
//
// `shutdown_proc` is called once when the window is closed — use it for cleaning
// up your own resources (textures, etc.). The engine handles its own internal
// cleanup afterwards.
//
// On desktop this runs a blocking loop. On web it stores the callbacks and
// returns immediately — the wasm runtime drives frames via the exported `step`
// procedure.
run :: proc(init_proc: proc(), frame_proc: proc(dt: f32), shutdown_proc: proc()) {
	ctx.init_proc = init_proc
	ctx.frame_proc = frame_proc
	ctx.shutdown_proc = shutdown_proc
	ctx.init_called = false

	// On desktop the renderer is already initialized (callbacks fire synchronously
	// during init), so call the init proc immediately before entering the loop.
	if ctx.renderer.is_initialized() && !ctx.init_called {
		init_proc()
		ctx.init_called = true
	}

	platform_run()
}

// Returns the time in seconds that the previous frame took.
get_frame_time :: proc() -> f32 {
	return ctx.frame_time
}

// Returns the time in seconds since `init` was called.
get_time :: proc() -> f64 {
	return ctx.elapsed_time
}

// Returns rendering statistics for the most recently completed frame.
get_stats :: proc() -> Stats {
	return ctx.renderer.get_stats(ctx.frame_time)
}

// Called by the render backend once the GPU device is ready.
// On desktop this fires synchronously during init(); on web it fires
// asynchronously once the adapter/device callbacks complete.
@(private = "package")
on_renderer_initialized :: proc() {
	text_init()

	if ctx.init_proc != nil {
		ctx.init_proc()
	}
	ctx.init_called = true
}

// Called by window backends when the framebuffer is resized.
@(private = "package")
on_window_resize :: proc() {
	if ctx.renderer.is_initialized() {
		ctx.renderer.resize()
	}
}

// Shut down the engine. Called internally after the user's shutdown_proc.
@(private = "package")
engine_shutdown :: proc() {
	if ctx.audio.shutdown != nil {
		ctx.audio.shutdown()
	}
	text_shutdown()
	ctx.renderer.shutdown()
	ctx.window.shutdown()
	ctx.initialized = false
}

// Calculate frame timing. Called internally before each frame callback.
@(private = "package")
calculate_frame_time :: proc() {
	now := time.now()

	if ctx.prev_frame_time != {} {
		since := time.diff(ctx.prev_frame_time, now)
		ctx.frame_time = f32(time.duration_seconds(since))
	}

	ctx.prev_frame_time = now
	ctx.elapsed_time = time.duration_seconds(time.since(ctx.start_time))
}
