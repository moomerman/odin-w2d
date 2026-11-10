# API Reference

## Types

```odin
Vec2 :: [2]f32
Color :: [4]u8
Font :: distinct int

Rect :: struct {
    x, y, w, h: f32,
}

Texture :: struct {
    handle: Texture_Handle,
    width:  int,
    height: int,
}

Shader :: struct {
    handle: Shader_Handle,
}

Render_Texture :: struct {
    texture: Texture,
}

// src is the drawn colour already multiplied by its alpha a (see Colour and Alpha).
Blend_Mode :: enum {
    Alpha,    // default: src + dst*(1-a)
    Additive, // src + dst, coverage unchanged — lights, particles, glow
    Multiply, // src*dst + dst*(1-a) — shadows, light-map compositing
}

Camera :: struct {
    target:   Vec2,   // world point the camera looks at
    offset:   Vec2,   // screen offset (set to screen_center to center the target)
    rotation: f32,    // radians
    zoom:     f32,    // 1.0 = normal, >1 = zoomed in
}

Stats :: struct {
    frame_time_ms:    f32,
    fps:              f32,
    draw_calls:       int,
    quads:            int,
    vertices:         int,
    texture_switches: int,
    textures_alive:   int,
    texture_memory:   int,
}

Window_Mode :: enum {
    Windowed,
    Windowed_Fixed,
    Fullscreen,
    Borderless,
}

Mouse_Button :: enum {
    Left,
    Right,
    Middle,
}

Key :: enum u16 {
    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
    Key_1, Key_2, Key_3, Key_4, Key_5, Key_6, Key_7, Key_8, Key_9, Key_0,
    Return, Escape, Backspace, Tab, Space,
    Minus, Equals, Left_Bracket, Right_Bracket, Backslash, Semicolon, Apostrophe,
    Grave, Comma, Period, Slash,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
    Insert, Home, Page_Up, Delete, End, Page_Down,
    Right, Left, Down, Up,
    Left_Ctrl, Left_Shift, Left_Alt, Left_Super,
    Right_Ctrl, Right_Shift, Right_Alt, Right_Super,
}

Gamepad_Index :: int // 0..MAX_GAMEPADS-1

Gamepad_Button :: enum {
    South, East, West, North, // face buttons (Xbox A/B/X/Y, PS Cross/Circle/Square/Triangle)
    Left_Shoulder, Right_Shoulder,
    Left_Trigger, Right_Trigger, // threshold-based digital view of the trigger axes
    Left_Stick, Right_Stick, // stick clicks (L3/R3)
    Dpad_Up, Dpad_Down, Dpad_Left, Dpad_Right,
    Start, Select, Guide,
}

Gamepad_Axis :: enum {
    Left_X, Left_Y, Right_X, Right_Y, // sticks, -1..1
    Left_Trigger, Right_Trigger, // 0..1
}

System_Cursor :: enum {
    Default, Text, Crosshair, Pointer,
    Resize_EW, Resize_NS, Resize_NWSE, Resize_NESW,
    Move, Not_Allowed,
}

Audio_Source :: distinct u64
Audio_Instance :: distinct u64
Audio_Bus :: distinct u64

Audio_Source_Type :: enum {
    Static,
    Stream,
}

Audio_End_Callback :: proc(instance: Audio_Instance, user_data: rawptr)

Audio_Spatial_Params :: struct {
    position:     Vec2,
    min_distance: f32,
    max_distance: f32,
}

Audio_Play_Params :: struct {
    bus:       Audio_Bus,
    volume:    f32,
    pan:       f32,
    pitch:     f32,
    loop:      bool,
    delay:     f32,
    spatial:   Maybe(Audio_Spatial_Params),
    on_end:    Audio_End_Callback,
    user_data: rawptr,
}
```

## Constants

```odin
// Input
MAX_GAMEPADS :: 4

// Sentinel handles
AUDIO_SOURCE_NONE :: Audio_Source(0)
AUDIO_INSTANCE_NONE :: Audio_Instance(0)
AUDIO_BUS_NONE :: Audio_Bus(0)
DEFAULT_AUDIO_SPATIAL_PARAMS :: Audio_Spatial_Params{ position = {0, 0}, min_distance = 100, max_distance = 1000 }

// Colors
BLACK, WHITE, BLANK, GRAY, DARK_GRAY, LIGHT_GRAY,
RED, DARK_RED, GREEN, DARK_GREEN, BLUE, DARK_BLUE, LIGHT_BLUE,
ORANGE, YELLOW, PURPLE, MAGENTA, BROWN :: Color
```

## Engine

```odin
init :: proc(width: int, height: int, title: string)
run :: proc(init_proc: proc(), frame_proc: proc(dt: f32), shutdown_proc: proc())
get_frame_time :: proc() -> f32
get_time :: proc() -> f64
get_frame_count :: proc() -> int // frame being run: 0 in the first frame proc call; the N of script `frame N`
get_screen_size :: proc() -> (int, int)
set_window_mode :: proc(mode: Window_Mode)
set_vsync :: proc(enabled: bool) // default on; off = loop runs unthrottled, window updated ~60/s
get_stats :: proc() -> Stats
get_gpu_device :: proc() -> rawptr
get_gpu_queue :: proc() -> rawptr
get_surface_format :: proc() -> u32
set_pre_present_callback :: proc(callback: proc(pass: rawptr, width, height: u32))
```

### Headless

`init_headless` replaces `init` for tests and CI: no window is created and
every frame is drawn into an offscreen target, so `read_pixels`,
`save_screenshot` and render textures work as usual. Frames run as fast as
they draw, and each reports exactly `frame_time` as its dt (the first frame
reports 0), so runs are deterministic. `scale` simulates a HiDPI backing
scale: the framebuffer is `width*scale` by `height*scale` pixels. There is
no close button, so end the run with `quit()`; input comes from the
`inject_*` procs (see Input - Injection). Desktop only. `tests/render` is a
worked example; run it with `just test`.

```odin
init_headless :: proc(width: int, height: int, scale: f32 = 1, frame_time: f32 = 1.0 / 60.0)
set_headless_size :: proc(width: int, height: int) // resize; call between frames
quit :: proc() // stop the run loop after this frame (any backend); shutdown_proc then runs
```

## Automation

Run any game unattended, from outside, with no code changes: `init` reads
these environment variables (desktop only). Any of them fixes dt at 1/60 s
so runs repeat frame for frame.

```
W2D_HEADLESS=1 W2D_FRAMES=60 W2D_SCREENSHOT=out.png ./mygame
W2D_HEADLESS=1 W2D_SCRIPT=smoke.txt ./mygame
```

| Variable | Effect |
| --- | --- |
| `W2D_HEADLESS=1` | No window, as `init_headless`; audio is muted |
| `W2D_SCALE=2` | Headless only: simulated HiDPI scale |
| `W2D_SCRIPT=path` | Play a script (works windowed too) |
| `W2D_FRAMES=n` | Quit after `n` frames |
| `W2D_SCREENSHOT=path` | With `W2D_FRAMES`: save the last frame |

A script has one command per line; `#` starts a comment; frames count from
0, and are the numbers `get_frame_count` returns. Input is applied before that frame's frame proc runs, a screenshot is
that frame as drawn (taken at `present`), and `quit` stops before that
frame. A headless script with no `quit` ends after its last command.

```
frame 30  screenshot start.png
frame 31  key Space down        # Key enum names, any case; down | up | tap
frame 33  key Space up
frame 50  mouse move 320 200    # window coordinates
frame 51  mouse click left      # down | up | click, left | right | middle
frame 60  scroll 0 -3
frame 70  resize 800 600        # headless only
frame 120 quit
```

The process exits with status 2 for a script that cannot be parsed and 1 if
a screenshot could not be saved or was never reached. `just example=<name>
shot` does the one-screenshot form for an example.

## Assets

```odin
// True when built with -define:W2D_DEV=true. Dev builds resolve asset paths
// from disk first (relative to the working directory) and hot-reload watched
// files on change (desktop only). Release builds resolve from the registry
// first, falling back to disk for unregistered paths (desktop only).
DEV :: #config(W2D_DEV, false)

// Register compile-time embedded assets, e.g.
//   w.register_assets("assets", #load_directory("assets"))
// #load_directory is non-recursive: register each subdirectory separately.
register_assets :: proc(prefix: string, files: []runtime.Load_Directory_File)

// Path-based loaders. Resolve from the registry or disk (see DEV above; on
// web, registry only). In dev builds, textures and shaders hot-reload in
// place when the file
// changes; a failed shader compile keeps the previous program. Audio loaded
// via load_audio(path) hot-reloads too (playing instances are stopped).
// Fonts are not hot-reloaded.
load_texture_from_file :: proc(path: string) -> Texture
load_shader_from_file :: proc(path: string) -> Shader
load_fragment_shader_from_file :: proc(path: string) -> Shader // see Shaders
load_font_from_file :: proc(path: string) -> Font

// Raw bytes for data the engine has no loader for (levels, config). The
// result is always a copy owned by the caller. In dev builds on desktop,
// `on_change` is called with the new contents whenever the file changes;
// `data` is only valid during the call.
Asset_Change_Proc :: #type proc(path: string, data: []u8)
load_data_from_file :: proc(path: string, on_change: Asset_Change_Proc = nil) -> (data: []u8, ok: bool)
```

## Drawing

```odin
clear :: proc(color: Color)
present :: proc()
draw_rect :: proc(r: Rect, color: Color)
draw_rect_outline :: proc(r: Rect, thickness: f32, color: Color)
draw_rect_ex :: proc(r: Rect, origin: Vec2, rotation: f32, color: Color)
draw_line :: proc(from: Vec2, to: Vec2, thickness: f32, color: Color)
draw_circle :: proc(center: Vec2, radius: f32, color: Color, segments: int = 16)
draw_circle_outline :: proc(center: Vec2, radius: f32, thickness: f32, color: Color, segments: int = 16)
draw_triangle :: proc(vertices: [3]Vec2, color: Color)
// Per-vertex colours (top-left, top-right, bottom-right, bottom-left).
draw_quad :: proc(positions: [4]Vec2, colors: [4]Color)
draw_rect_gradient :: proc(r: Rect, top_left, top_right, bottom_right, bottom_left: Color)
draw_rect_gradient_v :: proc(r: Rect, top, bottom: Color)
draw_rect_gradient_h :: proc(r: Rect, left, right: Color)
draw_texture :: proc(tex: Texture, pos: Vec2, tint: Color = WHITE)
draw_texture_rect :: proc(tex: Texture, src: Rect, dst: Rect, tint: Color = WHITE)
draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rotation: f32, tint: Color = WHITE)
draw_stats :: proc()
```

## Shapes

Vector shapes built from the quad batcher. They respect the transform
stack and the camera like every other draw call.

```odin
draw_rounded_rect :: proc(r: Rect, radius: f32, color: Color)
draw_rounded_rect_outline :: proc(r: Rect, radius: f32, thickness: f32, color: Color)
draw_ellipse :: proc(center: Vec2, rx, ry: f32, color: Color, segments: int = 24)
draw_ellipse_outline :: proc(center: Vec2, rx, ry: f32, thickness: f32, color: Color, segments: int = 32)
draw_polygon :: proc(points: []Vec2, color: Color)  // convex, fan from points[0]
draw_polyline :: proc(points: []Vec2, thickness: f32, color: Color, closed: bool = false)  // round joins and caps
draw_bezier :: proc(p0, p1, p2, p3: Vec2, thickness: f32, color: Color, segments: int = 24)  // cubic
bezier_point :: proc(p0, p1, p2, p3: Vec2, t: f32) -> Vec2
draw_arc :: proc(center: Vec2, radius: f32, start_angle, end_angle: f32, thickness: f32, color: Color, segments: int = 16)
// Radial gradient from per-vertex colour: glows and round shadows with no texture.
draw_circle_gradient :: proc(center: Vec2, radius: f32, center_color, edge_color: Color, segments: int = 32)
```

## Transforms

A CPU-side affine transform stack applied to every vertex the engine emits
(rects, shapes, textures and text). It composes with the camera (transform
first, then camera), costs no flush and no projection slot, and is reset by
`clear()` each frame. Use it for per-object placement; keep `set_camera` for
the view.

```odin
Transform :: struct { a, b, c, d, tx, ty: f32 }  // x' = a·x + c·y + tx, y' = b·x + d·y + ty
IDENTITY_TRANSFORM :: Transform{1, 0, 0, 1, 0, 0}

// Local `origin` lands on `translate`, rotated and scaled about it (draw_rect_ex's convention).
push_transform :: proc(translate: Vec2, rotation: f32 = 0, scale: Vec2 = {1, 1}, origin: Vec2 = {0, 0})
push_transform_ex :: proc(t: Transform)   // composed with the current transform
pop_transform :: proc()
get_transform :: proc() -> Transform       // the combined current transform
transform_apply :: proc(p: Vec2) -> Vec2   // local → screen (pre-camera)

transform_make :: proc(translate: Vec2, rotation: f32 = 0, scale: Vec2 = {1, 1}, origin: Vec2 = {0, 0}) -> Transform
transform_mul :: proc(outer, inner: Transform) -> Transform  // inner first, then outer
transform_point :: proc(t: Transform, p: Vec2) -> Vec2
transform_inverse :: proc(t: Transform) -> Transform        // e.g. mouse → local space
```

## Colour and Alpha

Everything you pass in or read back uses ordinary straight alpha: `Color`
values, tints, texture pixels, image files, clear colours and
`read_render_texture` results. Internally the renderer works in
premultiplied alpha (RGB already scaled by A), which the engine converts to
at the boundary. The practical effects:

- A render texture holding translucent content composites exactly as if the
  content had been drawn directly; just draw it with the default blend mode.
- Gradients and tints that fade to transparent keep their hue.
- `.Additive` adds light without adding coverage, so a glow drawn into a
  transparent render texture still adds when that texture is drawn.
- Custom shaders see premultiplied colour and must return it (see Shaders).

## Textures

Pixels are straight-alpha RGBA8, for both encoded images and raw data.

```odin
load_texture :: proc(bytes: []u8, width: int = 0, height: int = 0) -> Texture
update_texture :: proc(tex: Texture, data: []u8, x, y, width, height: int)
destroy_texture :: proc(tex: ^Texture)
```

### Filtering and wrapping

Each texture, render textures included (pass `rt.texture`), has its own
filter and wrap mode. Every texture starts `.Nearest` / `.Clamp`: crisp
pixels, edge texels stretched outwards. The setting applies to draws issued
after the change, including later in the same frame; draws already issued
keep the previous one. It is stored with the handle, so it survives a hot
reload. Custom shaders get it too: they sample through the group 0
`tex_sampler`, which is the drawn texture's sampler. (Group 1 textures bound
with `set_shader_texture` have no sampler of their own; read them with
`textureLoad`, or with `tex_sampler`, which carries the drawn texture's
setting.) The font atlas stays `.Nearest` / `.Clamp`, since glyphs are
rasterised at the size they are drawn.

```odin
Texture_Filter :: enum u8 {
    Nearest, // default: crisp pixels
    Linear,  // bilinear: smooth scaling, e.g. a low-res render texture under a CRT shader
}
Texture_Wrap :: enum u8 {
    Clamp,  // default: the edge texel repeats outwards
    Repeat, // tiles: a src rect larger than the texture draws several copies
    Mirror, // tiles, every other copy flipped
}
set_texture_filter :: proc(tex: Texture, filter: Texture_Filter)
set_texture_wrap :: proc(tex: Texture, wrap: Texture_Wrap)
get_texture_filter :: proc(tex: Texture) -> Texture_Filter
get_texture_wrap :: proc(tex: Texture) -> Texture_Wrap
```

A scrolling backdrop is a repeating texture drawn with a moving, oversized
source rect:

```odin
w.set_texture_wrap(clouds, .Repeat)
w.draw_texture_rect(clouds, {scroll, 0, screen_w, f32(clouds.height)}, {0, 0, screen_w, f32(clouds.height)})
```

## Render Textures

The active camera applies inside a render texture too, with the texture's
size as the viewport, so a world can be baked with the same camera it is
later drawn with. `set_camera(nil)` first for plain pixel coordinates.

```odin
create_render_texture :: proc(width: int, height: int) -> Render_Texture
set_render_texture :: proc(rt: Render_Texture, clear_color: Maybe(Color) = nil)
reset_render_texture :: proc()
destroy_render_texture :: proc(rt: ^Render_Texture)
```

## Readback

Copy pixels back from the GPU for screenshots and visual tests. Results are
tightly packed RGBA8 (any BGRA surface is swizzled; the screen's alpha is
255), row 0 at the top. Each call stalls until the GPU has finished the
work so far, so use it for debugging and tests, not every frame. Desktop
only: on web every call returns `ok = false` / `false`.

`read_pixels` reads the screen as drawn so far this frame, at the
framebuffer size in physical pixels (not `get_screen_size` on HiDPI). Call
it inside the frame proc, after drawing and before `present`; drawing may
continue afterwards. Drawing from `set_pre_present_callback` is not
included. When the window is hidden, covered, or (macOS) not yet shown the
surface has no texture, so the frame is drawn into an offscreen target of
the same size and nothing is presented; `read_pixels` reads that target,
so screenshots work from the first frame and with the window covered (the
loop is held to about 60 frames a second meanwhile). With `set_vsync(false)`
most frames are offscreen too, and read back the same way. `read_pixels`
returns `ok = false` only when the frame was skipped for a lost or resized
surface, so retry next frame. `read_render_texture` works inside a frame
or between frames, and returns straight alpha.

```odin
read_pixels :: proc(allocator := context.allocator) -> (pixels: []u8, width, height: int, ok: bool)
read_render_texture :: proc(rt: Render_Texture, allocator := context.allocator) -> (pixels: []u8, width, height: int, ok: bool)
save_screenshot :: proc(path: string) -> bool // read_pixels + PNG
```

## Text

```odin
load_font :: proc(data: []u8) -> Font
get_default_font :: proc() -> Font
draw_text :: proc(text: string, pos: Vec2, size: f32, color: Color = WHITE)
draw_text_ex :: proc(font: Font, text: string, pos: Vec2, size: f32, color: Color = WHITE)
draw_text_outlined :: proc(text: string, pos: Vec2, size: f32, color: Color = WHITE, outline_color: Color = BLACK, outline_size: f32 = 1)
draw_text_outlined_ex :: proc(font: Font, text: string, pos: Vec2, size: f32, color: Color = WHITE, outline_color: Color = BLACK, outline_size: f32 = 1)
measure_text :: proc(text: string, size: f32) -> Vec2
measure_text_ex :: proc(font: Font, text: string, size: f32) -> Vec2
// draw_text places the TOP of the line box at pos.y; for a baseline at y
// use pos.y = y - ascent. descent is negative.
get_font_metrics :: proc(font: Font, size: f32) -> (ascent, descent, line_height: f32)
```

Variable fonts (e.g. `Oxanium[wght].ttf`) render at their default instance;
there is no weight selection. Ship static instances for other weights.

## Shaders

Custom shaders are WGSL, in one of two forms.

**Fragment-only** (`load_fragment_shader`), the usual one: write the
fragment stage and your own group 1 bindings, and the engine appends its
prelude, `render/wgpu/prelude.wgsl`, which the default shader is built from
too. The prelude declares, and so reserves, these names:

| Name | What it is |
| --- | --- |
| `VertexInput` | vertex attributes: `position`, `texcoord`, `color` |
| `VertexOutput` | the fragment stage's input: `position: vec4<f32>` (`@builtin(position)`, framebuffer pixels), `texcoord: vec2<f32>` (`@location(0)`), `color: vec4<f32>` (`@location(1)`, premultiplied) |
| `projection` | `@group(0) @binding(0) var<uniform> mat4x4<f32>` |
| `tex_sampler` | `@group(0) @binding(1) var sampler`: the drawn texture's filter and wrap mode |
| `tex` | `@group(0) @binding(2) var texture_2d<f32>`: the texture being drawn |
| `vs_main` | the vertex stage |

```wgsl
struct Params { time: f32 };
@group(1) @binding(0) var<uniform> params: Params;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(tex, tex_sampler, in.texcoord) * in.color;
}
```

The prelude goes after your source (WGSL module-scope declarations can be
in any order), so line numbers in compile errors are those of the file you
wrote. If an error cites a line past the end of your source, the log says
it is in the prelude, which usually means you declared a reserved name.

**Full** (`load_shader`), for a custom vertex stage: the source declares
everything itself, using the same vertex input locations (position 0,
texcoord 1, colour 2) and group 0 bindings as the prelude.

In both forms group 1 is yours: at most one `var<uniform>` struct, whose
fields `set_shader_uniform` sets by name, and any number of `texture_2d`
bindings for `set_shader_texture`. Group 1 samplers are not supported;
sample with `tex_sampler` or read exact texels with `textureLoad`.

The vertex colour and every texture sample are premultiplied by alpha, and
the fragment shader must return premultiplied colour.
`textureSample(...) * in.color` and scaling the whole `vec4` are already
correct. To operate on the true colour (a LUT, a hue shift), divide `rgb` by
`a` first and multiply back afterwards; `examples/shader/lut.wgsl` shows
this.

```odin
// ok is optional. A shader that fails to compile logs the error and returns
// ok = false, but stays usable: draws fall back to the default shader until
// a hot-reload of fixed source succeeds. Both forms behave the same.
load_fragment_shader :: proc(wgsl_source: string) -> (shader: Shader, ok: bool)
load_shader :: proc(wgsl_source: string) -> (shader: Shader, ok: bool)
// From an asset path; hot-reloaded in dev builds, in the form it was loaded in.
load_fragment_shader_from_file :: proc(path: string) -> Shader
load_shader_from_file :: proc(path: string) -> Shader
// Array uniforms (array<T, N>, N a literal or an integer const) take a
// fixed array, slice or dynamic array; elements are copied into the WGSL
// stride, so [N][3]f32 fills array<vec3f, N>.
set_shader_uniform :: proc(shader: ^Shader, name: string, value: any)
set_shader_texture :: proc(shader: ^Shader, name: string, texture: Texture)
set_shader :: proc(shader: ^Shader)
reset_shader :: proc()
destroy_shader :: proc(shader: ^Shader)
```

## Camera

```odin
set_camera :: proc(camera: Maybe(Camera))
screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2
world_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2
camera_view_matrix :: proc(c: Camera) -> matrix[4, 4]f32
camera_world_matrix :: proc(c: Camera) -> matrix[4, 4]f32
```

## Blend Modes

```odin
// Applies to default and custom shaders; persists across render-texture
// switches and resets to .Alpha each frame.
set_blend_mode :: proc(mode: Blend_Mode)
reset_blend_mode :: proc()
```

## Scissor

```odin
set_scissor_rect :: proc(rect: Rect)
reset_scissor_rect :: proc()
```

## Input - Mouse

```odin
get_mouse_position :: proc() -> Vec2
get_mouse_delta :: proc() -> Vec2
get_scroll_delta :: proc(include_momentum: bool = true) -> Vec2
mouse_button_went_down :: proc(button: Mouse_Button) -> bool
mouse_button_went_up :: proc(button: Mouse_Button) -> bool
mouse_button_is_held :: proc(button: Mouse_Button) -> bool
```

## Input - Keyboard

```odin
key_went_down :: proc(key: Key) -> bool
key_went_up :: proc(key: Key) -> bool
key_is_held :: proc(key: Key) -> bool
```

## Input - Gamepad

Opt-in: call `init_gamepad()` once before `run()`. Up to `MAX_GAMEPADS` (4)
controllers, addressed by slot (`Gamepad_Index`, 0 = player one). Buttons are
named by physical position (`South`/`East`/`West`/`North` face buttons, etc.) so
code is vendor-neutral across Xbox/PlayStation/Switch. Sticks read -1..1,
triggers 0..1. Before `init_gamepad()` (or for disconnected / out-of-range
slots), queries return zero values and vibration is a no-op.

```odin
init_gamepad :: proc()      // call once, before run()
shutdown_gamepad :: proc()  // optional; engine also does this on exit
is_gamepad_connected :: proc(gamepad: Gamepad_Index) -> bool
get_gamepad_name :: proc(gamepad: Gamepad_Index) -> string
gamepad_button_went_down :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool
gamepad_button_went_up :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool
gamepad_button_is_held :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool
get_gamepad_axis :: proc(gamepad: Gamepad_Index, axis: Gamepad_Axis) -> f32
set_gamepad_vibration :: proc(gamepad: Gamepad_Index, left, right: f32, duration: f32 = 0)
```

## Input - Injection

Queue synthetic input for scripted tests and demos. Works with any window
backend, and is the only input under `init_headless`. Events are applied at
the start of the next frame, as if the OS had delivered them.

```odin
inject_key :: proc(key: Key, down: bool)
inject_mouse_move :: proc(pos: Vec2) // delta is the distance from the previous position
inject_mouse_button :: proc(button: Mouse_Button, down: bool) // at the pointer's position
inject_scroll :: proc(delta: Vec2)
```

## Input - Cursor

```odin
show_cursor :: proc()
hide_cursor :: proc()
set_cursor :: proc(cursor: System_Cursor)
set_custom_cursor :: proc(pixels: []u8, width, height: int, hot_x: int = 0, hot_y: int = 0)
```

## Audio - Lifecycle

```odin
init_audio :: proc() -> bool
shutdown_audio :: proc()
```

## Audio - Sources

```odin
// load_audio resolves `path` through the asset registry first (works on all
// platforms for registered assets), falling back to direct file access
// (desktop only) for unregistered paths.
load_audio :: proc(path: string, type: Audio_Source_Type = .Static) -> Audio_Source
load_audio_from_bytes :: proc(data: []u8, type: Audio_Source_Type = .Static) -> Audio_Source
destroy_audio :: proc(source: Audio_Source)
get_audio_duration :: proc(source: Audio_Source) -> f32
```

## Audio - Playback

```odin
play_audio :: proc(source: Audio_Source) -> Audio_Instance
play_audio :: proc(source: Audio_Source, params: Audio_Play_Params) -> Audio_Instance
stop_audio :: proc(instance: Audio_Instance)
pause_audio :: proc(instance: Audio_Instance)
resume_audio :: proc(instance: Audio_Instance)
stop_all_audio :: proc(bus: Audio_Bus = AUDIO_BUS_NONE)
default_audio_play_params :: proc() -> Audio_Play_Params
```

## Audio - Live Control

```odin
set_audio_volume :: proc(instance: Audio_Instance, volume: f32)
set_audio_pan :: proc(instance: Audio_Instance, pan: f32)
set_audio_pitch :: proc(instance: Audio_Instance, pitch: f32)
set_audio_looping :: proc(instance: Audio_Instance, loop: bool)
set_audio_position :: proc(instance: Audio_Instance, position: Vec2)
```

## Audio - Queries

```odin
is_audio_playing :: proc(instance: Audio_Instance) -> bool
is_audio_paused :: proc(instance: Audio_Instance) -> bool
get_audio_time :: proc(instance: Audio_Instance) -> f32
```

## Audio - Buses

```odin
create_audio_bus :: proc(name: string) -> Audio_Bus
destroy_audio_bus :: proc(bus: Audio_Bus)
get_main_audio_bus :: proc() -> Audio_Bus
set_audio_bus_volume :: proc(bus: Audio_Bus, volume: f32)
get_audio_bus_volume :: proc(bus: Audio_Bus) -> f32
set_audio_bus_muted :: proc(bus: Audio_Bus, muted: bool)
is_audio_bus_muted :: proc(bus: Audio_Bus) -> bool
```

## Audio - Spatial

```odin
set_audio_listener_position :: proc(position: Vec2)
get_audio_listener_position :: proc() -> Vec2
```
