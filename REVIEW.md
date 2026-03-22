# Code Review

## Architecture

```
odin-wgpu/
├── engine.odin                        # Engine state, init/run lifecycle, timing
├── types.odin                         # Re-exports core types for the public API
├── draw.odin                          # Drawing API: clear, present, rect, line, textures, stats
├── input.odin                         # Input processing and query API (keyboard, mouse, cursor)
├── text.odin                          # Text rendering via fontstash (TTF, atlas, measurement)
├── audio.odin                         # Audio API (playback, buses, spatial, listener)
├── shader.odin                        # Custom WGSL shader API
├── platform_desktop.odin              # Desktop event loop (#+build !js)
├── platform_js.odin                   # Web step export (#+build js)
├── autorelease_darwin.odin            # macOS autorelease pool management
├── autorelease_other.odin             # No-op for non-macOS
├── core/                              # Shared types & interfaces (breaks import cycles)
│   ├── core.odin                      # Vec2, Rect, Color, Stats, color constants
│   ├── window.odin                    # Window_Backend interface
│   ├── render.odin                    # Render_Backend interface, Texture, Shader
│   ├── audio.odin                     # Audio_Backend interface, Audio types
│   └── input.odin                     # Key, Mouse_Button, Event union, System_Cursor
├── backend/                           # Platform backend wiring (compile-time selection)
│   ├── backend.odin                   # Backends struct
│   ├── backend_desktop.odin           # SDL3 + wgpu + miniaudio (#+build !darwin !js)
│   ├── backend_darwin.odin            # Cocoa + wgpu + miniaudio (#+build darwin)
│   └── backend_js.odin               # JS + wgpu + webaudio (#+build js)
├── window/
│   ├── sdl3/sdl3.odin                 # SDL3 window backend
│   ├── darwin/darwin.odin             # Native Cocoa window backend (macOS)
│   ├── glfw/glfw.odin                 # GLFW backend (available, not wired up)
│   └── js/js.odin                     # JS/WASM window backend
├── render/wgpu/
│   ├── wgpu.odin                      # Batched renderer (textures, quads, shaders)
│   ├── wgsl_parser.odin               # WGSL parser for custom shader uniform metadata
│   └── shader.wgsl                    # Default vertex/fragment shader
├── audio/
│   ├── miniaudio/miniaudio.odin       # Desktop audio (buses, spatial, instances)
│   └── webaudio/                      # Web Audio API backend + JS glue
├── tools/
│   ├── build_web/                     # WASM build tool (HTML template, odin.js, wgpu.js)
│   ├── tracking_allocator/            # Memory leak detection utility
│   └── time_tracker/                  # Frame timing profiler
├── fonts/roboto.ttf                   # Embedded default font
└── examples/                          # 9 examples (hello → lemmings full game)
```

## What's working

- **Window backends** — SDL3 (desktop), native Cocoa (macOS), JS/WASM (web). Compile-time selection via build tags. GLFW backend available but not wired up.
- **Batched renderer** — texture-change triggers flush with correct vertex buffer offset tracking. 4096-quad batch limit. 1x1 white texture for solid shapes. Deferred bind group release for multi-texture correctness.
- **Texture loading** — unified `load_texture` handles encoded images (PNG/BMP/TGA via `core:image`) and raw RGBA8 pixel data. Sub-region updates via `update_texture`.
- **Text rendering** — fontstash integration with shared glyph atlas, auto-expanding atlas texture, dirty-region GPU updates (single-channel to RGBA expansion), default embedded font, measurement, outlined text.
- **Input system** — three-layer architecture: platform events → state processing → polled query API. Handles macOS trackpad DOWN+UP same-frame edge case with deferred UP. Keyboard (went down/up/held, repeat filtering), mouse (position, delta, buttons), cursor control (system shapes + custom RGBA cursors).
- **Audio** — full playback API with buses, spatial audio, listener position, pan/pitch/volume/looping. Desktop via miniaudio, web via Web Audio API.
- **Custom shaders** — WGSL parser extracts uniform metadata, automatic buffer layout, hot-swap between default and custom pipelines within a frame.
- **Drawing primitives** — rects, outlined rects, lines (arbitrary angle via perpendicular quad), textured quads, sub-region blitting with UV mapping.
- **Delta time** — `frame` callback receives `dt: f32`, `get_frame_time()` and `get_time()` available.
- **Stats overlay** — `draw_stats()` renders FPS, frame time, draw calls, quad count as a bar.
- **Cross-platform examples** — 9 examples from minimal to full game (lemmings), all build on desktop and web.
- **macOS autorelease** — Metal backend ObjC autorelease pool drained each frame to prevent memory growth.
- **Web build tool** — generates HTML from template, copies JS runtime, builds WASM, optional dev server.

## Resolved issues

| # | Issue | Resolution |
|---|-------|------------|
| 1 | `Engine`/`engine` visible to importers | Added `@(private = "package")` |
| 2 | Dead `update()` proc | Removed |
| 3 | `draw_texture` took `^Texture` | Now takes `Texture` by value; renderer tracks by handle |
| 4 | GLFW `c_title` memory leak | Stored in file-private global, freed in shutdown |
| 5 | No delta time | `frame` now receives `dt: f32`, timing tracked in engine |
| 6 | `RGBA8UnormSrgb` texture format | Switched to `RGBA8Unorm` for predictable results |
| 7 | Bind groups released mid-render-pass | Deferred release until after submit |
| 8 | Vertex buffer overwritten on flush | Track running offset, append rather than overwrite |
| 9 | Backend selection was runtime parameter | Now compile-time via build tags |
| 10 | Separate `load_texture` / `load_texture_from_bytes_raw` | Unified into single `load_texture` proc |
| 11 | Game had to import `config` package and pass backends | Removed `Config`; backends hardcoded per platform |
| 12 | `wrapper.odin` monolith | Split into `engine.odin`, `draw.odin`, `input.odin`, `text.odin`, `audio.odin`, `shader.odin`, `types.odin` |
| 13 | No input handling | Full keyboard + mouse + cursor API with three-layer architecture |
| 14 | No text rendering | fontstash integration with atlas, measurement, outlines |
| 15 | No audio | Full audio system with buses, spatial audio, two backends |
| 16 | No custom shaders | WGSL parser, uniform metadata, shader hot-swap |
| 17 | macOS SDL3 click delay (~500ms) | Native Cocoa window backend avoids SDL3 event latency |
| 18 | macOS Metal autorelease leak | Explicit autorelease pool drain each frame |

## Observations

### Strengths

- **Clean API surface.** The public API is small and consistent — `draw_*`, `load_*`, `*_went_down`/`*_is_held`. Easy to learn.
- **Good separation of concerns.** `core/` breaks circular imports cleanly. Each file has a single responsibility.
- **Backend abstraction.** `Window_Backend`, `Render_Backend`, `Audio_Backend` are structs of proc pointers (vtables). Swapping a backend means wiring different procs — no interface dispatch overhead.
- **Texture handle system.** `Texture_Handle :: distinct u64` keeps GPU resources internal to the renderer. The `Texture` struct exposed to users holds only handle + dimensions.
- **Input edge-case handling.** The macOS trackpad deferred-UP logic (`mouse_deferred_up`) is a real problem solved well — without it, clicks would be missed on trackpads.
- **Proper GPU resource cleanup.** Shutdown walks all textures, buffers, pipelines. Bind groups are deferred-released after submit rather than mid-pass.
- **Shader system is well-designed.** The WGSL parser automatically extracts uniform layout, so users just call `set_shader_uniform(shader, "time", value)` by name.
- **Batch efficiency.** Texture switches flush; within a texture, quads accumulate. Running vertex offset avoids re-uploading overlapping data.
- **No external dependencies.** Everything comes from Odin's vendor packages (`wgpu`, `sdl3`, `miniaudio`, `fontstash`).

### Items to consider

**`Shader` struct exposes wgpu internals.** The `Shader` type in `core/render.odin` contains `wgpu.ShaderModule`, `wgpu.RenderPipeline`, `wgpu.Buffer`, etc. This is the one type that leaks GPU backend details into the shared interface. Could be made opaque (handle-based like textures) but the complexity may not be warranted unless a non-wgpu renderer is planned.

**Panic on GPU resource failure.** `load_texture` panics if image decoding fails. The renderer panics if adapter/device requests fail. For a game library, returning errors or optionals would be friendlier — games could show fallback textures or gracefully degrade.

**Font atlas expansion allocates every dirty update.** In `text.odin:_update_font`, the RGBA expansion buffer (`make([]u8, dw * dh * 4)`) is allocated and freed every time the atlas has dirty glyphs. A persistent staging buffer (resized only when the atlas grows) would avoid per-frame allocations during text-heavy frames.

**Bind group creation per texture switch.** Each texture switch creates a new `BindGroup` (projection + sampler + texture). These are pooled per-frame and released after submit, but creating a bind group per switch could be cached by texture handle to avoid redundant GPU work if the same textures alternate.

**`MAX_BIND_GROUPS_PER_FRAME` is a hard limit (256).** If exceeded, it asserts. Games with many texture switches per frame could hit this. Could be made dynamic or at least warn before crashing.

**Color conversion happens per-vertex.** `f32(color[0]) / 255.0` is computed for every vertex of every quad. Since the same color applies to all 6 vertices of a quad, computing it once per quad would be cleaner (the compiler may already optimize this, but it's worth noting).

## Roadmap

### Window options

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

### Rendering optimizations

- **Texture atlas** — pack sprites into one texture to eliminate texture-switch flushes
- **Draw call sorting** — group by texture automatically (with layer/depth for ordering)
- **Index buffer** — switch from 6 vertices per quad to 4 vertices + 6 indices (33% less vertex data)
- **Persistent staging buffer** — reuse font atlas RGBA conversion buffer across frames

### CLI tool

Consolidate build tooling into a single command:

```
<project> build examples/texture
<project> web examples/texture
<project> serve examples/texture
```
