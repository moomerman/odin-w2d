// Automation test: an ordinary windowed program (plain w.init, no test hooks)
// driven from outside by the W2D_* environment variables. It records what the
// script in script.txt made it see and checks that after the run.
//
//   W2D_HEADLESS=1 W2D_SCRIPT=tests/automation/script.txt odin run tests/automation
//   (or: just test)
package main

import "core:fmt"
import "core:os"

import w "../.."

frames: int
space_down_frame := -1
space_up_frame := -1
click_frame := -1
click_pos: w.Vec2
scroll_frame := -1
size_at_25: [2]int
dt_ok := true
frame_count_ok := true

main :: proc() {
	if os.get_env("W2D_SCRIPT", context.temp_allocator) == "" {
		fmt.eprintln(
			"run with W2D_HEADLESS=1 W2D_SCRIPT=tests/automation/script.txt (or: just test)",
		)
		os.exit(2)
	}
	w.init(640, 360, "Automation Test")
	w.run(init, frame, shutdown)

	failures := 0
	check :: proc(failures: ^int, ok: bool, what: string, got: any) {
		if !ok {
			failures^ += 1
			fmt.printfln("  FAIL %s (got %v)", what, got)
		}
	}
	check(&failures, frames == 30, "quit before frame 30", frames)
	check(&failures, space_down_frame == 5, "Space went down on frame 5", space_down_frame)
	check(&failures, space_up_frame == 6, "Space tap released on frame 6", space_up_frame)
	check(&failures, click_frame == 12, "left click on frame 12", click_frame)
	check(&failures, click_pos == w.Vec2{100, 50}, "click at 100,50", click_pos)
	check(&failures, scroll_frame == 15, "scroll on frame 15", scroll_frame)
	check(&failures, size_at_25 == [2]int{320, 200}, "resized to 320x200 by frame 25", size_at_25)
	check(&failures, dt_ok, "dt is 1/60 on every frame after the first", dt_ok)
	check(&failures, frame_count_ok, "get_frame_count is the frame being run", frame_count_ok)
	check(
		&failures,
		w.get_frame_count() == 30,
		"get_frame_count after the run",
		w.get_frame_count(),
	)
	if failures > 0 {
		fmt.println("FAILED automation")
		os.exit(1)
	}
	fmt.println("ok (automation)")
}

init :: proc() {}

frame :: proc(dt: f32) {
	if frames > 0 && dt != 1.0 / 60.0 {
		dt_ok = false
	}
	if w.get_frame_count() != frames {
		frame_count_ok = false
	}
	// get_frame_count is the number the script's `frame N` lines use.
	n := w.get_frame_count()
	if w.key_went_down(.Space) do space_down_frame = n
	if w.key_went_up(.Space) do space_up_frame = n
	if w.mouse_button_went_down(.Left) {
		click_frame = n
		click_pos = w.get_mouse_position()
	}
	if w.get_scroll_delta() == (w.Vec2{0, -3}) do scroll_frame = n
	if frames == 25 {
		sw, sh := w.get_screen_size()
		size_at_25 = {sw, sh}
	}

	w.clear(w.DARK_BLUE)
	w.draw_rect({20, 20, 100, 100}, w.key_is_held(.A) ? w.GREEN : w.RED)
	w.present()
	frames += 1
}

shutdown :: proc() {}
