# TODO

Prioritized from an API review (June 2026) comparing w2d against raylib, Love2D,
macroquad, and Usagi. Completed feature plans (camera, render textures, rotation
on draw calls, scissor rect) have been removed — see `API.md` for what shipped.

## Decisions

- **No public package split.** Usagi's `gfx.` / `input.` / `sfx.` namespaces are
  Lua tables — free to create. In Odin a public split costs import-cycle
  plumbing (shared engine `ctx` would move into `core/` and every subpackage
  imports it) and worse caller ergonomics (four import lines per game file vs
  `import w "w2d"`). The internal split (`core/`, `backend/`, `render/`,
  `audio/`, `window/`) already provides modularity where it pays off; the flat
  prefix-namespaced facade (`draw_*`, `key_*`, `set_audio_*`) is the Odin idiom
  (raylib bindings, karl2d, sokol-odin) and stays.
- **No engine-level "juice" features.** Usagi's effects module (hitstop, screen
  shake, flash, slow-mo), palettes, sprite-sheet conventions, and pause menu are
  framework opinions, not library features. A "juice" example showing screen
  shake via camera offset would cover the need.

## High priority — blocks whole categories of games

### 1. Gamepad input — SHIPPED (desktop + web)

Public API (`input.odin`): `is_gamepad_connected`, `get_gamepad_name`,
`gamepad_button_went_down / went_up / is_held`, `get_gamepad_axis`,
`set_gamepad_vibration` — up to `MAX_GAMEPADS` (4), poll+diff model mirroring
keyboard/mouse. Types in `core/gamepad.odin`; `examples/gamepad` demos sticks,
face buttons, triggers, D-pad, hot-plug, and rumble.

Gamepad is its **own backend** (`core.Gamepad_Backend`), decoupled from
`Window_Backend`, because SDL3's gamepad subsystem runs independently of
windowing. One SDL3 implementation (`gamepad/sdl3/`) covers **all desktop
platforms including macOS** — macOS now links SDL3 for gamepad input while
keeping the native Cocoa window. This brings hot-plug, the SDL_GameControllerDB
mapping database, and rumble for free; no per-OS (evdev/XInput) or native
GameController-framework code was needed.

Web is backed by the browser Gamepad API: `gamepad/js/gamepad_js.js` packs a
snapshot into the wasm heap (`window.gamepadJsImports`, wired in
`tools/build_web/index_template.html` like the audio shim) and
`gamepad/js/gamepad_js.odin` unpacks it. Standard-mapping remap; rumble via
`vibrationActuator`. Browser caveats: a controller is only visible after the user
presses a button on it, and non-standard-mapping pads may mislabel buttons.

**Remaining:**

- **Action-mapping layer (follow-up):** an optional layer where one named action
  unions keyboard + gamepad buttons + analog stick behind a single
  `input.pressed(action)` (Usagi's nicest input idea). Raw API shipped first; the
  action layer can be a separate file or an example.

### 2. Text input events + clipboard

There is currently no way to receive typed characters. Reconstructing text from
`key_went_down` breaks on shift, layouts, and IME. Needed for name entry, chat,
dev consoles.

- Rune stream à la raylib `GetCharPressed()` / Love2D `love.textinput`:
  - `get_char_pressed :: proc() -> rune` (0 when queue empty), or a
    `get_typed_text :: proc() -> string` per-frame buffer.
  - Backends: SDL3 `SDL_EVENT_TEXT_INPUT` (+ `SDL_StartTextInput`), Cocoa
    `insertText:`, web `keypress`/`beforeinput` on the canvas.
- Clipboard: `get_clipboard_text() -> string`, `set_clipboard_text(text)`.
  SDL3 has it natively; web is async (`navigator.clipboard`) so the getter may
  need to be best-effort/cached.

### 3. Programmatic quit / close handling

Needed on desktop (a game can't currently exit itself or confirm-on-close) and
for web embedding (see web notes below — hosts that unmount the canvas leak a
running rAF loop).

- Module-level `quit_requested: bool` in engine state.
- Public `quit :: proc()` that sets the flag; the main loop runs
  `shutdown_proc`, then `engine_shutdown`, then exits cleanly.
- In `platform_js.odin`'s `step`: if `ctx.quit_requested`, run shutdown once
  and return `false` so `odin.js` cancels the rAF.
- Export `@(export) request_quit :: proc "c" ()` so a JS host can stop the
  engine from a hook's `destroyed()` — `@(fini)` only fires when the wasm
  module is torn down, which never happens when a host merely unmounts the
  canvas.
- Optional: a `set_close_callback` so games can intercept the window close
  button (unsaved-progress prompts).

### 4. Window control

`Window_Backend` only takes the title at init and exposes `set_window_mode`.
Add:

- `set_window_title :: proc(title: string)`
- `set_window_size :: proc(width, height: int)`
- vsync toggle + target FPS / frame cap (raylib `SetTargetFPS`); at minimum
  document the current vsync behavior
- focus / minimized queries (auto-pause), and possibly a focus-change callback
- window icon (lower priority; desktop only)
- **Live-resize rendering on macOS**: dragging a window edge enters AppKit's
  modal resize tracking loop, so `nextEventMatchingMask` in
  `window/darwin/darwin.odin` blocks the frame loop and the compositor
  stretches the last presented drawable (content squashes until release).
  Fix: render a frame from inside `windowDidResize` (the delegate fires
  throughout the drag; engine needs a "pump one frame" hook), or drive frames
  from a timer scheduled in `NSEventTrackingRunLoopMode`. For gap-free polish,
  set `CAMetalLayer.presentsWithTransaction = true` during live resize. The
  SDL3 backend has the same issue with its own fix (event watch callbacks).

### 5. Blend modes

In wgpu, blend state is baked into the pipeline, so each mode is a pre-built
pipeline; flush the batch and switch on change.

Modes — **Additive is the one games actually reach for** (particles, glow), so
it goes in the first cut:

```
Blend_Mode :: enum {
    Alpha,               // standard: src*alpha + dst*(1-alpha)
    Additive,            // src*alpha + dst
    Multiply,            // src*dst
    Premultiplied_Alpha, // src + dst*(1-alpha)
}
```

1. **`core/render.odin`** — `set_blend_mode: proc(mode: Blend_Mode)`.
2. **`render/wgpu/wgpu.odin`** — create one pipeline per mode at init; track
   `active_blend_mode` in `Batch_State`; `renderer_flush` selects the pipeline
   when no custom shader is active. Custom shader pipelines: pass the blend
   mode into `create_render_pipeline` (start with default-pipeline-only if
   per-shader variants are overkill).
3. **Public API** — `set_blend_mode(mode)` / `reset_blend_mode()`, flush +
   delegate.
4. Track current mode in engine context so it survives render-target switches.

### 6. Texture filter / wrap options

The sampler is hardcoded `Nearest` + `ClampToEdge` (`render/wgpu/wgpu.odin`,
sampler creation) — a pixel-art-only assumption. Linear filtering for
smooth-scaled art and `Repeat` for tiling/scrolling backgrounds are table
stakes (raylib `SetTextureFilter`/`SetTextureWrap`, Love2D
`setFilter`/`setWrap`).

- Create a small set of shared samplers at init (nearest/linear ×
  clamp/repeat) and select per-texture.
- `set_texture_filter(tex, filter)` / `set_texture_wrap(tex, wrap)` or params
  on `load_texture`.
- Repeat wrap requires UVs > 1 in `draw_texture_rect` — already supported by
  the UV math, just needs the sampler.

## Medium priority — common conveniences

### Sprite flipping

The UV math in `draw_texture_rect` / `draw_texture_ex` happens to support
raylib's negative-`src.w`/`src.h` flip trick, but it's undocumented and
untested. Either document + test that, or add explicit `flip_x` / `flip_y`
params — flipping is used constantly for facing direction.

### Text layout

`measure_text` alone makes every centered label three lines of caller code.

- Alignment (left/center/right) on a `draw_text_aligned` or param.
- Wrapped/bounded text (`draw_text_boxed(text, rect, ...)`).
- Expose font metrics: line height, ascent/descent (fontstash has these).

### More shapes + public vertex API

- Rounded rect (UI panels), ellipse, polygon, ring/arc.
- Expose a public triangle/vertex submission proc (thin wrapper over the
  internal `push_quad_ex` / a `push_triangle`) so users can build anything
  else themselves cheaply.

### Geometry / collision helpers

The collisions example hand-rolls `aabb_intersects_aabb` and `get_overlap` —
a sign they belong in the library (raylib `CheckCollisionRecs`, Usagi
`util.rect_overlap`). Small and high-leverage:

- `point_in_rect`, `point_in_circle`
- `rect_overlap(a, b) -> bool`, `rect_intersection(a, b) -> Rect`
- `circles_overlap`, `circle_rect_overlap`

### Touch input

We ship a web target; mouse events alone won't cut it on mobile browsers.
Touch events on the canvas mapped to a small API (`get_touch_count`,
`get_touch_position(index)`), with single-touch optionally aliased to mouse.

### Screenshot / pixel readback

- `get_render_texture_pixels(rt) -> []u8` and/or `take_screenshot()`.
- Also enables golden-image testing of the library itself.
- wgpu: copy texture to a mapped buffer; async on web — API may need a
  callback or be desktop-only initially.

## Worth considering — plays to the cross-platform pitch

### Save-data helper

On web there's no filesystem, only localStorage — painful for users to
abstract themselves. A minimal `save_data(key: string, bytes: []u8)` /
`load_data(key: string) -> []u8` mapping to the OS app-data dir on desktop and
localStorage on web fits "one codebase runs everywhere" perfectly.

### Color utilities

`fade(color, alpha)`, hex constructor, `color_from_hsv`. Tiny, but raylib
users will miss `Fade()` immediately.

### Audio link weight

`backend/backend_desktop.odin` imports miniaudio unconditionally, so every
game links the audio stack even if it never calls `init_audio`. Fix with a
build define (`#config(W2D_NO_AUDIO, false)` gating the backend import), not a
package split.

## Dev tooling: `w2d` CLI

Usagi-inspired (`init` / `dev` / `export`), adapted for a compiled language.
Designed June 2026. Lives in `tools/` like `build_web`; same `odin run`
pattern, or shipped as a built binary.

Decision: **no DLL-based hot reload for now.** State-preserving code reload
(Zylinski's odin-raylib-hot-reload approach) requires the engine `ctx` to live
in a host process with the game behind a proc table — a second consumption
mode worth revisiting later, but watch-rebuild-restart + in-process asset hot
reload gets most of the value at a fraction of the complexity.

### Asset registry (the enabling piece)

A two-mode virtual file system inside the engine, so the same game code gets
embedded assets in release and hot-reloadable disk assets in dev. Preserves
the current `#load`-style property: **one self-contained binary on desktop and
web, no packing step** — `build_web` needs no changes (it packs nothing today;
web builds work because `#load` embeds at compile time).

- New path-based loaders resolve through the registry:
  `load_texture_from_file`, `load_shader_from_file`, `load_font_from_file`
  (`load_audio(path)` already exists — route it through the same registry).
- **Release (default)**: the game registers embedded assets once. `w2d init`
  generates an `assets.odin` along the lines of:

  ```odin
  when !w.DEV {
      @(private) _assets := #load_directory("assets")
      @(init) _register :: proc() { w.register_assets("assets", _assets) }
  }
  ```

  `load_*_from_file("assets/player.png")` looks up the registry — bytes live
  in the binary's data section, zero runtime cost until decode. Works
  identically on wasm.
- **Dev** (`-define:W2D_DEV=true`, exposed as `w.DEV` via
  `#config(W2D_DEV, false)`): the embed block compiles out; loaders read from
  disk relative to the project root and record `path + mtime` next to the
  handle. Dev rebuilds don't re-embed assets, so rebuild time stays flat as
  the asset folder grows.
- `#load_directory` facts (verified on dev-2026-06): returns
  `[]Load_Directory_File{name, data}`, must be bound to a variable (not a
  constant), names come back **bare** (no directory prefix — hence the prefix
  arg on `register_assets`), and it is **non-recursive**. So either keep
  `assets/` flat, or the scaffold emits one `#load_directory` +
  `register_assets` line per subdirectory (`assets/sfx`, `assets/music`, …).

### Asset hot reload (engine-side, no IPC)

Gated behind `when W2D_DEV` — compiles out of release builds entirely.

- Every ~20 frames, stat registered asset paths; on mtime change, re-read and
  update **in place** behind the existing handle: re-decode + `update_texture`
  for images, recompile WGSL and swap the pipeline, re-bake the font atlas,
  re-load audio source. Game code holds handles; handles don't change; no
  game-side code at all.
- Wrinkle: `Texture` copies `width`/`height` by value into game state, so a
  reload that changes dimensions leaves stale copies. Either route size
  queries through the handle (`get_texture_size`) or document "keep
  hot-reloaded assets the same size". Decide before the loaders ship.
- Desktop only — wasm has no disk. Web dev loop is rebuild + browser refresh.

### `w2d dev` (watch-rebuild-restart)

With assets handled in-process, the tool only handles the code loop:

1. `odin build . -define:W2D_DEV=true -debug -o:none -out:.w2d/game`
2. Run the child; inherit stdout/stderr so `fmt.println` debugging works.
3. Watch `*.odin` via mtime polling (~200 ms; no fs-watcher in core, and
   polling tens of files is invisible — FSEvents/inotify is a later
   optimization).
4. On change: rebuild. **If the compile fails, keep the old binary running
   and print the errors** — the game never dies because you saved mid-edit.
5. On success: SIGTERM the child (graceful, so `shutdown` runs), start the
   new one. If the child crashes, wait for the next save instead of respawn
   looping.

State across restarts: **v1 is restart-only, no preservation** (decided).
Odin restarts in ~1 s for small games and asset handles aren't stable across
processes anyway. Optional save/restore hooks (engine calls them on
SIGTERM/boot in dev mode; user serializes a plain-data state struct) are a
possible v2 — requires the convention that asset handles are acquired in
`init`, never persisted.

Web variant: wrap `build_web --serve` + rebuild-on-save + browser
auto-refresh (served page polls a `/build-id` endpoint).

### `w2d init`

Scaffold a project; the template is how the conventions ship — users never
read a conventions doc:

- `main.odin` with `init`/`frame`/`shutdown` stubs and asset loading by path
- generated `assets.odin` (embed registration, above) + `assets/` directory
- `justfile`, `ols.json`, `.gitignore`
- w2d dependency wired up (vendor/pin via the existing `.deps/` convention)

Only two conventions, neither enforced (break them and you just lose the dev
niceties): assets live under `assets/` and are loaded by path; game state is
one plain-data struct with handles acquired in `init`.

### `w2d export` (later)

- v1: host platform + web (web is mostly `build_web` already; single binary
  falls out of the asset registry).
- Full cross-platform matrix is real cross-compilation (native deps — SDL3,
  wgpu-native, miniaudio — need per-target prebuilt libs). Usagi avoids this
  only because its games are Lua data appended to prebuilt binaries.
  Usagi-template-style prebuilt dep archives per target, fetched on first
  use, if demand appears.

### Build order

Each step independently useful: path loaders + asset registry → `when
W2D_DEV` asset watcher → `dev` supervisor → `init` scaffold → export.

## API consistency

- `load_audio(path)` loads from a file path but `load_texture(bytes)` only
  takes bytes — superseded by the asset-registry design above: path-based
  `load_*_from_file` procs become the primary API for all asset types,
  resolving through the registry (embedded in release, disk in dev). The
  bytes-based loaders stay for raw/generated data.
- `load_texture(bytes, width=0, height=0)` doing double duty for encoded
  images *and* raw pixels is magic; split out `load_texture_from_pixels`.
- `set_camera(Maybe(Camera))` takes nil to reset, but render textures and
  shaders use paired `set_` / `reset_` procs — three features, two
  conventions. Pick one.

## Web / embedding notes

### Canvas size queries (partially done)

`js_get_framebuffer_size` and `js_get_window_size` now read from
`id="wgpu-canvas"` instead of `body`, so the library is agnostic to the
surrounding page structure.

- **Document the embedder caveat in the README**: when the canvas is sized
  purely via its `width`/`height` attributes (no CSS), `wgpuSurfaceConfigure`
  writes back `canvas.width/height`, which also grows the displayed CSS size —
  a feedback loop where each frame configures the surface bigger than the
  last. Embedders should pin the canvas's display size with CSS (e.g.
  `style="width: 640px; height: 400px"`); the bundled template already does
  this implicitly via `width: 100%; height: 100%` against a fixed-size body.
- **`ResizeObserver` instead of window resize**: `js_size_callback` is wired
  to `window.resize`, which misses anything that resizes the canvas without
  resizing the window (parent layout change, sidebar toggle, devtools
  docking). A `ResizeObserver` on `#wgpu-canvas` is the correct trigger —
  small change in the JS shim plus a new entry point in `js.odin`.
- **Configurable selector**: hardcoding `#wgpu-canvas` blocks two w2d
  instances on one page (or just a different id). Pass the selector through
  `core.Window_Backend.init` and store it in module state. Not needed yet.
- **Offset coords for embedded canvases**: viewport coords break hit-testing
  when the canvas isn't at viewport origin.
- **Event listener hygiene**: `js_init` adds window event listeners without
  storing identities; verify `js_shutdown` unhooks cleanly across multiple
  init/shutdown cycles so embedders that mount/unmount/re-mount don't
  accumulate listeners.

## Suggested order

1. **Gamepad** (#1) — biggest gap, already designed
2. **Text input + clipboard** (#2) — unblocks text fields everywhere
3. **Blend modes** (#5) — small backend change, unlocks particles/glow
4. **Quit / close handling** (#3) — small, fixes web embedding leak too
5. **Texture filter/wrap** (#6) — small backend change
6. **Window control** (#4) — incremental backend additions
7. **Dev tooling** — path loaders + asset registry first (also resolves the
   bytes-vs-path API inconsistency), then asset hot reload, then `w2d dev` /
   `w2d init`
8. Medium-priority conveniences as they itch
