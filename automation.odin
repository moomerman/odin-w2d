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
//
// Any of these fixes dt at 1/60 s, so a run is repeatable frame for frame
// (as long as the game itself does not read the wall clock or unseeded
// randomness). Frames count from 0, the first call of the frame proc.
//
// A script has one command per line, `#` starts a comment:
//
//	frame 30  screenshot start.png
//	frame 31  key Space down           # Key enum names, any case
//	frame 33  key Space up
//	frame 40  key Return tap           # down this frame, up the next
//	frame 50  mouse move 320 200       # window coordinates
//	frame 51  mouse down left          # left | right | middle
//	frame 52  mouse up left
//	frame 53  mouse click left         # down this frame, up the next
//	frame 60  scroll 0 -3
//	frame 70  resize 800 600           # headless only
//	frame 120 quit
//
// Input commands are applied before frame N's frame proc runs; a screenshot
// is frame N as drawn, taken when the game calls present; `quit` stops
// before frame N runs. A headless script with no `quit` ends after its last
// command's frame. The process exits with status 1 if the script could not
// be carried out (a screenshot that could not be saved, for instance).
// Desktop only.

import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"

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
	done:   bool,
	tried:  bool, // Screenshot: a save was attempted and failed
}

@(private = "file")
automation: struct {
	active:     bool,
	commands:   [dynamic]Command,
	frame:      int, // the frame about to run, or running
	last_frame: int, // highest frame any command refers to
	failed:     bool,
}

@(private = "package")
Automation_Config :: struct {
	headless:   bool,
	scale:      f32,
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
	if automation.active || config.headless {
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
		if command.frame != automation.frame || command.done || command.kind == .Screenshot {
			continue
		}
		command.done = true
		switch command.kind {
		case .Key:
			inject_key(command.key, command.down)
		case .Mouse_Move:
			inject_mouse_move(command.vec)
		case .Mouse_Button:
			inject_mouse_button(command.button, command.down)
		case .Scroll:
			inject_scroll(command.vec)
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
		if command.kind != .Screenshot || command.done || command.frame > automation.frame {
			continue
		}
		if save_screenshot(command.path) {
			command.done = true
			fmt.printfln("[w2d] frame %d: wrote %s", automation.frame, command.path)
		} else {
			command.tried = true
		}
	}
}

// After frame N's frame proc returns.
@(private = "package")
automation_end_frame :: proc() {
	if !automation.active {
		return
	}
	automation.frame += 1
	// Nothing would ever close a headless run whose script has finished.
	if ctx.headless && automation.frame > automation.last_frame {
		quit()
	}
}

// After shutdown: report anything the script asked for that did not happen
// and exit non-zero if so.
@(private = "package")
automation_finish :: proc() {
	if !automation.active {
		return
	}
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
					automation.frame,
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
		key, key_ok := enum_from_name_fold(Key, args[0])
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
		if len(args) == 3 && args[0] == "move" {
			x, x_ok := strconv.parse_f32(args[1])
			y, y_ok := strconv.parse_f32(args[2])
			if !x_ok || !y_ok {
				return "expected: mouse move <x> <y>"
			}
			add({frame = frame, kind = .Mouse_Move, vec = {x, y}})
			break
		}
		if len(args) < 1 || len(args) > 2 {
			return "expected: mouse move <x> <y> | mouse down|up|click [left|right|middle]"
		}
		button := Mouse_Button.Left
		if len(args) == 2 {
			button_ok: bool
			button, button_ok = enum_from_name_fold(Mouse_Button, args[1])
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
	case "scroll", "resize":
		if len(args) != 2 {
			return "expected: scroll <dx> <dy> | resize <width> <height>"
		}
		x, x_ok := strconv.parse_f32(args[0])
		y, y_ok := strconv.parse_f32(args[1])
		if !x_ok || !y_ok {
			return "expected two numbers"
		}
		if fields[2] == "resize" && (x < 1 || y < 1) {
			return "resize needs a width and height of at least 1"
		}
		add({frame = frame, kind = fields[2] == "scroll" ? .Scroll : .Resize, vec = {x, y}})
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

// Enum value whose name matches, ignoring case.
@(private = "file")
enum_from_name_fold :: proc($E: typeid, name: string) -> (value: E, ok: bool) {
	for field in reflect.enum_fields_zipped(E) {
		if strings.equal_fold(field.name, name) {
			return E(field.value), true
		}
	}
	return
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
