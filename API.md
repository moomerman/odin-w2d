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
get_screen_size :: proc() -> (int, int)
set_window_mode :: proc(mode: Window_Mode)
get_stats :: proc() -> Stats
get_gpu_device :: proc() -> rawptr
get_gpu_queue :: proc() -> rawptr
get_surface_format :: proc() -> u32
set_pre_present_callback :: proc(callback: proc(pass: rawptr, width, height: u32))
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
draw_texture :: proc(tex: Texture, pos: Vec2, tint: Color = WHITE)
draw_texture_rect :: proc(tex: Texture, src: Rect, dst: Rect, tint: Color = WHITE)
draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rotation: f32, tint: Color = WHITE)
draw_stats :: proc()
```

## Textures

```odin
load_texture :: proc(bytes: []u8, width: int = 0, height: int = 0) -> Texture
update_texture :: proc(tex: Texture, data: []u8, x, y, width, height: int)
destroy_texture :: proc(tex: ^Texture)
```

## Render Textures

```odin
create_render_texture :: proc(width: int, height: int) -> Render_Texture
set_render_texture :: proc(rt: Render_Texture, clear_color: Maybe(Color) = nil)
reset_render_texture :: proc()
destroy_render_texture :: proc(rt: ^Render_Texture)
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
```

## Shaders

```odin
load_shader :: proc(wgsl_source: string) -> Shader
set_shader_uniform :: proc(shader: ^Shader, name: string, value: any)
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
