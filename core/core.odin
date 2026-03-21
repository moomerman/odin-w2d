// Core types and interfaces shared between the engine and backend implementations.
// This package exists to break circular imports between the engine and its backends.

package core

// Opaque handle to a texture managed by the render backend.
// The backend maps this to its internal GPU resources.
Texture_Handle :: distinct u64

// Opaque handle to a loaded font. Index 0 is reserved as invalid.
Font :: distinct int

Vec2 :: [2]f32

Rect :: struct {
	x, y, w, h: f32,
}

Color :: [4]u8

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
