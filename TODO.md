## Feature Plans

### 1. Camera System

**Goal**: 2D camera with position, zoom, rotation, and screen/world coordinate conversion.

**Design**:
- Camera transforms are applied by composing a view matrix with the existing orthographic projection, uploading the combined `view_projection` matrix to the same uniform buffer (no shader changes needed).
- `set_camera()` flushes the current batch (just like karl2d does), then recomputes and uploads the new view_projection matrix.
- Passing `nil` resets to identity view (screen-space drawing), which is how you draw UI on top of world content.

**Changes**:

1. **`core/core.odin`** — Add types:
   ```
   Camera :: struct {
       target:   Vec2,   // world point the camera looks at
       offset:   Vec2,   // screen offset (set to screen_center to center the target)
       rotation: f32,    // radians
       zoom:     f32,    // 1.0 = normal, >1 = zoomed in
   }
   ```

2. **`engine.odin`** — Add camera state to engine context:
   - `camera: Maybe(Camera)` — current active camera
   - `view_matrix: matrix[4,4]f32` — cached view matrix (identity when no camera)

3. **`camera.odin`** (new file) — Public API + math:
   - `set_camera(camera: Maybe(Camera))` — flush batch, update view matrix, re-upload view_projection to GPU
   - `screen_to_world(pos: Vec2, camera: Camera) -> Vec2` — multiply by world (inverse-view) matrix
   - `world_to_screen(pos: Vec2, camera: Camera) -> Vec2` — multiply by view matrix
   - `camera_view_matrix(c: Camera) -> matrix[4,4]f32` — construct without matrix inverse:
     `offset_translate * scale * rotate * (-target_translate)`
   - `camera_world_matrix(c: Camera) -> matrix[4,4]f32` — the inverse:
     `target_translate * (-rotate) * (1/scale) * (-offset_translate)`

4. **`core/render.odin`** — Add to `Render_Backend`:
   - `set_view_projection: proc(m: matrix[4,4]f32)` — upload the combined matrix to the GPU projection buffer

5. **`render/wgpu/wgpu.odin`** — Implement `set_view_projection`:
   - `wgpu.QueueWriteBuffer(queue, projection_buffer, 0, &m, size_of(m))`
   - The existing shader already applies this matrix to vertices, so no shader changes needed.

6. **Update `clear()`** — After `begin_frame`, re-apply the current camera's view_projection (since begin_frame resets per-frame state). Alternatively, have `set_camera` called once and persist across frames, re-uploading in `begin_frame`.

**Example usage**:
```
camera := w.Camera{ target = player_pos, offset = screen_center, zoom = 2.0 }
w.set_camera(camera)
// draw world...
w.set_camera(nil)
// draw UI...
```

---

### 2. Render Textures (Offscreen Rendering)

**Goal**: Draw into a texture instead of the screen, for post-processing, minimaps, transitions, etc.

**Design**:
- In wgpu, the render target is fixed for the lifetime of a render pass. Switching targets requires ending the current pass and beginning a new one.
- `set_render_texture()` flushes the batch, ends the current render pass, and begins a new one targeting either the render texture or the screen.
- The projection matrix is updated to match the render texture dimensions (or screen dimensions when switching back).

**Changes**:

1. **`core/core.odin`** — Add types:
   ```
   Render_Texture_Handle :: distinct u64

   Render_Texture :: struct {
       texture: Texture,                   // usable as a normal texture for drawing
       handle:  Render_Texture_Handle,     // backend's render target identifier
   }
   ```

2. **`core/render.odin`** — Add to `Render_Backend`:
   - `create_render_texture: proc(width, height: int) -> (Texture_Handle, Render_Texture_Handle)`
   - `destroy_render_texture: proc(handle: Render_Texture_Handle)`
   - `set_render_target: proc(handle: Maybe(Render_Texture_Handle), width, height: int)` — end current pass, begin new pass targeting render texture (or screen if nil)

3. **`render/wgpu/wgpu.odin`** — Backend implementation:
   - **Render_Texture_Entry**: stores `wgpu.Texture` (with `RenderAttachment | TextureBinding` usage), `wgpu.TextureView`, dimensions
   - **`renderer_create_render_texture`**: create a BGRA8Unorm texture with render attachment usage, return both the texture handle (for sampling) and render texture handle
   - **`renderer_set_render_target`**:
     1. Flush the batch
     2. End the current render pass (`RenderPassEncoderEnd`)
     3. Begin a new render pass with `loadOp = .Load` (preserve existing content) targeting either:
        - The render texture's view (if handle provided)
        - The screen surface view (if nil)
     4. Update projection for new dimensions
   - **`renderer_destroy_render_texture`**: release the texture and view

4. **`render_texture.odin`** (new file) — Public API:
   - `create_render_texture(width, height: int) -> Render_Texture`
   - `destroy_render_texture(rt: Render_Texture)`
   - `set_render_texture(rt: Maybe(Render_Texture))` — flush, switch target, update projection
   - When switching to a render texture, also re-apply the current camera transform to the new projection

5. **Frame lifecycle consideration**:
   - `begin_frame` always targets the screen initially
   - `set_render_texture` can switch mid-frame
   - `present` must ensure the final pass is the screen pass (or auto-switch back)
   - The render pass for a render texture should use `loadOp = .Load` by default (so `clear` can be called explicitly to clear it)

**Key wgpu detail**: The `clear` function currently calls `begin_frame` which creates the render pass with `loadOp = .Clear`. For render textures, we need a separate `clear_render_texture` or modify `clear` to clear whichever target is currently active.

---

### 3. Gamepad Input

**Goal**: Support gamepad/controller input with button state, analog axes, and vibration.

**Design**:
- Mirror the keyboard/mouse input pattern: `went_down`, `went_up`, `is_held` state arrays, reset each frame.
- Axis values are polled (not event-based) since analog sticks produce continuous values.
- Platform-specific backends provide raw gamepad data; the engine normalizes it.
- Support up to 4 gamepads (standard limit for most platforms).

**Changes**:

1. **`core/core.odin`** — Add types:
   ```
   MAX_GAMEPADS :: 4
   Gamepad_Index :: int  // 0 to MAX_GAMEPADS-1

   Gamepad_Button :: enum {
       // Face buttons
       South, East, West, North,     // A/B/X/Y (Xbox) or Cross/Circle/Square/Triangle (PS)
       // Shoulders
       Left_Shoulder, Right_Shoulder,
       // Triggers (as buttons, threshold-based)
       Left_Trigger, Right_Trigger,
       // Sticks
       Left_Stick, Right_Stick,
       // D-pad
       Dpad_Up, Dpad_Down, Dpad_Left, Dpad_Right,
       // Menu
       Start, Select, Guide,
   }

   Gamepad_Axis :: enum {
       Left_X, Left_Y,
       Right_X, Right_Y,
       Left_Trigger, Right_Trigger,
   }
   ```

2. **`core/input.odin`** — Add to `Input_State` (or equivalent):
   ```
   Gamepad_State :: struct {
       connected:     bool,
       button_down:   [Gamepad_Button]bool,   // went down this frame
       button_up:     [Gamepad_Button]bool,    // went up this frame
       button_held:   [Gamepad_Button]bool,    // currently held
       axes:          [Gamepad_Axis]f32,       // -1..1 for sticks, 0..1 for triggers
   }
   gamepads: [MAX_GAMEPADS]Gamepad_State
   ```

3. **`core/window.odin`** — Add to `Window_Backend`:
   - `poll_gamepads: proc(state: ^[MAX_GAMEPADS]Gamepad_State)` — platform fills in raw state each frame
   - `set_gamepad_vibration: proc(index: Gamepad_Index, left, right: f32)` — platform-specific rumble

4. **`input.odin`** — Public API:
   - `is_gamepad_connected(gamepad: Gamepad_Index) -> bool`
   - `gamepad_button_went_down(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool`
   - `gamepad_button_went_up(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool`
   - `gamepad_button_is_held(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool`
   - `get_gamepad_axis(gamepad: Gamepad_Index, axis: Gamepad_Axis) -> f32`
   - `set_gamepad_vibration(gamepad: Gamepad_Index, left, right: f32)`

5. **Platform backends** — implement `poll_gamepads`:
   - **macOS** (`#+build darwin`): GameController framework — `GCController.controllers()`, poll `extendedGamepad` button/axis values, `CHHapticEngine` for vibration
   - **Web** (`#+build js`): `navigator.getGamepads()` via JS interop, compare previous/current state to generate went_down/went_up events
   - **Linux**: evdev `/dev/input/eventN` with udev for hotplug detection, force feedback for vibration
   - **Windows**: XInput (`XInputGetState` / `XInputSetState`)

6. **Engine frame loop** — In the frame update (where `poll_events` runs):
   - Reset `button_down` and `button_up` arrays
   - Call `window.poll_gamepads` to get fresh state
   - Diff against previous frame to compute `went_down` / `went_up`

**Implementation order**: Start with macOS (GameController) since that's the dev platform, then web, then Linux/Windows.

---

### 5. Rotation on Draw Calls

**Goal**: `draw_rect_ex` and `draw_texture_ex` with origin + rotation parameters.

**Design**:
- The infrastructure already exists: `push_quad_ex` accepts arbitrary vertex positions (used by `draw_line`).
- Rotation is applied CPU-side by computing the 4 rotated corner positions, then submitting them via `push_quad_ex`.
- Origin defines the pivot point relative to the rect's top-left corner.

**Changes**:

1. **`draw.odin`** — Add two new procedures:

   ```
   draw_rect_ex :: proc(r: Rect, origin: Vec2, rotation: f32, color: Color)
   ```
   - If rotation is ~0, fall through to regular `draw_rect` (optimization)
   - Compute rotated corners:
     ```
     sin_r, cos_r := math.sincos(rotation)
     dx, dy := -origin.x, -origin.y
     // For each corner offset (dx,dy), (dx+w,dy), (dx+w,dy+h), (dx,dy+h):
     //   rotated.x = r.x + cx*cos_r - cy*sin_r
     //   rotated.y = r.y + cx*sin_r + cy*cos_r
     ```
   - Submit via `push_quad_ex`

   ```
   draw_texture_ex :: proc(
       tex: Texture, src: Rect, dst: Rect,
       origin: Vec2, rotation: f32, tint: Color = WHITE,
   )
   ```
   - Same rotation math as above, applied to `dst` rect corners
   - UV coordinates computed from `src` rect (same as `draw_texture_rect`)
   - Submit via `push_quad_ex`

2. **No backend changes needed** — `push_quad_ex` already handles arbitrary vertex positions.

3. **Helper** (private): Extract the rotation math into a shared helper:
   ```
   @(private="file")
   rotate_quad :: proc(rect: Rect, origin: Vec2, rotation: f32) -> [4]Vec2
   ```

---

### 6. Scissor Rect and Blend Mode

**Goal**: Clip rendering to a rectangle, and control alpha blending mode.

**Design**:

**Scissor Rect**:
- wgpu supports `RenderPassEncoderSetScissorRect()` which can be called between draw calls within the same render pass — no pass restart needed.
- Flush the batch when scissor changes, then set the new scissor rect.
- Pass `nil` to reset to full viewport.

**Blend Mode**:
- In wgpu, blend state is baked into the render pipeline object. Supporting multiple blend modes requires multiple pre-built pipelines.
- Create pipelines for each blend mode at init time. When blend mode changes, flush the batch and switch pipelines.
- Start with two modes: `Alpha` (standard src_alpha/one_minus_src_alpha) and `Premultiplied_Alpha` (one/one_minus_src_alpha).

**Changes**:

1. **`core/core.odin`** — Add types:
   ```
   Blend_Mode :: enum {
       Alpha,               // standard: src*alpha + dst*(1-alpha)
       Premultiplied_Alpha, // premultiplied: src + dst*(1-alpha)
   }
   ```

2. **`core/render.odin`** — Add to `Render_Backend`:
   - `set_scissor_rect: proc(rect: Maybe(Rect))` — set or clear scissor
   - `set_blend_mode: proc(mode: Blend_Mode)` — switch pipeline

3. **`render/wgpu/wgpu.odin`** — Backend implementation:

   **Scissor**:
   - `renderer_set_scissor_rect(rect: Maybe(core.Rect))`:
     1. Flush the batch
     2. If rect provided: `wgpu.RenderPassEncoderSetScissorRect(pass, x, y, w, h)`
     3. If nil: `wgpu.RenderPassEncoderSetScissorRect(pass, 0, 0, width, height)` (full viewport)

   **Blend mode**:
   - At init, create two pipelines:
     - `pipeline_alpha` (current default — `SrcAlpha / OneMinusSrcAlpha`)
     - `pipeline_premultiplied` (`One / OneMinusSrcAlpha`)
   - Add `active_blend_mode: Blend_Mode` to `Batch_State`
   - `renderer_set_blend_mode(mode)`:
     1. If same mode, early return
     2. Flush the batch
     3. Update `active_blend_mode`
   - In `renderer_flush`, select pipeline based on `active_blend_mode` (when no custom shader is active)
   - Custom shader pipelines: `create_render_pipeline` needs a blend mode parameter so custom shaders can also respect the active blend mode. Alternatively, create two pipeline variants per custom shader (may be overkill initially — start with default pipeline only).

4. **`draw.odin`** (or new `render_state.odin`) — Public API:
   - `set_scissor_rect(rect: Maybe(Rect))` — flush + delegate to backend
   - `set_blend_mode(mode: Blend_Mode)` — flush + delegate to backend

5. **Engine state** — Track current scissor and blend mode in engine context so they can be restored after render target switches.

---

## Implementation Priority

Recommended order (each builds on or is independent of the others):

1. **Rotation on draw calls** (#5) — Zero backend changes, purely additive, immediately useful
2. **Scissor rect / blend mode** (#6) — Small backend changes, unlocks clipping and premultiplied alpha
3. **Camera system** (#1) — Small backend change (set_view_projection), big usability win
4. **Render textures** (#2) — Largest backend change (render pass management), depends on camera for proper projection
5. **Gamepad input** (#3) — Independent of rendering, but requires significant per-platform work
