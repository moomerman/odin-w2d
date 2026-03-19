# WGPU 2D Wrapper — Status & Review

## Architecture

```
odin-wgpu/
├── build_web/                         # Odin build tool for wasm targets
│   ├── build_web.odin
│   └── index_template.html
├── engine.odin                        # Engine state, init/run lifecycle, timing
├── types.odin                         # Re-exports core types for the public API
├── draw.odin                          # Drawing API: clear, present, draw_rect, textures
├── render.odin                        # Re-exports core.Render_Backend
├── window.odin                        # Re-exports core.Window_Backend
├── platform_desktop.odin              # Desktop event loop (#+build !js)
├── platform_js.odin                   # Web step export (#+build js)
├── core/core.odin                     # Shared types & interfaces (breaks import cycles)
├── backend/                           # Platform backend wiring (internal, not user-facing)
│   ├── backend.odin                   # Backends struct
│   ├── backend_desktop.odin           # SDL3 + wgpu (#+build !js)
│   └── backend_js.odin               # JS + wgpu (#+build js)
├── render/wgpu/                       # wgpu renderer implementation
│   ├── wgpu.odin
│   └── shader.wgsl
├── window/sdl3/sdl3.odin             # SDL3 window backend
├── window/glfw/glfw.odin             # GLFW window backend (available, not wired up)
├── window/js/js.odin                 # JS/WASM window backend
└── examples/
    ├── hello/main.odin               # Colored rectangles
    └── texture/main.odin             # PNG + raw pixel textures
```

## Public API

```
// Lifecycle
w.init(1280, 720, "My Game")
w.run(game_init, game_frame, game_shutdown)

// Drawing
w.clear(color)
w.present()
w.draw_rect(rect, color)
w.draw_texture(tex, pos)
w.draw_texture(tex, pos, tint)
w.draw_texture_rect(tex, src, dst)

// Textures
w.load_texture(#load("image.png")) -> Texture           // from encoded image
w.load_texture(raw_pixels, width, height) -> Texture     // from raw RGBA8
w.destroy_texture(&tex)

// Timing
w.get_frame_time() -> f32
w.get_time() -> f64
```

### `run` lifecycle

- `init` — called once when the GPU device is ready. Load textures here.
- `frame(dt: f32)` — called every frame with delta time in seconds.
- `shutdown` — called on exit. Clean up your resources here.

### Backend selection

Backends are hardcoded per platform — the game doesn't need to specify them:
- **Desktop:** SDL3 window + wgpu renderer (wired in `backend/backend_desktop.odin`)
- **Web:** JS canvas + wgpu renderer (wired in `backend/backend_js.odin`)

A GLFW window backend exists in `window/glfw/` but is not currently wired up. The `Window_Backend` and `Render_Backend` interfaces (structs of procs in `core/`) are kept so a different backend can be swapped in later if needed.

```
odin build examples/hello                                # Desktop (SDL3 + wgpu)
odin run build_web -- examples/hello                     # Web (JS + wgpu)
```

## What's working

- **Window backends** — SDL3 (desktop), JS/WASM (web). Hardcoded per platform in `backend/`. GLFW backend available but not wired up.
- **Batched renderer** — texture-change triggers flush with correct vertex buffer offset tracking. 4096-quad batch limit. 1×1 white texture for solid shapes. Deferred bind group release for multi-texture correctness.
- **Texture loading** — unified `load_texture` handles both encoded images (PNG/BMP/TGA via `core:image`) and raw RGBA8 pixel data.
- **Shader** — orthographic projection, textured + vertex-colored quads via WGSL.
- **build_web tool** — Odin program following karl2d's pattern. Generates HTML from template, copies `odin.js` + `wgpu.js`, builds wasm.
- **Delta time** — `frame` callback receives `dt: f32`, `get_frame_time()` and `get_time()` available.
- **Cross-platform examples** — hello and texture both build and run on desktop (SDL3, GLFW) and web.

## Resolved issues

| # | Issue | Resolution |
|---|-------|------------|
| 1 | `Engine`/`engine` visible to importers | Added `@(private = "package")` |
| 2 | Dead `update()` proc | Removed |
| 3 | `draw_texture` took `^Texture` | Now takes `Texture` by value; renderer tracks by view handle |
| 4 | GLFW `c_title` memory leak | Stored in file-private global, freed in shutdown |
| 5 | No delta time | `frame` now receives `dt: f32`, timing tracked in engine |
| 6 | `RGBA8UnormSrgb` texture format | Switched to `RGBA8Unorm` for predictable results |
| 7 | Bind groups released mid-render-pass | Deferred release until after submit |
| 8 | Vertex buffer overwritten on flush | Track running offset, append rather than overwrite |
| 9 | Backend selection was runtime parameter | Now compile-time via `#config(WINDOW_BACKEND)` |
| 10 | Separate `load_texture` / `load_texture_from_bytes_raw` | Unified into single `load_texture` proc |
| 11 | Game had to import `config` package and pass backends | Removed `Config` struct and `config/` package; backends hardcoded per platform |

## Remaining items

### `Texture` exposes wgpu internals

`Texture` contains `wgpu.Texture` and `wgpu.TextureView` directly. For a real abstraction these should be opaque handles with the renderer owning the actual wgpu objects. Fine for now.

### No error handling on GPU resource creation

`load_texture` and internal renderer setup will panic on failure. Eventually these should return errors or optionals.

### File reorganisation

`wrapper.odin` currently contains types, engine lifecycle, drawing, textures, and timing. Natural splits:

| File | Contents |
|---|---|
| `types.odin` | `Vec2`, `Rect`, `Color`, `Texture`, color constants, `Window_Mode`, `Window_Options` |
| `engine.odin` | `Engine` struct, `init`/`run`/`engine_shutdown`, timing |
| `drawing.odin` | `draw_rect`, `draw_texture`, `draw_texture_rect`, `clear`, `present`, `load_texture`, `destroy_texture` |
| `input.odin` | (future) `key_went_down`, `get_mouse_position`, input state, enums |

---

## Roadmap

### Window Options

```odin
Window_Mode :: enum {
    Fixed,
    Resizable,    // current default
    Fullscreen,
}

Window_Options :: struct {
    mode: Window_Mode,
}
```

### Input handling

Follow karl2d's pattern: the window backends collect raw platform events, the wrapper processes them into a simple polled input state that the user queries each frame.

**Three layers:**

1. **Platform events (per-backend)** — add a `get_events` proc to `Window_Backend`. Each backend translates native events (SDL/GLFW/JS) into a common `Event` union type.

2. **Input state processing (wrapper internals)** — each frame, before calling `frame`, drain the event queue and update held/pressed/released arrays. Handle edge cases like releasing all held keys on window unfocus.

3. **Public query API (user-facing)** — polled functions:
    ```
    w.key_went_down(.Space) -> bool
    w.key_went_up(.Escape) -> bool
    w.key_is_held(.W) -> bool
    w.mouse_button_went_down(.Left) -> bool
    w.mouse_button_is_held(.Left) -> bool
    w.get_mouse_position() -> Vec2
    w.get_mouse_delta() -> Vec2
    w.get_mouse_wheel_delta() -> f32
    ```

**Scope for first pass:** keyboard + mouse only. No gamepad. Enough for Escape-to-quit, WASD movement, mouse-click interaction, mouse position.

### Text rendering

**Approach:** use `vendor:fontstash` — the same library karl2d uses.

Fontstash is a font atlas manager included in Odin's vendor packages. You give it TTF data, it rasterises glyphs on demand into a texture atlas, and returns quad positions + UVs. We render the quads through our existing batched renderer — the font atlas is just another texture.

**Why fontstash over alternatives:**

| Option | What it does | Verdict |
|---|---|---|
| `vendor:fontstash` | Atlas manager: TTF → glyph quads + UV coords | **Right choice.** Designed for 2D game engines, handles atlas packing and caching, renderer-agnostic. |
| `vendor:stb/truetype` | Raw font rasteriser (used internally by fontstash) | Too low-level — you'd rebuild atlas management from scratch. |
| `vendor:kb_text_shape` | Full Unicode/OpenType text shaping | Overkill — complex scripts and ligatures aren't needed for game text. Still needs a rasteriser on top. |

**Implementation path:**

1. Create a fontstash context during renderer init
2. Embed a default font (karl2d embeds one — we can do the same)
3. Font atlas becomes a wgpu texture, updated when fontstash rasterises new glyphs
4. `draw_text` calls fontstash for glyph layout, pushes quads through `renderer_push_quad` using atlas UVs
5. Expose minimal public API:
    ```
    w.draw_text(text, pos, size, color)
    w.measure_text(text, size) -> Vec2
    w.load_font(#load("myfont.ttf")) -> Font
    w.get_default_font() -> Font
    ```

**Reference:** karl2d's integration is in `karl2d.odin` (`_update_font`, `_set_font`, `draw_text_ex`) and uses fontstash's `FontContext` for layout + atlas management.

### CLI tool

Consolidate build tooling into a single command:

```
<project> build examples/texture
<project> web examples/texture
<project> serve examples/texture
```

`build_web` would become a subcommand of this tool.

### Rendering optimisations (future)

- **Texture atlas** — pack sprites into one texture to eliminate texture-switch flushes
- **Draw call sorting** — group by texture automatically (with layer/depth for ordering)
- **Bindless textures** — pass texture index per-vertex instead of rebinding (not universally supported on web)

## Render Statistics

import "core:fmt"
frame_count: int
stats :: proc() {
	frame_count += 1
	if frame_count % 60 == 0 {
		s := w.get_stats()
		fmt.printfln(
			"FPS: %.0f | Frame: %.1fms | Draw calls: %v | Quads: %v | Tex switches: %v | Textures: %v (%vKB)",
			s.fps,
			s.frame_time_ms,
			s.draw_calls,
			s.quads,
			s.texture_switches,
			s.textures_alive,
			s.texture_memory / 1024,
		)
	}
}
