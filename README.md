# odin-wgpu

A 2D game development library for [Odin](https://odin-lang.org/) using WebGPU (wgpu-native). One codebase runs on desktop (macOS, Linux, Windows) and web (WASM).

## Quick start

```odin
package main

import w "../.."

main :: proc() {
    w.init(1280, 720, "My Game")
    w.run(init, frame, shutdown)
}

init :: proc() {
    // Load textures, fonts, audio here
}

frame :: proc(dt: f32) {
    w.clear(w.LIGHT_BLUE)
    w.draw_rect({50, 50, 200, 100}, w.RED)
    w.draw_text("Hello!", {60, 60}, 32)
    w.present()
}

shutdown :: proc() {}
```

## Build

```bash
odin run examples/hello                            # Desktop
odin run tools/build_web -- examples/hello         # Web (WASM)
odin run tools/build_web -- examples/hello --serve # Web + dev server
```

## Features

- **Drawing** — rectangles, lines, textures (PNG/BMP/TGA), sub-region blitting, tinting
- **Text** — TTF font loading via fontstash, measurement, outlined text, default embedded font
- **Input** — keyboard (went down/up/held), mouse (position, delta, buttons), system and custom cursors
- **Audio** — load/play/pause/stop, volume/pan/pitch, buses, spatial audio, looping
- **Shaders** — custom WGSL shaders with automatic uniform parsing and hot-swapping
- **Cross-platform** — desktop (SDL3/native Cocoa + wgpu) and web (JS canvas + wgpu + Web Audio)
- **Stats** — built-in FPS, frame time, draw calls, quad count overlay via `draw_stats()`

## API overview

### Lifecycle

```
init(width, height, title)
run(init_proc, frame_proc, shutdown_proc)
get_frame_time() -> f32
get_time() -> f64
get_screen_size() -> (int, int)
get_stats() -> Stats
```

### Drawing

```
clear(color)
present()
draw_rect(rect, color)
draw_rect_outline(rect, thickness, color)
draw_line(from, to, thickness, color)
draw_texture(texture, pos, tint?)
draw_texture_rect(texture, src, dst, tint?)
load_texture(bytes, width?, height?) -> Texture
update_texture(texture, data, x, y, w, h)
destroy_texture(&texture)
draw_stats()
```

### Text

```
load_font(ttf_bytes) -> Font
get_default_font() -> Font
draw_text(text, pos, size, color?)
draw_text_ex(font, text, pos, size, color?)
draw_text_outlined(text, pos, size, color, outline_color, outline_size)
measure_text(text, size) -> Vec2
```

### Input

```
key_went_down(key) -> bool
key_went_up(key) -> bool
key_is_held(key) -> bool
get_mouse_position() -> Vec2
get_mouse_delta() -> Vec2
mouse_button_went_down(button) -> bool
mouse_button_went_up(button) -> bool
mouse_button_is_held(button) -> bool
show_cursor() / hide_cursor()
set_cursor(system_cursor)
set_custom_cursor(pixels, width, height, hot_x, hot_y)
```

### Audio

```
init_audio() -> bool
shutdown_audio()
load_audio(path, type?) -> Audio_Source
load_audio_from_bytes(data, type?) -> Audio_Source
play_audio(source, params?) -> Audio_Instance
stop_audio(instance) / pause_audio(instance) / resume_audio(instance)
set_audio_volume/pan/pitch/looping/position(instance, value)
create_audio_bus(name) -> Audio_Bus
set_audio_bus_volume(bus, volume)
set_audio_listener_position(position)
```

### Shaders

```
load_shader(wgsl_source) -> Shader
set_shader_uniform(&shader, name, value)
set_shader(&shader) / reset_shader()
destroy_shader(&shader)
```

## Examples

| Example | What it shows |
|---------|--------------|
| `examples/hello` | Colored rectangles |
| `examples/texture` | PNG loading, raw pixel textures, sprite sheets |
| `examples/keyboard` | WASD movement, key states |
| `examples/mouse` | Cursor tracking, system/custom cursors, click detection |
| `examples/text` | Font loading, measurement, outlined text |
| `examples/audio` | Sound playback |
| `examples/shader` | Custom WGSL shader with uniforms |
| `examples/collisions` | Collision detection |
| `examples/lemmings` | Full game: sprites, animation, terrain, audio |

## Architecture

Backends are selected at compile time — your game code doesn't need to specify them:

- **macOS** — native Cocoa window + wgpu renderer + miniaudio
- **Desktop (other)** — SDL3 window + wgpu renderer + miniaudio
- **Web** — JS canvas + wgpu renderer + Web Audio

The library is structured as:

```
engine (public API)  ->  core/ (shared types & interfaces)
                     ->  backend/ (platform wiring)
                     ->  window/{sdl3,darwin,glfw,js}
                     ->  render/wgpu/
                     ->  audio/{miniaudio,webaudio}
```

## Known issues

### wgpu-native memory leak

Odin's vendor library ships wgpu-native v27.0.2.0 which has a [command encoder memory leak](https://github.com/gfx-rs/wgpu-native/issues/541) — internal cleanup is skipped every frame, causing steady memory growth (~3-4 MB/min).

This is fixed in v27.0.4.0. To upgrade:

1. Download the release for your platform from https://github.com/gfx-rs/wgpu-native/releases/tag/v27.0.4.0

2. Replace the library files in your Odin install:
   ```
   ~/.odin-install/<version>/vendor/wgpu/lib/wgpu-macos-aarch64-release/lib/libwgpu_native.a
   ~/.odin-install/<version>/vendor/wgpu/lib/wgpu-macos-aarch64-release/lib/libwgpu_native.dylib
   ```

3. Relax the version check in `~/.odin-install/<version>/vendor/wgpu/wgpu.odin` (around line 1699). Change:
   ```odin
   if v.xyz != BINDINGS_VERSION.xyz {
   ```
   to:
   ```odin
   if v.xy != BINDINGS_VERSION.xy {
   ```
   This allows the compatible patch release (27.0.4) to pass validation against the 27.0.2 bindings.
