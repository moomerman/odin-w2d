#+build !js
package engine

// Automation: run any game unattended, from outside, with no code changes.
//
// `init` reads a few environment variables. With them a game can run with no
// window, at a fixed timestep, play back scripted input, save screenshots at
// chosen frames and exit — so a test, a CI job or an AI agent can see what a
// change did:
//
//	W2D_HEADLESS=1 W2D_FRAMES=60 W2D_SCREENSHOT=out.png odin run mygame
//	W2D_HEADLESS=1 W2D_SCRIPT=smoke.txt odin run mygame
//
//	W2D_HEADLESS=1     no window (as init_headless); audio is muted
//	W2D_SCALE=2        headless only: simulated HiDPI scale (default 1)
//	W2D_SCRIPT=path    play a script (below); works windowed too
//	W2D_FRAMES=n       quit before frame n (after n frames have run)
//	W2D_SCREENSHOT=p   with W2D_FRAMES: save the last frame to p
//	W2D_RECORD=path    write the input the game receives as a script
//
// Any of these fixes dt at 1/60 s, so a run is repeatable frame for frame
// (as long as the game itself does not read the wall clock or unseeded
// randomness). Frames count from 0, the first call of the frame proc; the
// game sees the same number from get_frame_count.
//
// A script has one command per line, `#` starts a comment:
//
//	frame 30  screenshot start.png
//	frame 31  key Space down           # Key enum names, any case
//	frame 33  key Space up
//	frame 40  key Return tap           # down this frame, up the next
//	frame 50  mouse move 320 200       # window coordinates
//	frame 51  mouse move 320 200 4 0   # with the delta to report (default:
//	                                   # the distance from the last position)
//	frame 51  mouse down left          # left | right | middle
//	frame 52  mouse up left
//	frame 53  mouse click left         # down this frame, up the next
//	frame 60  scroll 0 -3
//	frame 61  scroll 0 -1 momentum     # as OS inertia scrolling
//	frame 70  resize 800 600           # headless only
//	frame 120 quit
//
// Input commands are applied before frame N's frame proc runs; a screenshot
// is frame N as drawn, taken when the game calls present; `quit` stops
// before frame N runs. A headless script with no `quit` ends after its last
// command's frame. The process exits with status 1 if the script could not
// be carried out (a screenshot that could not be saved, for instance).
// Desktop only.
//
// W2D_RECORD writes every input event the game receives (from the window and
// from inject_*, including a W2D_SCRIPT's) as script lines, so W2D_SCRIPT on
// the file replays the session. Each frame's lines are written when its
// input is processed, so a crash keeps what came before; the file ends with
// `quit` at the frame the run stopped. Recording fixes dt at 1/60 s even in
// a window, so the replay sees the same frame times. Per frame, mouse
// motion becomes one `mouse move` to the final position, with the frame's
// total delta when that is not simply the change in position (relative
// motion, a press away from the pointer), and scrolling one `scroll` line
// with and one without momentum; key repeats, which only re-report a held key, are left
// out. Resizes are not input and are not recorded.

import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"

import "core"

@(private = "file")
AUTOMATION_FRAME_TIME :: 1.0 / 60.0

@(private = "file")
Command_Kind :: enum {
	Screenshot,
	Key,
	Mouse_Move,
	Mouse_Button,
	Scroll,
	Resize,
	Quit,
}

@(private = "file")
Command :: struct {
	frame:  int,
	kind:   Command_Kind,
	path:   string, // Screenshot (owned)
	key:    Key,
	button: Mouse_Button,
	down:   bool,
	vec:    Vec2, // Mouse_Move position, Scroll delta, Resize size
	delta:  Vec2, // Mouse_Move, when flag is set
	flag:   bool, // Mouse_Move: delta given; Scroll: momentum
	done:   bool,
	tried:  bool, // Screenshot: a save was attempted and failed
}

@(private = "file")
automation: struct {
	active:     bool,
	commands:   [dynamic]Command,
	last_frame: int, // highest frame any command refers to
	failed:     bool,
}

@(private = "package")
Automation_Config :: struct {
	headless:   bool,
	scale:      f32,
	record:     bool, // W2D_RECORD is set: the timestep must be fixed
	frame_time: f32, // > 0 when the run should use a fixed timestep
}

// Read the W2D_* environment variables and load the script, if any. Called
// from init before the backends are created.
@(private = "package")
automation_configure :: proc() -> (config: Automation_Config) {
	config.scale = 1
	config.headless = env_flag("W2D_HEADLESS")
	if value, found := env("W2D_SCALE"); found {
		if scale, ok := strconv.parse_f32(value); ok && scale > 0 {
			config.scale = scale
		} else {
			automation_fatal("W2D_SCALE=%q is not a positive number", value)
		}
		delete(value)
	}

	if path, found := env("W2D_SCRIPT"); found {
		automation_load_script(path)
		delete(path)
		automation.active = true
	}

	if value, found := env("W2D_FRAMES"); found {
		frames, ok := strconv.parse_int(value)
		if !ok || frames < 1 {
			automation_fatal("W2D_FRAMES=%q is not a positive whole number", value)
		}
		delete(value)
		if shot, has_shot := env("W2D_SCREENSHOT"); has_shot {
			append(
				&automation.commands,
				Command{frame = frames - 1, kind = .Screenshot, path = shot},
			)
		}
		append(&automation.commands, Command{frame = frames, kind = .Quit})
		automation.active = true
	}

	for command in automation.commands {
		automation.last_frame = max(automation.last_frame, command.frame)
	}

	if path, found := env("W2D_RECORD"); found {
		file, err := os.create(path)
		if err != nil {
			automation_fatal("cannot create W2D_RECORD %q: %v", path, err)
		}
		delete(path)
		recorder.file = file
		config.record = true
		record_write("# w2d input recording (W2D_RECORD); replay with W2D_SCRIPT=<this file>\n")
	}

	// A recording replays faithfully only if the game saw the same frame times.
	if automation.active || config.headless || recorder.file != nil {
		config.frame_time = AUTOMATION_FRAME_TIME
	}
	if config.headless && !automation.active {
		fmt.eprintln(
			"[w2d] W2D_HEADLESS is set with no W2D_SCRIPT or W2D_FRAMES: the game will run unseen until it quits itself",
		)
	}
	return
}

// Before frame N's input is processed: apply that frame's input commands,
// resizes and quit.
@(private = "package")
automation_begin_frame :: proc() {
	if !automation.active {
		return
	}
	for &command in automation.commands {
		if command.frame != ctx.frame_count || command.done || command.kind == .Screenshot {
			continue
		}
		command.done = true
		switch command.kind {
		case .Key:
			inject_key(command.key, command.down)
		case .Mouse_Move:
			if command.flag {
				inject_mouse_move_delta(command.vec, command.delta)
			} else {
				inject_mouse_move(command.vec)
			}
		case .Mouse_Button:
			inject_mouse_button(command.button, command.down)
		case .Scroll:
			inject_scroll(command.vec, command.flag)
		case .Resize:
			if ctx.headless {
				set_headless_size(int(command.vec.x), int(command.vec.y))
			} else {
				fmt.eprintfln("[w2d] frame %d: resize needs W2D_HEADLESS=1", command.frame)
				automation.failed = true
			}
		case .Quit:
			quit()
		case .Screenshot:
		}
	}
}

// From present(), before the frame is submitted: take this frame's
// screenshots. A frame that could not be read (a lost surface in windowed
// mode) leaves the command pending for the next frame.
@(private = "package")
automation_present :: proc() {
	if !automation.active {
		return
	}
	for &command in automation.commands {
		if command.kind != .Screenshot || command.done || command.frame > ctx.frame_count {
			continue
		}
		if save_screenshot(command.path) {
			command.done = true
			fmt.printfln("[w2d] frame %d: wrote %s", ctx.frame_count, command.path)
		} else {
			command.tried = true
		}
	}
}

// After frame N's frame proc returns and ctx.frame_count has moved on to N+1.
@(private = "package")
automation_end_frame :: proc() {
	if !automation.active {
		return
	}
	// Nothing would ever close a headless run whose script has finished.
	if ctx.headless && ctx.frame_count > automation.last_frame {
		quit()
	}
}

// After shutdown: report anything the script asked for that did not happen
// and exit non-zero if so.
@(private = "package")
automation_finish :: proc() {
	record_finish()
	for command in automation.commands {
		if command.kind == .Screenshot && !command.done {
			if command.tried {
				fmt.eprintfln(
					"[w2d] screenshot %s (frame %d) could not be saved: check the path is writable",
					command.path,
					command.frame,
				)
			} else {
				fmt.eprintfln(
					"[w2d] screenshot %s (frame %d) was never taken: the run ended at frame %d, or the game did not call present",
					command.path,
					command.frame,
					ctx.frame_count,
				)
			}
			automation.failed = true
		}
		delete(command.path)
	}
	delete(automation.commands)
	failed := automation.failed
	automation = {}
	if failed {
		os.exit(1)
	}
}

//--------//
// SCRIPT //
//--------//

@(private = "file")
automation_load_script :: proc(path: string) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		automation_fatal("cannot read W2D_SCRIPT %q: %v", path, err)
	}
	defer delete(data)

	text := string(data)
	line_no := 0
	for line in strings.split_lines_iterator(&text) {
		line_no += 1
		content := line
		if hash := strings.index_byte(content, '#'); hash >= 0 {
			content = content[:hash]
		}
		fields := strings.fields(content)
		defer delete(fields)
		if len(fields) == 0 {
			continue
		}
		if message := automation_parse_line(fields); message != "" {
			automation_fatal("%s:%d: %s\n    %s", path, line_no, message, strings.trim_space(line))
		}
	}
}

// Parse one script line into commands. Returns "" or what is wrong with it.
@(private = "file")
automation_parse_line :: proc(fields: []string) -> string {
	if len(fields) < 3 || fields[0] != "frame" {
		return "expected: frame <n> <command> ..."
	}
	frame, frame_ok := strconv.parse_int(fields[1])
	if !frame_ok || frame < 0 {
		return "frame number must be a whole number, 0 or more"
	}
	args := fields[3:]
	add :: proc(command: Command) {
		append(&automation.commands, command)
	}

	switch fields[2] {
	case "screenshot":
		if len(args) != 1 {
			return "expected: screenshot <path.png>"
		}
		add({frame = frame, kind = .Screenshot, path = strings.clone(args[0])})
	case "key":
		if len(args) != 2 {
			return "expected: key <Name> down|up|tap"
		}
		key, key_ok := script_value(Key, args[0])
		if !key_ok {
			return "unknown key name (use the Key enum's names, e.g. Space, A, Left_Shift, Key_1)"
		}
		switch args[1] {
		case "down", "up":
			add({frame = frame, kind = .Key, key = key, down = args[1] == "down"})
		case "tap":
			add({frame = frame, kind = .Key, key = key, down = true})
			add({frame = frame + 1, kind = .Key, key = key, down = false})
		case:
			return "expected: key <Name> down|up|tap"
		}
	case "mouse":
		if len(args) > 0 && args[0] == "move" {
			numbers: [4]f32
			if len(args) != 3 && len(args) != 5 {
				return "expected: mouse move <x> <y> [<dx> <dy>]"
			}
			for arg, i in args[1:] {
				ok: bool
				if numbers[i], ok = strconv.parse_f32(arg); !ok {
					return "expected: mouse move <x> <y> [<dx> <dy>]"
				}
			}
			add(
				{
					frame = frame,
					kind = .Mouse_Move,
					vec = numbers.xy,
					delta = numbers.zw,
					flag = len(args) == 5,
				},
			)
			break
		}
		if len(args) < 1 || len(args) > 2 {
			return "expected: mouse move <x> <y> | mouse down|up|click [left|right|middle]"
		}
		button := Mouse_Button.Left
		if len(args) == 2 {
			button_ok: bool
			button, button_ok = script_value(Mouse_Button, args[1])
			if !button_ok {
				return "unknown mouse button (left, right or middle)"
			}
		}
		switch args[0] {
		case "down", "up":
			add({frame = frame, kind = .Mouse_Button, button = button, down = args[0] == "down"})
		case "click":
			add({frame = frame, kind = .Mouse_Button, button = button, down = true})
			add({frame = frame + 1, kind = .Mouse_Button, button = button, down = false})
		case:
			return "expected: mouse move <x> <y> | mouse down|up|click [left|right|middle]"
		}
	case "scroll":
		momentum := len(args) == 3 && args[2] == "momentum"
		if len(args) != 2 && !momentum {
			return "expected: scroll <dx> <dy> [momentum]"
		}
		x, x_ok := strconv.parse_f32(args[0])
		y, y_ok := strconv.parse_f32(args[1])
		if !x_ok || !y_ok {
			return "expected: scroll <dx> <dy> [momentum]"
		}
		add({frame = frame, kind = .Scroll, vec = {x, y}, flag = momentum})
	case "resize":
		if len(args) != 2 {
			return "expected: resize <width> <height>"
		}
		x, x_ok := strconv.parse_f32(args[0])
		y, y_ok := strconv.parse_f32(args[1])
		if !x_ok || !y_ok || x < 1 || y < 1 {
			return "resize needs a width and height of at least 1"
		}
		add({frame = frame, kind = .Resize, vec = {x, y}})
	case "quit":
		if len(args) != 0 {
			return "quit takes no arguments"
		}
		add({frame = frame, kind = .Quit})
	case:
		return "unknown command (screenshot, key, mouse, scroll, resize, quit)"
	}
	return ""
}

// Key and mouse button names in scripts are the enum's own field names
// (reflect.enum_fields_zipped), any case when read. The parser and the
// recorder both use this one table, so every name the recorder writes reads
// back as the same value.
@(private = "file")
script_value :: proc($E: typeid, name: string) -> (value: E, ok: bool) {
	for field in reflect.enum_fields_zipped(E) {
		if strings.equal_fold(field.name, name) {
			return E(field.value), true
		}
	}
	return
}

@(private = "file")
script_name :: proc(value: $E) -> string {
	for field in reflect.enum_fields_zipped(E) {
		if E(field.value) == value {
			return field.name
		}
	}
	return "?"
}

//-----------//
// RECORDING //
//-----------//

@(private = "file")
recorder: struct {
	file:            ^os.File,
	lines:           strings.Builder, // this frame's key and button lines, in order
	scroll:          Vec2, // this frame's scrolling without momentum
	scroll_momentum: Vec2, // and with
	mouse_pos:       Vec2, // pointer position as of the last line written
}

// From process_input, for each event applied this frame.
@(private = "package")
automation_record_event :: proc(event: core.Event) {
	if recorder.file == nil {
		return
	}
	b := &recorder.lines
	switch e in event {
	case core.Mouse_Move_Event: // collapsed to one line per frame by automation_record_frame
	case core.Mouse_Button_Event:
		fmt.sbprintfln(
			b,
			"frame %d mouse %s %s",
			ctx.frame_count,
			e.down ? "down" : "up",
			script_name(e.button),
		)
	case core.Mouse_Scroll_Event:
		if e.momentum {
			recorder.scroll_momentum += e.delta
		} else {
			recorder.scroll += e.delta
		}
	case core.Key_Event:
		if !e.repeat {
			fmt.sbprintfln(
				b,
				"frame %d key %s %s",
				ctx.frame_count,
				script_name(e.key),
				e.down ? "down" : "up",
			)
		}
	}
}

// From process_input once this frame's events are applied: write its lines.
// The pointer move goes first so buttons replay at the frame's final position.
@(private = "package")
automation_record_frame :: proc() {
	if recorder.file == nil {
		return
	}
	frame := ctx.frame_count
	head: strings.Builder
	defer strings.builder_destroy(&head)
	if input.mouse_pos != recorder.mouse_pos || input.mouse_delta != {} {
		pos, delta := input.mouse_pos, input.mouse_delta
		fmt.sbprintf(&head, "frame %d mouse move %v %v", frame, pos.x, pos.y)
		if delta != pos - recorder.mouse_pos {
			fmt.sbprintf(&head, " %v %v", delta.x, delta.y)
		}
		strings.write_byte(&head, '\n')
		recorder.mouse_pos = pos
	}
	strings.write_string(&head, strings.to_string(recorder.lines))
	if recorder.scroll != {} {
		fmt.sbprintfln(&head, "frame %d scroll %v %v", frame, recorder.scroll.x, recorder.scroll.y)
	}
	if recorder.scroll_momentum != {} {
		fmt.sbprintfln(
			&head,
			"frame %d scroll %v %v momentum",
			frame,
			recorder.scroll_momentum.x,
			recorder.scroll_momentum.y,
		)
	}
	strings.builder_reset(&recorder.lines)
	recorder.scroll, recorder.scroll_momentum = {}, {}
	if len(head.buf) > 0 {
		record_write(strings.to_string(head))
	}
}

// End the recording with `quit` at the frame the run stopped before.
@(private = "file")
record_finish :: proc() {
	if recorder.file == nil {
		return
	}
	record_write(fmt.tprintf("frame %d quit\n", ctx.frame_count))
	os.close(recorder.file)
	strings.builder_destroy(&recorder.lines)
	recorder = {}
}

// Written and flushed straight away, so a crash keeps what was recorded.
@(private = "file")
record_write :: proc(text: string) {
	if _, err := os.write_string(recorder.file, text); err != nil {
		fmt.eprintfln("[w2d] W2D_RECORD: write failed: %v", err)
		automation.failed = true
		return
	}
	os.flush(recorder.file)
}

@(private = "file")
env :: proc(key: string) -> (value: string, found: bool) {
	value, found = os.lookup_env(key, context.allocator)
	if found && value == "" {
		delete(value)
		return "", false
	}
	return
}

@(private = "file")
env_flag :: proc(key: string) -> bool {
	value, found := env(key)
	defer delete(value)
	return found && value != "0" && !strings.equal_fold(value, "false")
}

// A bad automation setup must not silently run the game for real.
@(private = "file")
automation_fatal :: proc(format: string, args: ..any) -> ! {
	fmt.eprint("[w2d] ")
	fmt.eprintfln(format, ..args)
	os.exit(2)
}
