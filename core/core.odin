// Core types and interfaces shared between the engine and backend implementations.
// This package exists to break circular imports between the engine and its backends.

package core

import "vendor:wgpu"

//----------//
// INPUT    //
//----------//

Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}

// Physical keyboard keys. Values match SDL3 scancodes for efficient desktop mapping.
Key :: enum u16 {
	// Letters
	A = 4, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,

	// Digits
	Key_1 = 30, Key_2, Key_3, Key_4, Key_5,
	Key_6, Key_7, Key_8, Key_9, Key_0,

	// Common keys
	Return    = 40,
	Escape    = 41,
	Backspace = 42,
	Tab       = 43,
	Space     = 44,

	// Punctuation
	Minus        = 45,
	Equals       = 46,
	Left_Bracket = 47,
	Right_Bracket = 48,
	Backslash    = 49,
	Semicolon    = 51,
	Apostrophe   = 52,
	Grave        = 53,
	Comma        = 54,
	Period       = 55,
	Slash        = 56,

	// Function keys
	F1  = 58, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,

	// Navigation
	Insert   = 73,
	Home     = 74,
	Page_Up  = 75,
	Delete   = 76,
	End      = 77,
	Page_Down = 78,

	// Arrows
	Right = 79,
	Left  = 80,
	Down  = 81,
	Up    = 82,

	// Modifiers
	Left_Ctrl   = 224,
	Left_Shift  = 225,
	Left_Alt    = 226,
	Left_Super  = 227,
	Right_Ctrl  = 228,
	Right_Shift = 229,
	Right_Alt   = 230,
	Right_Super = 231,
}

Event :: union {
	Mouse_Move_Event,
	Mouse_Button_Event,
	Key_Event,
}

Mouse_Move_Event :: struct {
	pos:   Vec2,
	delta: Vec2,
}

Mouse_Button_Event :: struct {
	button: Mouse_Button,
	down:   bool, // true = pressed, false = released
	pos:    Vec2,
}

Key_Event :: struct {
	key:    Key,
	down:   bool, // true = pressed, false = released
	repeat: bool, // true if this is a key-repeat event
}

// Opaque handle to a texture managed by the render backend.
// The backend maps this to its internal GPU resources.
Texture_Handle :: distinct u64

Vec2 :: [2]f32

Rect :: struct {
	x, y, w, h: f32,
}

Color :: [4]u8

// Texture is backend-agnostic. The handle is an opaque ID managed by
// the active Render_Backend; width and height are cached for convenience.
Texture :: struct {
	handle: Texture_Handle,
	width:  int,
	height: int,
}

Stats :: struct {
	frame_time_ms:    f32, // last frame time in milliseconds
	fps:              f32, // frames per second (1 / frame_time)
	draw_calls:       int, // number of flush/draw calls this frame
	quads:            int, // total quads drawn this frame
	vertices:         int, // total vertices drawn this frame
	texture_switches: int, // number of texture changes that triggered a flush
	textures_alive:   int, // currently live textures
	texture_memory:   int, // estimated bytes of live texture data (w * h * 4)
}

// Window_Backend abstracts over different windowing libraries (SDL3, GLFW, JS).
// Each backend provides an implementation of these procedures.
Window_Backend :: struct {
	// Create the window with the given dimensions and title.
	// on_resize is called when the framebuffer size changes so the engine
	// can reconfigure the renderer.
	init:                 proc(width, height: int, title: string, on_resize: proc()),

	// Destroy the window and clean up platform resources.
	shutdown:             proc(),

	// Poll for window/input events. Returns false when the user has requested to close the window.
	poll_events:          proc() -> bool,

	// Create a wgpu surface for the window.
	get_surface:          proc(instance: wgpu.Instance) -> wgpu.Surface,

	// Get the framebuffer size in physical pixels.
	get_framebuffer_size: proc() -> (width: u32, height: u32),

	// Return buffered input events since the last call, then clear the buffer.
	get_events:           proc() -> []Event,
}

// Render_Backend abstracts over different rendering implementations.
// Currently the only backend is wgpu (render/wgpu package).
Render_Backend :: struct {
	// Initialize the renderer with the given window backend.
	// on_initialized is called once the GPU device is ready (synchronous on desktop,
	// async on web) — the engine uses this to fire the user's init callback.
	init:              proc(window: ^Window_Backend, on_initialized: proc()),

	// Shut down the renderer and release all GPU resources.
	shutdown:          proc(),

	// Handle a window resize — reconfigure the swapchain and projection.
	resize:            proc(),

	// Returns true once the GPU device is ready and rendering can begin.
	is_initialized:    proc() -> bool,

	// Begin a new frame, clearing the screen with the given color.
	// Returns false if the surface is unavailable (e.g. minimized).
	begin_frame:       proc(color: Color) -> bool,

	// Submit the current frame to the GPU and present it.
	present:           proc(),

	// Flush all batched vertices to the GPU.
	flush:             proc(),

	// Push a textured quad into the current batch.
	push_quad:         proc(dst: Rect, src_uv: [4][2]f32, tex: Texture_Handle, color: Color),

	// Push a textured quad with explicit vertex positions (for rotated/arbitrary quads).
	push_quad_ex:      proc(
		positions: [4]Vec2,
		src_uv: [4][2]f32,
		tex: Texture_Handle,
		color: Color,
	),

	// Create a texture from raw RGBA8 pixel data. Returns an opaque handle.
	create_texture:    proc(data: []u8, width, height: int) -> Texture_Handle,

	// Destroy a texture and free its GPU resources.
	destroy_texture:   proc(handle: Texture_Handle),

	// Get the built-in 1x1 white texture used for solid color drawing.
	get_white_texture: proc() -> Texture_Handle,

	// Get rendering statistics for the most recently completed frame.
	get_stats:         proc(frame_time: f32) -> Stats,
}

//----------//
// COLORS   //
//----------//

BLACK :: Color{0, 0, 0, 255}
WHITE :: Color{255, 255, 255, 255}
BLANK :: Color{0, 0, 0, 0}
GRAY :: Color{128, 128, 128, 255}
DARK_GRAY :: Color{80, 80, 80, 255}
LIGHT_GRAY :: Color{200, 200, 200, 255}
RED :: Color{230, 41, 55, 255}
DARK_RED :: Color{150, 30, 30, 255}
GREEN :: Color{0, 228, 48, 255}
DARK_GREEN :: Color{0, 117, 44, 255}
BLUE :: Color{0, 121, 241, 255}
DARK_BLUE :: Color{0, 82, 172, 255}
LIGHT_BLUE :: Color{102, 191, 255, 255}
ORANGE :: Color{255, 161, 0, 255}
YELLOW :: Color{253, 249, 0, 255}
PURPLE :: Color{200, 122, 255, 255}
MAGENTA :: Color{255, 0, 255, 255}
BROWN :: Color{127, 106, 79, 255}
