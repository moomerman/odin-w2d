// Record and replay test: an ordinary program (plain w.init) that logs the
// input it sees each frame. `just test` runs it twice:
//
//   record: W2D_SCRIPT=tests/replay/script.txt W2D_RECORD=build/replay-recorded.txt
//           It also feeds events through the headless window, as the OS
//           would, so the recording holds window input as well as scripted.
//   replay: W2D_SCRIPT=build/replay-recorded.txt, no window events.
//
// The two logs must be identical: the recording reproduces the input.
// `realtime` (with W2D_RECORD, no script) asks init_headless for real-time
// frames and checks that recording fixes dt at 1/60 s anyway.
//
// W2D_SCRIPT_ONLY: `plain` runs the script alone; `locked` runs it with the
// window events too, under W2D_SCRIPT_ONLY=1, and its log must match plain's.
//
//   W2D_HEADLESS=1 ... ./build/tests-replay record|replay|plain|locked <log path>
//   W2D_RECORD=... ./build/tests-replay realtime <log path>
package main

import "core:fmt"
import "core:os"
import "core:strings"

import w "../.."
import "../../backend"
import "../../core"

Mode :: enum {
	Record,
	Replay,
	Realtime,
	Plain,
	Locked,
}

mode: Mode
log: strings.Builder
failures: int

// Keys the log reports on: one of each kind of name.
KEYS :: [?]w.Key{.Space, .Left_Shift, .Key_1, .Return, .Z}

main :: proc() {
	if len(os.args) != 3 {
		fmt.eprintln("usage: tests-replay record|replay|realtime|plain|locked <log> (just test)")
		os.exit(2)
	}
	switch os.args[1] {
	case "record":
		mode = .Record
	case "replay":
		mode = .Replay
	case "realtime":
		mode = .Realtime
	case "plain":
		mode = .Plain
	case "locked":
		mode = .Locked
	case:
		fmt.eprintln("mode must be record, replay, realtime, plain or locked")
		os.exit(2)
	}

	if mode == .Realtime {
		w.init_headless(320, 200, frame_time = 0)
	} else {
		w.init(320, 200, "Replay Test")
	}
	w.run(init, frame, shutdown)
	fmt.sbprintfln(&log, "ran %d frames", w.get_frame_count())

	if err := os.write_entire_file(os.args[2], log.buf[:]); err != nil {
		fmt.eprintfln("cannot write %s: %v", os.args[2], err)
		os.exit(2)
	}
	if mode == .Replay {
		check_recording(os.get_env("W2D_SCRIPT", context.temp_allocator))
	}
	if failures > 0 {
		fmt.printfln("FAILED replay (%v)", mode)
		os.exit(1)
	}
	fmt.printfln("ok (replay: %v)", mode)
}

check :: proc(ok: bool, what: string) {
	if !ok {
		failures += 1
		fmt.printfln("  FAIL frame %d: %s", w.get_frame_count(), what)
	}
}

init :: proc() {}

shutdown :: proc() {}

frame :: proc(dt: f32) {
	n := w.get_frame_count()
	if mode == .Realtime {
		if n > 0 {
			check(dt == 1.0 / 60.0, "W2D_RECORD fixes dt at 1/60 s")
		}
		if n == 3 {
			w.quit()
		}
	}
	if mode == .Record || mode == .Locked {
		push_window_events(n + 1)
	}
	if mode == .Record {
		check_live(n) // window and scripted input mix
	}

	fmt.sbprintf(&log, "%d:", n)
	for key in KEYS {
		if w.key_went_down(key) do fmt.sbprintf(&log, " %v+", key)
		if w.key_went_up(key) do fmt.sbprintf(&log, " %v-", key)
		if w.key_is_held(key) do fmt.sbprintf(&log, " %v", key)
	}
	for button in w.Mouse_Button {
		if w.mouse_button_went_down(button) do fmt.sbprintf(&log, " %v+", button)
		if w.mouse_button_went_up(button) do fmt.sbprintf(&log, " %v-", button)
		if w.mouse_button_is_held(button) do fmt.sbprintf(&log, " %v", button)
	}
	fmt.sbprintfln(
		&log,
		" pos=%v delta=%v scroll=%v/%v",
		w.get_mouse_position(),
		w.get_mouse_delta(),
		w.get_scroll_delta(),
		w.get_scroll_delta(include_momentum = false),
	)

	w.clear(w.BLACK)
	w.present()
}

// Window events, as the OS would deliver them, arriving at frame `next`.
push_window_events :: proc(next: int) {
	push :: backend.headless_push_event
	switch next {
	case 20:
		push(core.Key_Event{key = .Z, down = true})
	case 21:
		push(core.Key_Event{key = .Z, down = true, repeat = true}) // not a new press
	case 22:
		push(core.Key_Event{key = .Z, down = false})
	case 23:
		// A press away from the pointer, with no move before it.
		push(core.Mouse_Button_Event{button = .Middle, down = true, pos = {50, 60}})
	case 24:
		push(core.Mouse_Button_Event{button = .Middle, down = false, pos = {50, 60}})
	case 25:
		push(core.Mouse_Move_Event{pos = {60, 70}, delta = {10, 10}})
		push(core.Mouse_Move_Event{pos = {70, 80}, delta = {10, 10}})
		push(core.Mouse_Scroll_Event{delta = {0, -2}, pos = {70, 80}, momentum = true})
		push(core.Mouse_Scroll_Event{delta = {0, -1}, pos = {70, 80}})
	}
}

// The live run saw what the script and the window events describe (so the
// log the replay must match is not trivially empty).
check_live :: proc(n: int) {
	switch n {
	case 2:
		check(w.key_went_down(.Space), "Space went down")
	case 5:
		check(w.key_went_down(.Left_Shift), "Left_Shift tap")
	case 7:
		check(w.key_is_held(.Key_1) && w.key_is_held(.Return), "Key_1 and Return held")
	case 10:
		check(w.get_mouse_position() == w.Vec2{30.5, 40.25}, "second move of the frame wins")
	case 14:
		check(w.mouse_button_went_down(.Right), "right click at 14")
		check(w.get_mouse_position() == w.Vec2{200, 100}, "right click at 200,100")
	case 16:
		check(w.get_scroll_delta() == w.Vec2{1, -1}, "two scrolls in a frame add up")
	case 17:
		check(w.get_scroll_delta() == w.Vec2{0, 4}, "momentum scroll")
		check(w.get_scroll_delta(false) == w.Vec2{}, "momentum scroll left out")
	case 18:
		check(w.get_mouse_delta() == w.Vec2{5, -5}, "scripted delta without a move")
	case 20:
		check(w.key_went_down(.Z), "window key Z went down")
	case 21:
		check(!w.key_went_down(.Z) && w.key_is_held(.Z), "Z repeat is not a new press")
	case 23:
		check(w.mouse_button_went_down(.Middle), "window middle button went down")
		check(w.get_mouse_position() == w.Vec2{50, 60}, "button press moves the pointer")
		check(w.get_mouse_delta() == w.Vec2{}, "a press reports no motion")
	case 25:
		check(w.get_mouse_delta() == w.Vec2{20, 20}, "window moves add up")
		check(w.get_scroll_delta() == w.Vec2{0, -3}, "window scroll with momentum")
		check(w.get_scroll_delta(false) == w.Vec2{0, -1}, "window scroll without momentum")
	}
}

// The recording collapses each frame's moves and ends with quit.
check_recording :: proc(path: string) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		check(false, "read the recording")
		return
	}
	defer delete(data)
	text := string(data)
	check(strings.count(text, "frame 10 mouse move") == 1, "one move line for frame 10")
	check(strings.count(text, "frame 25 mouse move") == 1, "one move line for frame 25")
	check(strings.count(text, "frame 21 key") == 0, "no line for the key repeat")
	check(strings.has_suffix(text, "frame 30 quit\n"), "ends with quit at frame 30")
}
