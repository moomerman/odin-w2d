// Headless render and input tests.
//
// Runs the engine with no window (init_headless), draws known pictures and
// checks them with read_pixels. Each test owns one or more frames; a failed
// expectation is printed and the process exits with status 1.
//
//   odin run tests/render          (or: just test)
//   odin run tests/render -- 2     simulate a 2x HiDPI backing scale
//   odin run tests/render -- 1 projection   only tests whose name contains "projection"
//
// Adding a test: write a `proc(step: int) -> (done: bool)` and add it to
// `tests`. It is called once per frame between clear and present, with step
// counting from 0, until it returns true. Draw in logical coordinates
// (WIDTH x HEIGHT); `snap` + `at` read pixels back in the same coordinates
// whatever the scale.
package main

import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"
import "core:strconv"
import "core:strings"

import w "../.."

WIDTH :: 640
HEIGHT :: 360
DT :: 1.0 / 60.0

Test :: struct {
	name:    string,
	run:     proc(step: int) -> (done: bool),
	// Optional: called before the frame begins (outside clear/present), for
	// things that must happen between frames such as a resize.
	between: proc(step: int),
}

tests := []Test {
	{name = "fixed_timestep", run = test_fixed_timestep},
	{name = "projection_before_camera", run = test_projection_before_camera},
	{name = "projection_after_render_texture", run = test_projection_after_render_texture},
	{name = "transform_stack", run = test_transform_stack},
	{name = "uniforms_per_draw", run = test_uniforms_per_draw},
	{name = "uniform_buffer_growth", run = test_uniform_buffer_growth},
	{name = "uniforms_set_at_init", run = test_uniforms_set_at_init},
	{name = "uniform_type_conversion", run = test_uniform_type_conversion},
	{name = "many_quads", run = test_many_quads},
	{name = "alpha_render_texture_compositing", run = test_alpha_render_texture_compositing},
	{name = "alpha_texture_pixels", run = test_alpha_texture_pixels},
	{name = "alpha_gradient_to_transparent", run = test_alpha_gradient_to_transparent},
	{name = "alpha_readback_is_straight", run = test_alpha_readback_is_straight},
	{name = "blend_additive", run = test_blend_additive},
	{name = "blend_multiply", run = test_blend_multiply},
	{name = "scissor_clips", run = test_scissor_clips},
	{name = "scissor_out_of_bounds", run = test_scissor_out_of_bounds},
	{name = "scissor_render_texture", run = test_scissor_render_texture},
	{name = "invalid_render_target", run = test_invalid_render_target},
	{name = "text_draws", run = test_text_draws},
	{name = "input_injection", run = test_input_injection},
	{name = "resize", run = test_resize, between = between_resize},
	{name = "sampling_linear_filter", run = test_sampling_linear_filter},
	{name = "sampling_wrap", run = test_sampling_wrap},
	{name = "sampling_change_mid_frame", run = test_sampling_change_mid_frame},
	{name = "sampling_render_texture_shader", run = test_sampling_render_texture_shader},
	{name = "many_textures", run = test_many_textures},
	{name = "fragment_shader_draws", run = test_fragment_shader_draws},
	{name = "fragment_shader_compile_error", run = test_fragment_shader_compile_error},
	{name = "frame_count", run = test_frame_count},
	{name = "save_render_texture", run = test_save_render_texture},
}

scale: f32 = 1
filter: string
current: int
step: int
failures: int
test_failures: int

tint_shader: w.Shader
glow_shader: w.Shader
small_rt: w.Render_Texture

main :: proc() {
	if len(os.args) > 1 {
		if v, ok := strconv.parse_f32(os.args[1]); ok && v > 0 {
			scale = v
		}
	}
	if len(os.args) > 2 {
		filter = os.args[2]
	}

	w.init_headless(WIDTH, HEIGHT, scale, DT)
	w.run(init, frame, shutdown)

	if failures > 0 {
		fmt.printfln("FAILED: %d expectation(s) at scale %v", failures, scale)
		os.exit(1)
	}
	fmt.printfln("ok (scale %v)", scale)
}

init :: proc() {
	tint_shader = w.load_shader(TINT_SHADER)
	// Some uniforms are set once here and never again; others every draw.
	glow_shader = w.load_shader(GLOW_SHADER)
	w.set_shader_uniform(&glow_shader, "color_r", f32(0))
	w.set_shader_uniform(&glow_shader, "color_g", f32(0))
	w.set_shader_uniform(&glow_shader, "color_b", f32(1))
	w.set_shader_uniform(&glow_shader, "intensity", f32(1))
	w.set_shader_uniform(&glow_shader, "falloff", f32(8))
	small_rt = w.create_render_texture(16, 16)
	skip_filtered()
}

shutdown :: proc() {
	w.destroy_shader(&tint_shader)
	w.destroy_shader(&glow_shader)
	w.destroy_render_texture(&small_rt)
}

frame :: proc(dt: f32) {
	if current >= len(tests) {
		w.quit()
		return
	}
	t := tests[current]
	if t.between != nil {
		t.between(step)
	}

	w.clear(w.BLACK)
	done := t.run(step)
	w.present()

	step += 1
	frames_run += 1
	if done {
		fmt.printfln("%s %s", test_failures == 0 ? "PASS" : "FAIL", t.name)
		test_failures = 0
		step = 0
		current += 1
		skip_filtered()
	}
	free_all(context.temp_allocator)
}

skip_filtered :: proc() {
	for current < len(tests) && filter != "" && !strings.contains(tests[current].name, filter) {
		current += 1
	}
}

//---------//
// HELPERS //
//---------//

Snap :: struct {
	pixels: []u8,
	width:  int,
	height: int,
}

// Read back the screen as drawn so far this frame (temp-allocated).
snap :: proc() -> Snap {
	pixels, width, height, ok := w.read_pixels(context.temp_allocator)
	if !ok {
		fail("read_pixels failed")
	}
	return {pixels, width, height}
}

// Pixel at a logical coordinate.
at :: proc(s: Snap, x, y: f32) -> w.Color {
	px := int(x * f32(s.width) / WIDTH)
	py := int(y * f32(s.height) / HEIGHT)
	if px < 0 || py < 0 || px >= s.width || py >= s.height {
		return {}
	}
	i := (py * s.width + px) * 4
	return {s.pixels[i], s.pixels[i + 1], s.pixels[i + 2], s.pixels[i + 3]}
}

fail :: proc(format: string, args: ..any) {
	failures += 1
	test_failures += 1
	fmt.printf("  [%s step %d] ", tests[current].name, step)
	fmt.printfln(format, ..args)
}

expect :: proc(cond: bool, what: string) {
	if !cond {
		fail("expected %s", what)
	}
}

// Colours match within `tolerance` per channel.
expect_color :: proc(got, want: w.Color, what: string, tolerance := 0) {
	for i in 0 ..< 4 {
		if abs(int(got[i]) - int(want[i])) > tolerance {
			fail("%s: got %v, want %v", what, got, want)
			return
		}
	}
}

// Draws with a solid colour taken from uniforms: tint * gain.
TINT_SHADER :: `
struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
};
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
};
@group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
struct Params {
    tint: vec4<f32>,
    gain: f32,
};
@group(1) @binding(0) var<uniform> params: Params;
@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = projection * vec4<f32>(in.position, 0.0, 1.0);
    return out;
}
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(params.tint.rgb * params.gain, 1.0);
}
`

// A radial glow: five scalar uniforms (a 20-byte struct), colour times a
// falloff from the quad's centre, returned premultiplied.
GLOW_SHADER :: `
struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
};
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) texcoord: vec2<f32>,
};
@group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
struct Params {
    color_r: f32,
    color_g: f32,
    color_b: f32,
    intensity: f32,
    falloff: f32,
};
@group(1) @binding(0) var<uniform> params: Params;
@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = projection * vec4<f32>(in.position, 0.0, 1.0);
    out.texcoord = in.texcoord;
    return out;
}
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let d = distance(in.texcoord, vec2<f32>(0.5, 0.5)) * 2.0;
    let glow = clamp(exp(-d * d * params.falloff) * params.intensity, 0.0, 1.0);
    return vec4<f32>(vec3<f32>(params.color_r, params.color_g, params.color_b) * glow, glow);
}
`

//-------//
// TESTS //
//-------//

// init_headless's frame_time: every frame after the first reports exactly
// DT, and get_time advances by it.
last_time: f64

test_fixed_timestep :: proc(step: int) -> bool {
	if step > 0 {
		expect(w.get_frame_time() == DT, "dt == 1/60")
		expect(abs(w.get_time() - last_time - DT) < 1e-6, "get_time advances by 1/60")
	}
	last_time = w.get_time()
	return step == 2
}

// Drawing before the first set_camera of a frame must stay in screen space,
// in that frame and the next (the camera matrix once overwrote slot 0).
test_projection_before_camera :: proc(step: int) -> bool {
	w.draw_rect({0, 0, 100, 100}, w.RED)
	if step == 0 {
		w.set_camera(w.Camera{target = {0, 0}, offset = {320, 180}, zoom = 1})
		w.draw_rect({-10, -10, 20, 20}, w.GREEN)
		w.set_camera(nil)
	}
	s := snap()
	expect_color(at(s, 50, 50), w.RED, "screen-space rect")
	expect_color(at(s, 370, 230), w.BLACK, "screen-space rect not moved by the camera")
	if step == 0 {
		expect_color(at(s, 320, 180), w.GREEN, "world rect at the camera offset")
	}
	return step == 1
}

// Same, for the render-texture projection: a 16x16 target's projection must
// not leak into screen drawing in this frame or the next.
test_projection_after_render_texture :: proc(step: int) -> bool {
	w.draw_rect({600, 320, 20, 20}, w.RED)
	if step == 0 {
		w.set_render_texture(small_rt, w.BLANK)
		w.draw_rect({0, 0, 16, 16}, w.BLUE)
		w.reset_render_texture()
		w.draw_rect({500, 320, 20, 20}, w.GREEN)
	}
	s := snap()
	expect_color(at(s, 610, 330), w.RED, "rect drawn before the render texture")
	expect_color(at(s, 300, 100), w.BLACK, "nothing stretched across the screen")
	if step == 0 {
		expect_color(at(s, 510, 330), w.GREEN, "rect drawn after the render texture")
	}
	return step == 1
}

test_transform_stack :: proc(step: int) -> bool {
	w.push_transform({200, 100}, scale = {2, 2})
	w.draw_rect({0, 0, 10, 10}, w.RED)
	w.pop_transform()
	w.draw_rect({0, 0, 10, 10}, w.GREEN)
	s := snap()
	expect_color(at(s, 215, 115), w.RED, "translated, scaled rect")
	expect_color(at(s, 225, 125), w.BLACK, "scaled rect is 20x20")
	expect_color(at(s, 5, 5), w.GREEN, "rect after pop_transform")
	return true
}

// Each draw sees the uniform values set when it was issued.
test_uniforms_per_draw :: proc(step: int) -> bool {
	w.set_shader(&tint_shader)
	w.set_shader_uniform(&tint_shader, "gain", f32(1))
	w.set_shader_uniform(&tint_shader, "tint", [4]f32{1, 0, 0, 1})
	w.draw_rect({0, 0, 100, 100}, w.WHITE)
	w.set_shader_uniform(&tint_shader, "tint", [4]f32{0, 1, 0, 1})
	w.draw_rect({200, 0, 100, 100}, w.WHITE)
	w.reset_shader()
	s := snap()
	expect_color(at(s, 50, 50), {255, 0, 0, 255}, "first draw keeps its tint")
	expect_color(at(s, 250, 50), {0, 255, 0, 255}, "second draw gets the new tint")
	return true
}

// More uniform changes in a frame than the buffer's initial slots.
test_uniform_buffer_growth :: proc(step: int) -> bool {
	N :: 40
	w.set_shader(&tint_shader)
	w.set_shader_uniform(&tint_shader, "gain", f32(1))
	for i in 0 ..< N {
		t := f32(i) / (N - 1)
		w.set_shader_uniform(&tint_shader, "tint", [4]f32{t, 0, 1 - t, 1})
		w.draw_rect({f32(i) * 16, 0, 16, 16}, w.WHITE)
	}
	w.reset_shader()
	s := snap()
	expect_color(at(s, 8, 8), {0, 0, 255, 255}, "first of 40")
	expect_color(at(s, 20 * 16 + 8, 8), {131, 0, 124, 255}, "21st of 40", 1)
	expect_color(at(s, 39 * 16 + 8, 8), {255, 0, 0, 255}, "last of 40")
	return true
}

// Uniforms set once in the init proc keep their values in every later frame,
// alongside ones that change per draw (and the quad's UVs span 0..1).
test_uniforms_set_at_init :: proc(step: int) -> bool {
	for i in 0 ..< 2 {
		w.set_shader_uniform(&glow_shader, "color_r", f32(i))
		w.set_shader_uniform(&glow_shader, "color_b", f32(1 - i))
		w.set_shader(&glow_shader)
		w.draw_rect({f32(i) * 200, 0, 200, 200}, w.WHITE)
		w.reset_shader()
	}
	s := snap()
	expect_color(at(s, 100, 100), {0, 0, 255, 255}, "first glow's centre", 2)
	expect_color(at(s, 300, 100), {255, 0, 0, 255}, "second glow's centre", 2)
	expect_color(at(s, 10, 100), w.BLACK, "glow has fallen off at the quad's edge", 2)
	expect_color(at(s, 100, 190), w.BLACK, "glow has fallen off at the bottom", 2)
	return step == 2
}

// Untyped constants arrive in an `any` as f64 / int; they must be converted,
// and values that do not fit must be ignored rather than copied as garbage.
test_uniform_type_conversion :: proc(step: int) -> bool {
	w.set_shader(&tint_shader)
	w.set_shader_uniform(&tint_shader, "tint", [4]f64{1, 1, 1, 1})
	w.set_shader_uniform(&tint_shader, "gain", 0.5)
	w.draw_rect({0, 0, 50, 50}, w.WHITE)
	w.set_shader_uniform(&tint_shader, "gain", 1)
	w.draw_rect({100, 0, 50, 50}, w.WHITE)
	w.set_shader_uniform(&tint_shader, "tint", f32(0)) // wrong shape: ignored (logs once)
	w.draw_rect({200, 0, 50, 50}, w.WHITE)
	w.reset_shader()
	s := snap()
	expect_color(at(s, 25, 25), {128, 128, 128, 255}, "f64 gain 0.5", 1)
	expect_color(at(s, 125, 25), {255, 255, 255, 255}, "int gain 1")
	expect_color(at(s, 225, 25), {255, 255, 255, 255}, "scalar for a vec4 is ignored")
	return true
}

// More quads than one vertex buffer holds, with a camera change and a render
// target switch part-way; the first quad drawn must survive.
test_many_quads :: proc(step: int) -> bool {
	w.draw_rect({0, 0, 100, 100}, w.RED)
	for i in 0 ..< 50_000 {
		if i == 20_000 {
			w.set_camera(w.Camera{zoom = 1})
			w.set_camera(nil)
		}
		if i == 30_000 {
			w.set_render_texture(small_rt, w.BLANK)
			w.reset_render_texture()
		}
		w.draw_rect({300 + f32(i % 100), 100 + f32(i / 100 % 100), 1, 1}, w.BLUE)
	}
	w.draw_rect({500, 0, 100, 100}, w.GREEN)
	s := snap()
	expect_color(at(s, 50, 50), w.RED, "first quad")
	expect_color(at(s, 350, 150), w.BLUE, "middle quads")
	expect_color(at(s, 550, 50), w.GREEN, "last quad")
	expect(w.get_stats().quads >= 0, "stats readable")
	return true
}

// The renderer works in premultiplied alpha, so translucent content drawn
// into a transparent render texture and then composited looks exactly like
// the same content drawn directly.
test_alpha_render_texture_compositing :: proc(step: int) -> bool {
	HALF_RED :: w.Color{255, 0, 0, 128}
	w.draw_rect({0, 0, WIDTH, HEIGHT}, w.WHITE)
	w.draw_rect({10, 10, 50, 50}, HALF_RED)

	w.set_render_texture(small_rt, w.BLANK)
	w.draw_rect({0, 0, 16, 16}, HALF_RED)
	w.reset_render_texture()
	w.draw_texture_rect(small_rt.texture, {0, 0, 16, 16}, {110, 10, 50, 50})
	// Tinting a render texture with a translucent colour fades it further.
	w.draw_texture_rect(small_rt.texture, {0, 0, 16, 16}, {210, 10, 50, 50}, {255, 255, 255, 128})

	s := snap()
	expect_color(at(s, 35, 35), {255, 127, 127, 255}, "50% red on white, drawn directly", 1)
	expect_color(at(s, 135, 35), at(s, 35, 35), "same via a render texture", 1)
	expect_color(at(s, 235, 35), {255, 191, 191, 255}, "render texture at 50% tint", 2)
	return true
}

// Texture pixels are given with straight alpha (as image files store them).
test_alpha_texture_pixels :: proc(step: int) -> bool {
	pixels := [8]u8{255, 0, 0, 128, 0, 255, 0, 255}
	tex := w.load_texture(pixels[:], 2, 1)
	defer w.destroy_texture(&tex)
	if step == 1 {
		// update_texture takes straight alpha too.
		blue := [4]u8{0, 0, 255, 128}
		w.update_texture(tex, blue[:], 0, 0, 1, 1)
	}

	w.draw_rect({0, 0, 100, 100}, w.WHITE)
	w.draw_texture_rect(tex, {0, 0, 2, 1}, {0, 0, 100, 50})
	w.draw_texture_rect(tex, {0, 0, 2, 1}, {200, 0, 100, 50})
	s := snap()
	if step == 0 {
		expect_color(at(s, 25, 25), {255, 127, 127, 255}, "50% red texel on white", 1)
		expect_color(at(s, 225, 25), {128, 0, 0, 255}, "50% red texel on black", 1)
	} else {
		expect_color(at(s, 25, 25), {127, 127, 255, 255}, "updated 50% blue texel on white", 1)
	}
	expect_color(at(s, 75, 25), {0, 255, 0, 255}, "opaque green texel")
	return step == 1
}

// Per-vertex colours interpolate in premultiplied space: a fade to BLANK
// keeps its hue instead of darkening on the way.
test_alpha_gradient_to_transparent :: proc(step: int) -> bool {
	w.draw_rect({0, 0, WIDTH, HEIGHT}, w.WHITE)
	w.draw_rect_gradient_h({0, 100, 200, 20}, {255, 0, 0, 255}, w.BLANK)
	s := snap()
	expect_color(
		at(s, 100, 110),
		{255, 128, 128, 255},
		"midpoint of red-to-transparent on white",
		3,
	)
	expect_color(at(s, 2, 110), {255, 3, 3, 255}, "opaque end", 4)
	expect_color(at(s, 198, 110), {255, 252, 252, 255}, "transparent end", 4)
	return true
}

// read_render_texture returns straight alpha, the form load_texture takes.
test_alpha_readback_is_straight :: proc(step: int) -> bool {
	if step == 0 {
		w.set_render_texture(small_rt, w.BLANK)
		w.draw_rect({0, 0, 16, 16}, w.Color{255, 255, 255, 128})
	} else {
		w.set_render_texture(small_rt, w.Color{255, 0, 0, 128}) // translucent clear colour
	}
	w.reset_render_texture()
	p, _, _, ok := w.read_render_texture(small_rt, context.temp_allocator)
	expect(ok, "read_render_texture ok")
	if ok {
		got := w.Color{p[0], p[1], p[2], p[3]}
		if step == 0 {
			expect_color(got, {255, 255, 255, 128}, "50% white drawn on clear", 1)
		} else {
			expect_color(got, {255, 0, 0, 128}, "cleared to 50% red", 1)
		}
	}
	return step == 1
}

// Additive adds colour scaled by alpha and never changes coverage, so
// additive drawing into a transparent render texture still adds when the
// texture is composited.
test_blend_additive :: proc(step: int) -> bool {
	w.draw_rect({0, 0, WIDTH, HEIGHT}, {0, 0, 255, 255})
	w.set_blend_mode(.Additive)
	w.draw_rect({0, 0, 50, 50}, {255, 0, 0, 255})
	w.draw_rect({100, 0, 50, 50}, {255, 0, 0, 128})
	w.reset_blend_mode()

	w.set_render_texture(small_rt, w.BLANK)
	w.set_blend_mode(.Additive)
	w.draw_rect({0, 0, 16, 16}, {255, 0, 0, 128})
	w.reset_blend_mode()
	w.reset_render_texture()
	w.draw_texture_rect(small_rt.texture, {0, 0, 16, 16}, {200, 0, 50, 50})

	s := snap()
	expect_color(at(s, 25, 25), {255, 0, 255, 255}, "opaque red added to blue")
	expect_color(at(s, 125, 25), {128, 0, 255, 255}, "50% red added to blue", 1)
	expect_color(at(s, 225, 25), {128, 0, 255, 255}, "additive glow via a render texture", 1)
	return true
}

// Multiply darkens by the source colour, in proportion to its alpha.
test_blend_multiply :: proc(step: int) -> bool {
	w.draw_rect({0, 0, WIDTH, HEIGHT}, {200, 200, 200, 255})
	w.set_blend_mode(.Multiply)
	w.draw_rect({0, 0, 50, 50}, {128, 128, 128, 255})
	w.draw_rect({100, 0, 50, 50}, {0, 0, 0, 0})
	w.draw_rect({200, 0, 50, 50}, {0, 0, 0, 128})
	w.reset_blend_mode()
	s := snap()
	expect_color(at(s, 25, 25), {100, 100, 100, 255}, "200 x 50% grey", 1)
	expect_color(at(s, 125, 25), {200, 200, 200, 255}, "fully transparent source leaves it alone")
	expect_color(at(s, 225, 25), {100, 100, 100, 255}, "50% black halves it", 1)
	return true
}

test_scissor_clips :: proc(step: int) -> bool {
	w.set_scissor_rect({50, 50, 100, 100})
	w.draw_rect({0, 0, WIDTH, HEIGHT}, w.RED)
	w.reset_scissor_rect()
	w.draw_rect({300, 300, 20, 20}, w.GREEN)
	s := snap()
	expect_color(at(s, 100, 100), w.RED, "inside the scissor")
	expect_color(at(s, 52, 52), w.RED, "just inside the scissor's corner")
	expect_color(at(s, 147, 147), w.RED, "just inside the far corner")
	expect_color(at(s, 45, 100), w.BLACK, "left of the scissor")
	expect_color(at(s, 155, 100), w.BLACK, "right of the scissor")
	expect_color(at(s, 100, 155), w.BLACK, "below the scissor")
	expect_color(at(s, 310, 310), w.GREEN, "drawing after reset_scissor_rect")
	return true
}

// Rects that are partly or wholly off the target must clip, not crash.
test_scissor_out_of_bounds :: proc(step: int) -> bool {
	w.set_scissor_rect({-50, -50, 100, 100}) // negative origin: clips to 50x50
	w.draw_rect({0, 0, WIDTH, HEIGHT}, w.RED)
	w.set_scissor_rect({600, 300, 500, 500}) // hangs off the bottom-right
	w.draw_rect({0, 0, WIDTH, HEIGHT}, w.GREEN)
	w.set_scissor_rect({700, 0, 50, 50}) // wholly outside: draws nothing
	w.draw_rect({0, 0, WIDTH, HEIGHT}, w.BLUE)
	w.set_scissor_rect({100, 100, 0, 50}) // zero area: draws nothing
	w.draw_rect({0, 0, WIDTH, HEIGHT}, w.BLUE)
	w.reset_scissor_rect()
	s := snap()
	expect_color(at(s, 25, 25), w.RED, "negative-origin scissor keeps its visible part")
	expect_color(at(s, 55, 25), w.BLACK, "negative-origin scissor is not widened")
	expect_color(at(s, 620, 340), w.GREEN, "scissor hanging off the edge")
	expect_color(at(s, 590, 340), w.BLACK, "left of the hanging scissor")
	expect_color(at(s, 300, 200), w.BLACK, "off-target and zero-area scissors draw nothing")
	return true
}

// On a render texture the scissor is in the texture's own pixels, whatever
// the window's scale, and is clamped to the texture.
test_scissor_render_texture :: proc(step: int) -> bool {
	w.set_render_texture(small_rt, w.BLACK)
	w.set_scissor_rect({8, 0, 100, 100})
	w.draw_rect({0, 0, 16, 16}, w.RED)
	w.reset_scissor_rect()
	w.reset_render_texture()
	p, pw, _, ok := w.read_render_texture(small_rt, context.temp_allocator)
	expect(ok, "read_render_texture ok")
	if ok {
		px :: proc(p: []u8, pw, x, y: int) -> w.Color {
			i := (y * pw + x) * 4
			return {p[i], p[i + 1], p[i + 2], p[i + 3]}
		}
		expect_color(px(p, pw, 7, 8), w.BLACK, "texel left of the scissor")
		expect_color(px(p, pw, 8, 8), w.RED, "first texel inside the scissor")
		expect_color(px(p, pw, 15, 15), w.RED, "last texel")
	}
	return true
}

// A destroyed render texture must be ignored, and drawing must carry on.
test_invalid_render_target :: proc(step: int) -> bool {
	dead := w.create_render_texture(8, 8)
	stale := dead
	w.destroy_render_texture(&dead)
	w.set_render_texture(stale) // logs, target unchanged
	w.reset_render_texture()
	w.draw_rect({0, 0, 100, 100}, w.RED)
	s := snap()
	expect_color(at(s, 50, 50), w.RED, "screen drawing after an invalid render target")
	return true
}

test_text_draws :: proc(step: int) -> bool {
	size := w.measure_text("HHHH", 64)
	expect(size.x > 40 && size.y > 40, "measure_text gives a plausible size")
	w.draw_text("HHHH", {20, 20}, 64, w.WHITE)
	s := snap()
	lit := 0
	for y := f32(20); y < 20 + size.y; y += 2 {
		for x := f32(20); x < 20 + size.x; x += 2 {
			if at(s, x, y).r > 200 {
				lit += 1
			}
		}
	}
	expect(lit > 50, "glyph pixels inside the measured box")
	expect_color(at(s, 20 + size.x + 30, 40), w.BLACK, "nothing right of the text")
	return true
}

// Injected events are applied at the start of the next frame.
test_input_injection :: proc(step: int) -> bool {
	switch step {
	case 0:
		expect(!w.key_is_held(.Space), "Space starts released")
		w.inject_key(.Space, true)
		w.inject_mouse_move({100, 50})
		w.inject_mouse_button(.Left, true)
		w.inject_scroll({0, 3})
	case 1:
		expect(w.key_went_down(.Space), "Space went down")
		expect(w.key_is_held(.Space), "Space held")
		expect(w.get_mouse_position() == w.Vec2{100, 50}, "mouse at 100,50")
		expect(w.mouse_button_went_down(.Left), "left button went down")
		expect(w.get_scroll_delta() == w.Vec2{0, 3}, "scroll delta 0,3")
		w.inject_mouse_move({110, 70})
	case 2:
		expect(!w.key_went_down(.Space), "went_down lasts one frame")
		expect(w.key_is_held(.Space), "Space still held")
		expect(w.mouse_button_is_held(.Left), "left button still held")
		expect(w.get_mouse_delta() == w.Vec2{10, 20}, "mouse delta 10,20")
		expect(w.get_scroll_delta() == w.Vec2{}, "scroll delta cleared")
		w.inject_key(.Space, false)
		w.inject_mouse_button(.Left, false)
	case 3:
		expect(w.key_went_up(.Space), "Space went up")
		expect(!w.key_is_held(.Space), "Space released")
		expect(w.mouse_button_went_up(.Left), "left button went up")
		expect(!w.mouse_button_is_held(.Left), "left button released")
		return true
	}
	return false
}

// Resizing between frames: screen size, framebuffer and projection follow.
between_resize :: proc(step: int) {
	switch step {
	case 1:
		w.set_headless_size(320, 200)
	case 2:
		w.set_headless_size(WIDTH, HEIGHT)
	}
}

test_resize :: proc(step: int) -> bool {
	sw, sh := w.get_screen_size()
	if step == 1 {
		expect(sw == 320 && sh == 200, "screen size 320x200 after resize")
		w.draw_rect({300, 180, 20, 20}, w.RED)
		pixels, pw, ph, ok := w.read_pixels(context.temp_allocator)
		expect(ok, "read_pixels after resize")
		if ok {
			expect(
				pw == int(320 * scale) && ph == int(200 * scale),
				"framebuffer follows the resize",
			)
			i := ((ph - 2) * pw + (pw - 2)) * 4
			expect_color(
				{pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]},
				w.RED,
				"bottom-right corner in the new projection",
			)
		}
		return false
	}
	expect(sw == WIDTH && sh == HEIGHT, "screen size 640x360")
	w.draw_rect({620, 340, 20, 20}, w.RED)
	s := snap()
	expect(s.width == int(WIDTH * scale) && s.height == int(HEIGHT * scale), "framebuffer size")
	expect_color(at(s, 630, 350), w.RED, "bottom-right corner")
	return step == 2
}

//----------//
// SAMPLING //
//----------//

// A 2x1 texture: a red texel then a blue one.
red_blue_texture :: proc() -> w.Texture {
	pixels := [8]u8{255, 0, 0, 255, 0, 0, 255, 255}
	return w.load_texture(pixels[:], 2, 1)
}

// Nearest returns one texel or the other; linear blends them, half and half
// on the texel boundary and 70/30 at u = 0.4.
test_sampling_linear_filter :: proc(step: int) -> bool {
	nearest := red_blue_texture()
	defer w.destroy_texture(&nearest)
	linear := red_blue_texture()
	defer w.destroy_texture(&linear)
	expect(w.get_texture_filter(linear) == .Nearest, "textures start .Nearest")
	w.set_texture_filter(linear, .Linear)
	expect(w.get_texture_filter(linear) == .Linear, "get_texture_filter reports .Linear")

	w.draw_texture_rect(nearest, {0, 0, 2, 1}, {0, 0, 200, 20})
	w.draw_texture_rect(linear, {0, 0, 2, 1}, {0, 40, 200, 20})
	s := snap()
	expect_color(at(s, 80, 10), {255, 0, 0, 255}, "nearest at u=0.4 is the red texel")
	expect_color(at(s, 120, 10), {0, 0, 255, 255}, "nearest at u=0.6 is the blue texel")
	expect_color(at(s, 80, 50), {178, 0, 77, 255}, "linear at u=0.4 blends 70/30", 2)
	expect_color(at(s, 100, 50), {128, 0, 128, 255}, "linear on the texel boundary", 2)
	expect_color(at(s, 10, 50), {255, 0, 0, 255}, "linear clamps at the left edge", 1)
	return true
}

// A source rect four texels wide over a two-texel texture: clamp stretches
// the last texel, repeat tiles, mirror tiles flipped.
test_sampling_wrap :: proc(step: int) -> bool {
	clamped := red_blue_texture()
	defer w.destroy_texture(&clamped)
	repeated := red_blue_texture()
	defer w.destroy_texture(&repeated)
	mirrored := red_blue_texture()
	defer w.destroy_texture(&mirrored)
	expect(w.get_texture_wrap(clamped) == .Clamp, "textures start .Clamp")
	w.set_texture_wrap(repeated, .Repeat)
	w.set_texture_wrap(mirrored, .Mirror)
	expect(w.get_texture_wrap(repeated) == .Repeat, "get_texture_wrap reports .Repeat")

	src := w.Rect{0, 0, 4, 1}
	w.draw_texture_rect(clamped, src, {0, 0, 200, 20})
	w.draw_texture_rect(repeated, src, {0, 40, 200, 20})
	w.draw_texture_rect(mirrored, src, {0, 80, 200, 20})
	s := snap()
	RED :: w.Color{255, 0, 0, 255}
	BLUE :: w.Color{0, 0, 255, 255}
	expect_color(at(s, 25, 10), RED, "clamp: first texel")
	expect_color(at(s, 125, 10), BLUE, "clamp: past the edge is the edge texel")
	expect_color(at(s, 175, 10), BLUE, "clamp: still the edge texel")
	expect_color(at(s, 75, 50), BLUE, "repeat: second texel")
	expect_color(at(s, 125, 50), RED, "repeat: second copy starts red")
	expect_color(at(s, 175, 50), BLUE, "repeat: second copy ends blue")
	expect_color(at(s, 125, 90), BLUE, "mirror: flipped copy starts blue")
	expect_color(at(s, 175, 90), RED, "mirror: flipped copy ends red")
	return true
}

// The same texture drawn three times in one frame, its filter changed
// between the draws: each draw keeps the filter it was issued with (the
// third reuses the first's cached bind group).
test_sampling_change_mid_frame :: proc(step: int) -> bool {
	tex := red_blue_texture()
	defer w.destroy_texture(&tex)
	w.draw_texture_rect(tex, {0, 0, 2, 1}, {0, 0, 200, 20})
	w.set_texture_filter(tex, .Linear)
	w.draw_texture_rect(tex, {0, 0, 2, 1}, {0, 40, 200, 20})
	w.set_texture_filter(tex, .Nearest)
	w.draw_texture_rect(tex, {0, 0, 4, 1}, {0, 80, 200, 20})
	w.set_texture_wrap(tex, .Repeat)
	w.draw_texture_rect(tex, {0, 0, 4, 1}, {0, 120, 200, 20})
	s := snap()
	expect_color(at(s, 80, 10), {255, 0, 0, 255}, "draw before the change stays nearest")
	expect_color(at(s, 80, 50), {178, 0, 77, 255}, "draw after the change is linear", 2)
	expect_color(at(s, 40, 90), {255, 0, 0, 255}, "draw after changing back is nearest")
	expect_color(at(s, 125, 90), {0, 0, 255, 255}, "draw before set_texture_wrap clamps")
	expect_color(at(s, 125, 130), {255, 0, 0, 255}, "draw after set_texture_wrap repeats")
	return true
}

// Passes the sample through with red and blue swapped, so the result shows
// both that the custom shader ran and how it sampled.
SWAP_SHADER :: `
struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
};
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) texcoord: vec2<f32>,
};
@group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
@group(0) @binding(1) var tex_sampler: sampler;
@group(0) @binding(2) var tex: texture_2d<f32>;
@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = projection * vec4<f32>(in.position, 0.0, 1.0);
    out.texcoord = in.texcoord;
    return out;
}
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(tex, tex_sampler, in.texcoord).bgra;
}
`

// The motivating case: a low-resolution render texture with linear
// filtering, stretched over the screen by a post-process shader.
swap_shader: w.Shader
sampling_rt: w.Render_Texture

test_sampling_render_texture_shader :: proc(step: int) -> bool {
	if step == 1 {
		w.destroy_shader(&swap_shader)
		w.destroy_render_texture(&sampling_rt)
		return true
	}
	swap_shader = w.load_shader(SWAP_SHADER)
	sampling_rt = w.create_render_texture(2, 1)
	w.set_texture_filter(sampling_rt.texture, .Linear)

	w.set_camera(nil)
	w.set_render_texture(sampling_rt, w.BLACK)
	w.draw_rect({0, 0, 1, 1}, {255, 0, 0, 255})
	w.draw_rect({1, 0, 1, 1}, {0, 0, 255, 255})
	w.reset_render_texture()

	w.set_shader(&swap_shader)
	w.draw_texture_rect(sampling_rt.texture, {0, 0, 2, 1}, {0, 0, 200, 20})
	w.reset_shader()
	s := snap()
	expect_color(at(s, 10, 10), {0, 0, 255, 255}, "red texel, swapped to blue", 1)
	expect_color(at(s, 80, 10), {77, 0, 178, 255}, "linear blend through the shader", 2)
	expect_color(at(s, 190, 10), {255, 0, 0, 255}, "blue texel, swapped to red", 1)
	return false
}

// More distinct textures in one frame than the bind group list once held
// (256), each drawn twice with a sampler change between.
test_many_textures :: proc(step: int) -> bool {
	N :: 300
	textures: [N]w.Texture
	for i in 0 ..< N {
		pixel := [4]u8{u8(i % 256), 0, 255, 255}
		textures[i] = w.load_texture(pixel[:], 1, 1)
	}
	defer for &tex in textures {
		w.destroy_texture(&tex)
	}
	for i in 0 ..< N {
		x, y := f32(i % 30) * 20, f32(i / 30) * 20
		w.draw_texture_rect(textures[i], {0, 0, 1, 1}, {x, y, 10, 20})
		w.set_texture_filter(textures[i], .Linear)
		w.draw_texture_rect(textures[i], {0, 0, 1, 1}, {x + 10, y, 10, 20})
	}
	s := snap()
	expect_color(at(s, 5, 10), {0, 0, 255, 255}, "first texture")
	expect_color(at(s, 29 * 20 + 15, 9 * 20 + 10), {299 % 256, 0, 255, 255}, "last texture")
	return true
}

//-----------------------//
// FRAGMENT-ONLY SHADERS //
//-----------------------//

// Only the fragment stage and a uniform; the prelude supplies VertexOutput,
// tex, tex_sampler and the vertex stage.
FRAGMENT_TINT_SHADER :: `
struct Params {
    tint: vec4<f32>,
};
@group(1) @binding(0) var<uniform> params: Params;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(tex, tex_sampler, in.texcoord) * in.color * params.tint;
}
`

fragment_tint_shader: w.Shader

test_fragment_shader_draws :: proc(step: int) -> bool {
	if step == 1 {
		w.destroy_shader(&fragment_tint_shader)
		return true
	}
	ok: bool
	fragment_tint_shader, ok = w.load_fragment_shader(FRAGMENT_TINT_SHADER)
	expect(ok, "fragment-only shader compiles")
	tex := red_blue_texture()
	defer w.destroy_texture(&tex)

	w.set_shader(&fragment_tint_shader)
	w.set_shader_uniform(&fragment_tint_shader, "tint", [4]f32{1, 0.5, 0, 1})
	w.draw_rect({0, 0, 100, 50}, w.WHITE)
	w.draw_rect({100, 0, 100, 50}, {255, 255, 255, 128}) // arrives premultiplied
	w.draw_texture_rect(tex, {0, 0, 2, 1}, {200, 0, 100, 50})
	w.reset_shader()
	w.draw_rect({300, 0, 100, 50}, w.WHITE)
	s := snap()
	expect_color(at(s, 50, 25), {255, 128, 0, 255}, "white times the tint uniform", 1)
	expect_color(at(s, 150, 25), {128, 64, 0, 255}, "premultiplied vertex colour", 1)
	expect_color(at(s, 225, 25), {255, 0, 0, 255}, "texture sampled through the prelude", 1)
	expect_color(at(s, 275, 25), {0, 0, 0, 255}, "blue texel tinted away", 1)
	expect_color(at(s, 350, 25), w.WHITE, "default shader after reset_shader")
	return false
}

// A syntax error: ok = false, no crash, and drawing with the shader falls
// back to the default shader, the same as for a full shader.
BROKEN_FRAGMENT_SHADER :: `
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return this is not wgsl;
}
`

broken_fragment: w.Shader
broken_full: w.Shader

test_fragment_shader_compile_error :: proc(step: int) -> bool {
	if step == 1 {
		w.destroy_shader(&broken_fragment)
		w.destroy_shader(&broken_full)
		return true
	}
	ok_fragment, ok_full: bool
	broken_fragment, ok_fragment = w.load_fragment_shader(BROKEN_FRAGMENT_SHADER)
	broken_full, ok_full = w.load_shader(BROKEN_FRAGMENT_SHADER)
	expect(!ok_fragment, "fragment-only shader with a syntax error reports ok = false")
	expect(!ok_full, "full shader with a syntax error reports ok = false")

	w.set_shader(&broken_fragment)
	w.draw_rect({0, 0, 100, 50}, w.RED)
	w.set_shader(&broken_full)
	w.draw_rect({100, 0, 100, 50}, w.GREEN)
	w.reset_shader()
	s := snap()
	expect_color(at(s, 50, 25), w.RED, "broken fragment-only shader draws with the default")
	expect_color(at(s, 150, 25), w.GREEN, "broken full shader draws with the default")
	return false
}

// get_frame_count is the frame being run: one more each frame, and (as this
// test program counts its own frames) equal to the number of frames so far.
frames_run: int
first_frame_count: int

test_frame_count :: proc(step: int) -> bool {
	if step == 0 {
		first_frame_count = w.get_frame_count()
		expect(first_frame_count == frames_run, "get_frame_count == frames run before this one")
	} else {
		expect(w.get_frame_count() == first_frame_count + step, "get_frame_count advances by 1")
	}
	return step == 2
}

// save_render_texture writes the texture at its own pixel size (whatever the
// window's scale) with straight alpha, like read_render_texture.
test_save_render_texture :: proc(step: int) -> bool {
	OUT :: "build/tests-render-rt.png"
	rt := w.create_render_texture(24, 8)
	defer w.destroy_render_texture(&rt)
	w.set_render_texture(rt, w.BLANK)
	w.draw_rect({0, 0, 12, 8}, w.RED)
	w.draw_rect({12, 0, 12, 8}, w.Color{0, 255, 0, 128})
	w.reset_render_texture()
	expect(w.save_render_texture(rt, OUT), "save_render_texture ok")
	expect(!w.save_render_texture(rt, "build/no-such-dir/rt.png"), "unwritable path fails")

	img, err := png.load_from_file(OUT, {.alpha_add_if_missing}, context.temp_allocator)
	expect(err == nil, "PNG loads")
	if err != nil {
		return true
	}
	defer image.destroy(img, context.temp_allocator)
	expect(img.width == 24 && img.height == 8, "PNG is the texture's size")
	expect(img.channels == 4 && img.depth == 8, "PNG is RGBA8")
	if img.width == 24 && img.height == 8 && img.channels == 4 {
		p := img.pixels[:]
		px :: proc(p: []u8, x, y: int) -> w.Color {
			i := (y * 24 + x) * 4
			return {p[i], p[i + 1], p[i + 2], p[i + 3]}
		}
		expect_color(px(p, 2, 4), w.RED, "opaque red half")
		expect_color(px(p, 20, 4), {0, 255, 0, 128}, "50% green half, straight alpha", 1)
	}
	return true
}
