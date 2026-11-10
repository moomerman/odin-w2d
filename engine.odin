package engine

import "core:time"

import "backend"

//-----------------------//
// ENGINE INTERNAL STATE //
//-----------------------//

@(private = "package")
Context :: struct {
	window:           Window_Backend,
	renderer:         Render_Backend,
	audio:            Audio_Backend,
	gamepad:          Gamepad_Backend,
	initialized:      bool,
	init_proc:        proc(),
	frame_proc:       proc(dt: f32),
	shutdown_proc:    proc(),
	init_called:      bool,
	quit_requested:   bool,
	headless:         bool,

	// Timing
	start_time:       time.Time,
	prev_frame_time:  time.Time,
	frame_time:       f32, // seconds since last frame
	fixed_frame_time: f32, // > 0: every frame reports exactly this dt (headless)
	elapsed_time:     f64, // seconds since init
	// Frames whose frame proc has run: during frame N's frame proc, N. The
	// one counter for get_frame_count and W2D_SCRIPT's `frame N` lines.
	frame_count:      int,

	// Camera
	camera:           Maybe(Camera),

	// Size of the active render texture, or nil when drawing to the window.
	target_size:      Maybe([2]int),
}

@(private = "package")
ctx: Context

//------------//
// PUBLIC API //
//------------//

// Initialize the engine. The platform layer selects the appropriate
// window and renderer backends automatically.
//
// On desktop, init also honours the W2D_* automation environment variables
// (W2D_HEADLESS, W2D_SCRIPT, W2D_FRAMES, W2D_SCREENSHOT), which let a test or
// an agent run any game unattended with no code changes. See automation.odin.
init :: proc(width: int, height: int, title: string) {
	auto := automation_configure()
	ctx.fixed_frame_time = auto.frame_time
	if auto.headless {
		ctx.headless = true
		init_with_backends(backend.headless(auto.scale), width, height, "")
		return
	}
	init_with_backends(backend.default(), width, height, title)
}

// Initialize the engine with no window, for tests and CI. Drawing goes to
// an offscreen target the size of the "window", so read_pixels,
// save_screenshot and render textures work as usual; nothing is shown and
// frames run as fast as they are drawn. Desktop only.
//
// `scale` stands in for a HiDPI backing scale: the framebuffer is
// width*scale by height*scale pixels while drawing coordinates stay
// width by height.
//
// `frame_time` is the dt every frame reports (and get_time advances by), so
// runs are deterministic whatever the machine's speed. Pass 0 for real time
// (except under W2D_RECORD, which needs a fixed dt and uses 1/60 s).
//
// There is no close button and no OS input: end the run with quit(), and
// drive input with the inject_* procs.
init_headless :: proc(width: int, height: int, scale: f32 = 1, frame_time: f32 = 1.0 / 60.0) {
	// W2D_SCRIPT / W2D_FRAMES still apply; headless, scale and dt are the
	// caller's, but a recording only replays faithfully at a fixed dt.
	auto := automation_configure()
	ctx.headless = true
	ctx.fixed_frame_time = frame_time
	if frame_time <= 0 && auto.record {
		ctx.fixed_frame_time = auto.frame_time
	}
	init_with_backends(backend.headless(scale), width, height, "")
}

// Resize the headless window, as a user dragging a window edge would. Takes
// effect immediately; call it between frames (outside clear/present).
// No effect unless the engine was started with init_headless.
set_headless_size :: proc(width: int, height: int) {
	if ctx.headless {
		backend.headless_resize(width, height)
	}
}

// Ask the run loop to stop. The current frame finishes, then shutdown_proc
// and the engine's own cleanup run and `run` returns (desktop) or the frame
// loop stops (web).
quit :: proc() {
	ctx.quit_requested = true
}

@(private = "file")
init_with_backends :: proc(backends: backend.Backends, width: int, height: int, title: string) {
	ctx.window = backends.window
	ctx.renderer = backends.renderer
	ctx.audio = backends.audio
	ctx.gamepad = backends.gamepad

	ctx.window.init(width, height, title, on_window_resize)
	// The gamepad backend is opt-in (see init_gamepad) so it stays off the
	// startup path for games that don't read a gamepad.

	ctx.start_time = time.now()
	ctx.prev_frame_time = ctx.start_time

	ctx.renderer.init(&ctx.window, on_renderer_initialized)
	ctx.initialized = true
}

// Run the game loop.
//
// `init_proc` is called once when the GPU device is fully initialized — use it
// for loading textures and other GPU resources. On desktop this fires before
// the first frame. On web it fires once the adapter/device callbacks complete.
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

	platform_run()
}

// Returns the time in seconds that the previous frame took.
get_frame_time :: proc() -> f32 {
	return ctx.frame_time
}

// Returns the number of the frame being run: 0 during the first call of the
// frame proc, 1 during the second, and so on (after the run, the number of
// frames run). This is the number W2D_SCRIPT's `frame N` lines and
// W2D_RECORD's output refer to.
get_frame_count :: proc() -> int {
	return ctx.frame_count
}

// Returns the time in seconds since `init` was called.
get_time :: proc() -> f64 {
	return ctx.elapsed_time
}

// Get the current screen size in logical pixels (points).
// On high-DPI displays this is the window size, not the physical framebuffer size.
get_screen_size :: proc() -> (int, int) {
	w, h := ctx.window.get_window_size()
	return int(w), int(h)
}

// Set the window mode (windowed, fixed-size, fullscreen, or borderless).
set_window_mode :: proc(mode: Window_Mode) {
	ctx.window.set_window_mode(mode)
}

// Enable (the default) or disable vsync. With vsync off the frame loop
// never waits for the display: frames run as fast as the GPU draws them,
// into an offscreen target, and the window shows the latest one about 60
// times a second (acquiring a window frame blocks at the display rate on
// macOS whatever the present mode, so this is how unthrottled works). For
// tests and script runs; use get_frame_time for movement either way.
// Takes effect from the next frame. No effect on web, where the browser
// paces frames.
set_vsync :: proc(enabled: bool) {
	ctx.renderer.set_vsync(enabled)
}

// Returns rendering statistics for the most recently completed frame.
get_stats :: proc() -> Stats {
	return ctx.renderer.get_stats(ctx.frame_time)
}

// Return the underlying GPU device handle. For the wgpu backend this is a wgpu.Device.
get_gpu_device :: proc() -> rawptr {
	return ctx.renderer.get_gpu_device()
}

// Return the underlying GPU queue handle. For the wgpu backend this is a wgpu.Queue.
get_gpu_queue :: proc() -> rawptr {
	return ctx.renderer.get_gpu_queue()
}

// Return the surface texture format as a u32 (cast to your backend's format enum).
get_surface_format :: proc() -> u32 {
	return ctx.renderer.get_surface_format()
}

// Set a callback invoked after engine flush but before the render pass ends.
// Use this for custom renderers that need to draw into the same render pass.
set_pre_present_callback :: proc(callback: proc(pass: rawptr, width, height: u32)) {
	ctx.renderer.set_pre_present_callback(callback)
}

// Called by the render backend once the GPU device is ready.
// Initializes engine subsystems that need the GPU (text rendering).
// The user's init_proc is called from the frame loop once the renderer is ready.
@(private = "package")
on_renderer_initialized :: proc() {
	text_init()
}

// Called by window backends when the framebuffer is resized.
@(private = "package")
on_window_resize :: proc() {
	if ctx.renderer.is_initialized() {
		ctx.renderer.resize()
		// Re-apply camera transform after resize resets the projection.
		if ctx.camera != nil {
			upload_view_projection()
		}
	}
}

// Shut down the engine. Called internally after the user's shutdown_proc.
@(private = "package")
engine_shutdown :: proc() {
	ctx.audio.shutdown()
	if input.gamepad_active {
		ctx.gamepad.shutdown()
	}
	text_shutdown()
	assets_shutdown()
	input_shutdown()
	ctx.renderer.shutdown()
	ctx.window.shutdown()
	ctx.initialized = false
}

// Calculate frame timing. Called internally before each frame callback.
@(private = "package")
calculate_frame_time :: proc() {
	if ctx.fixed_frame_time > 0 {
		// The first frame reports 0, like the real-time path.
		if ctx.prev_frame_time != {} {
			ctx.frame_time = ctx.fixed_frame_time
			ctx.elapsed_time += f64(ctx.fixed_frame_time)
		}
		ctx.prev_frame_time = time.now()
		return
	}

	now := time.now()

	if ctx.prev_frame_time != {} {
		since := time.diff(ctx.prev_frame_time, now)
		ctx.frame_time = f32(time.duration_seconds(since))
	}

	ctx.prev_frame_time = now
	ctx.elapsed_time = time.duration_seconds(time.since(ctx.start_time))
}
