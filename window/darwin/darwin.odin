#+build darwin
#+build !js
// Native macOS window backend using Cocoa APIs directly.
// Avoids SDL3's event handling which causes ~500ms mouse click delays
// when window managers like Magnet are running.

package window_darwin

import "base:intrinsics"
import "base:runtime"

import NS "core:sys/darwin/Foundation"
import CA "vendor:darwin/QuartzCore"
import "vendor:wgpu"

import core "../../core"

@(private = "file")
app: ^NS.Application

@(private = "file")
window: ^NS.Window

@(private = "file")
metal_layer: ^CA.MetalLayer

@(private = "file")
events: [dynamic]core.Event

@(private = "file")
should_quit: bool

@(private = "file")
on_resize: proc()

@(private = "file")
screen_width: int

@(private = "file")
screen_height: int

@(private = "file")
prev_modifier_flags: NS.EventModifierFlags

@(private = "file")
odin_ctx: runtime.Context

@(private = "file")
cursor_hidden: bool

@(private = "file")
current_custom_cursor: ^NS.Cursor

backend :: proc() -> core.Window_Backend {
	return core.Window_Backend {
		init = native_init,
		shutdown = native_shutdown,
		poll_events = native_poll_events,
		get_surface = native_get_surface,
		get_framebuffer_size = native_get_framebuffer_size,
		get_events = native_get_events,
		set_cursor_visible = native_set_cursor_visible,
		set_system_cursor = native_set_system_cursor,
		set_custom_cursor = native_set_custom_cursor,
	}
}

@(private = "file")
native_init :: proc(width, height: int, title: string, resize_cb: proc()) {
	on_resize = resize_cb
	screen_width = width
	screen_height = height
	odin_ctx = context

	app = NS.Application_sharedApplication()
	app->setActivationPolicy(.Regular)

	NS.scoped_autoreleasepool()

	// Menu bar with Quit (Cmd+Q)
	menu_bar := NS.Menu_alloc()->init()
	app->setMainMenu(menu_bar)
	app_menu_item := menu_bar->addItemWithTitle(NS.AT(""), nil, NS.AT(""))

	app_menu := NS.Menu_alloc()->init()
	app_menu->addItemWithTitle(
		NS.AT("Quit"),
		NS.sel_registerName(cstring("terminate:")),
		NS.AT("q"),
	)
	app_menu_item->setSubmenu(app_menu)
	app->setAppleMenu(app_menu)

	// Create window
	rect := NS.Rect {
		origin = {0, 0},
		size   = {NS.Float(width), NS.Float(height)},
	}

	style :=
		NS.WindowStyleMaskTitled |
		NS.WindowStyleMaskClosable |
		NS.WindowStyleMaskMiniaturizable |
		NS.WindowStyleMaskResizable
	window = NS.Window_alloc()->initWithContentRect(rect, style, .Buffered, false)

	title_str := NS.String_alloc()->initWithOdinString(title)
	window->setTitle(title_str)

	window->center()
	window->setAcceptsMouseMovedEvents(true)

	// Create Metal layer for wgpu surface
	metal_layer = CA.MetalLayer_layer()
	view := window->contentView()
	view->setWantsLayer(true)
	view->setLayer(metal_layer)

	window->makeKeyAndOrderFront(nil)

	// Application delegate — prevents terminate: from hard-killing the process.
	app_delegate := NS.application_delegate_register_and_alloc(NS.ApplicationDelegateTemplate {
			applicationShouldTerminate = proc(_: ^NS.Application) -> NS.ApplicationTerminateReply {
				should_quit = true
				return .TerminateCancel
			},
		}, "NativeDarwinApplicationDelegate", odin_ctx)
	app->setDelegate(app_delegate)

	// Window delegate — proper close and resize handling.
	win_delegate := NS.window_delegate_register_and_alloc(NS.WindowDelegateTemplate {
			windowShouldClose = proc(_: ^NS.Window) -> bool {
				should_quit = true
				return false
			},
			windowDidResize = proc(_: ^NS.Notification) {
				context = odin_ctx
				content_rect := window->contentLayoutRect()
				new_w := int(content_rect.size.width)
				new_h := int(content_rect.size.height)
				if new_w != screen_width || new_h != screen_height {
					screen_width = new_w
					screen_height = new_h
					if on_resize != nil {
						on_resize()
					}
				}
			},
		}, "NativeDarwinWindowDelegate", odin_ctx)
	window->setDelegate(win_delegate)

	app->activateIgnoringOtherApps(true)
	app->finishLaunching()

	should_quit = false
}

@(private = "file")
native_shutdown :: proc() {
	delete(events)
	if window != nil {
		window->close()
		window = nil
	}
}

@(private = "file")
native_poll_events :: proc() -> bool {
	for {
		event := app->nextEventMatchingMask(NS.EventMaskAny, nil, NS.DefaultRunLoopMode, true)

		if event == nil {
			break
		}

		event_type := event->type()

		#partial switch event_type {
		case .KeyDown:
			key := key_from_macos_keycode(event->keyCode())
			if key != nil {
				append(
					&events,
					core.Event(
						core.Key_Event{key = key.?, down = true, repeat = event->isARepeat()},
					),
				)
			}

		case .KeyUp:
			key := key_from_macos_keycode(event->keyCode())
			if key != nil {
				append(
					&events,
					core.Event(core.Key_Event{key = key.?, down = false, repeat = false}),
				)
			}

		case .FlagsChanged:
			// Modifier keys (Shift, Ctrl, Alt, Cmd) generate FlagsChanged,
			// not KeyDown/KeyUp. Detect which modifier changed by comparing
			// with previous flags.
			new_flags := event->modifierFlags()
			handle_modifier_change(.Shift, .Left_Shift, new_flags)
			handle_modifier_change(.Control, .Left_Ctrl, new_flags)
			handle_modifier_change(.Option, .Left_Alt, new_flags)
			handle_modifier_change(.Command, .Left_Super, new_flags)
			prev_modifier_flags = new_flags

		case .LeftMouseDown:
			pos := mouse_pos_from_event(event)
			append(
				&events,
				core.Event(core.Mouse_Button_Event{button = .Left, down = true, pos = pos}),
			)

		case .LeftMouseUp:
			pos := mouse_pos_from_event(event)
			append(
				&events,
				core.Event(core.Mouse_Button_Event{button = .Left, down = false, pos = pos}),
			)

		case .RightMouseDown:
			pos := mouse_pos_from_event(event)
			append(
				&events,
				core.Event(core.Mouse_Button_Event{button = .Right, down = true, pos = pos}),
			)

		case .RightMouseUp:
			pos := mouse_pos_from_event(event)
			append(
				&events,
				core.Event(core.Mouse_Button_Event{button = .Right, down = false, pos = pos}),
			)

		case .OtherMouseDown:
			pos := mouse_pos_from_event(event)
			append(
				&events,
				core.Event(core.Mouse_Button_Event{button = .Middle, down = true, pos = pos}),
			)

		case .OtherMouseUp:
			pos := mouse_pos_from_event(event)
			append(
				&events,
				core.Event(core.Mouse_Button_Event{button = .Middle, down = false, pos = pos}),
			)

		case .MouseMoved, .LeftMouseDragged, .RightMouseDragged, .OtherMouseDragged:
			pos := mouse_pos_from_event(event)
			delta := core.Vec2{f32(event->deltaX()), f32(event->deltaY())}
			append(&events, core.Event(core.Mouse_Move_Event{pos = pos, delta = delta}))
		}

		// Forward non-key events to application for default handling.
		// For key events, only forward if Cmd/Ctrl is held (for Cmd+Q etc).
		// Otherwise regular key presses cause system beeps.
		is_key_event := event_type == .KeyDown || event_type == .KeyUp
		if is_key_event {
			mods := event->modifierFlags()
			has_cmd_or_ctrl := mods & {.Command, .Control} != {}
			if has_cmd_or_ctrl {
				app->sendEvent(event)
			}
		} else {
			app->sendEvent(event)
		}
	}

	return !should_quit
}

@(private = "file")
native_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor {
			nextInChain = &wgpu.SurfaceSourceMetalLayer {
				chain = wgpu.ChainedStruct{sType = .SurfaceSourceMetalLayer},
				layer = metal_layer,
			},
		},
	)
}

@(private = "file")
native_get_framebuffer_size :: proc() -> (width: u32, height: u32) {
	view := window->contentView()
	bounds := view->bounds()
	scale := f64(window->backingScaleFactor())
	return u32(f64(bounds.size.width) * scale), u32(f64(bounds.size.height) * scale)
}

@(private = "file")
native_get_events :: proc() -> []core.Event {
	result := events[:]
	clear(&events)
	return result
}

@(private = "file")
native_set_cursor_visible :: proc(visible: bool) {
	if visible && cursor_hidden {
		NS.Cursor_unhide()
		cursor_hidden = false
	} else if !visible && !cursor_hidden {
		NS.Cursor_hide()
		cursor_hidden = true
	}
}

@(private = "file")
native_set_system_cursor :: proc(cursor: core.System_Cursor) {
	ns_cursor: ^NS.Cursor
	switch cursor {
	case .Default:
		ns_cursor = NS.Cursor_arrowCursor()
	case .Text:
		ns_cursor = NS.Cursor_IBeamCursor()
	case .Pointer:
		ns_cursor = NS.Cursor_pointingHandCursor()
	case .Crosshair:
		ns_cursor = intrinsics.objc_send(^NS.Cursor, NS.Cursor, "crosshairCursor")
	case .Resize_EW:
		ns_cursor = intrinsics.objc_send(^NS.Cursor, NS.Cursor, "resizeLeftRightCursor")
	case .Resize_NS:
		ns_cursor = intrinsics.objc_send(^NS.Cursor, NS.Cursor, "resizeUpDownCursor")
	case .Resize_NWSE:
		// Private Apple selector; falls back to arrow if unavailable.
		ns_cursor = intrinsics.objc_send(^NS.Cursor, NS.Cursor, "_windowResizeNorthWestSouthEastCursor")
		if ns_cursor == nil do ns_cursor = NS.Cursor_arrowCursor()
	case .Resize_NESW:
		ns_cursor = intrinsics.objc_send(^NS.Cursor, NS.Cursor, "_windowResizeNorthEastSouthWestCursor")
		if ns_cursor == nil do ns_cursor = NS.Cursor_arrowCursor()
	case .Move:
		ns_cursor = intrinsics.objc_send(^NS.Cursor, NS.Cursor, "openHandCursor")
	case .Not_Allowed:
		ns_cursor = intrinsics.objc_send(^NS.Cursor, NS.Cursor, "operationNotAllowedCursor")
	}
	if ns_cursor != nil {
		ns_cursor->set()
	}
}

@(private = "file")
native_set_custom_cursor :: proc(pixels: []u8, w, h, hot_x, hot_y: int) {
	if len(pixels) < w * h * 4 do return

	planes := [?]^u8{raw_data(pixels)}

	rep := NS.BitmapImageRep_alloc()->initWithBitmapDataPlanes(
		&planes[0],
		NS.Integer(w),
		NS.Integer(h),
		8,  // bits per sample
		4,  // samples per pixel (RGBA)
		true,  // has alpha
		false, // is planar
		NS.AT("NSDeviceRGBColorSpace"),
		NS.Integer(w * 4), // bytes per row
		32, // bits per pixel
	)
	if rep == nil do return
	defer rep->release()

	image := NS.Image_alloc()->initWithSize({NS.Float(w), NS.Float(h)})
	image->addRepresentation((^NS.ImageRep)(rep))

	new_cursor := NS.Cursor_alloc()->initWithImage(image, {NS.Float(hot_x), NS.Float(hot_y)})
	image->release()

	if new_cursor != nil {
		new_cursor->set()
		// Release the previous custom cursor.
		if current_custom_cursor != nil {
			current_custom_cursor->release()
		}
		current_custom_cursor = new_cursor
	}
}

// --- Helpers ---

@(private = "file")
mouse_pos_from_event :: proc(event: ^NS.Event) -> core.Vec2 {
	loc := event->locationInWindow()
	// Flip Y — macOS origin is bottom-left
	y := NS.Float(screen_height) - loc.y
	return {f32(loc.x), f32(y)}
}

@(private = "file")
handle_modifier_change :: proc(
	flag: NS.EventModifierFlag,
	key: core.Key,
	new_flags: NS.EventModifierFlags,
) {
	was_down := flag in prev_modifier_flags
	is_down := flag in new_flags
	if is_down && !was_down {
		append(&events, core.Event(core.Key_Event{key = key, down = true}))
	} else if !is_down && was_down {
		append(&events, core.Event(core.Key_Event{key = key, down = false}))
	}
}

@(private = "file")
key_from_macos_keycode :: proc(keycode: u16) -> Maybe(core.Key) {
	#partial switch NS.kVK(keycode) {
	case .ANSI_A:
		return .A
	case .ANSI_B:
		return .B
	case .ANSI_C:
		return .C
	case .ANSI_D:
		return .D
	case .ANSI_E:
		return .E
	case .ANSI_F:
		return .F
	case .ANSI_G:
		return .G
	case .ANSI_H:
		return .H
	case .ANSI_I:
		return .I
	case .ANSI_J:
		return .J
	case .ANSI_K:
		return .K
	case .ANSI_L:
		return .L
	case .ANSI_M:
		return .M
	case .ANSI_N:
		return .N
	case .ANSI_O:
		return .O
	case .ANSI_P:
		return .P
	case .ANSI_Q:
		return .Q
	case .ANSI_R:
		return .R
	case .ANSI_S:
		return .S
	case .ANSI_T:
		return .T
	case .ANSI_U:
		return .U
	case .ANSI_V:
		return .V
	case .ANSI_W:
		return .W
	case .ANSI_X:
		return .X
	case .ANSI_Y:
		return .Y
	case .ANSI_Z:
		return .Z

	case .ANSI_1:
		return .Key_1
	case .ANSI_2:
		return .Key_2
	case .ANSI_3:
		return .Key_3
	case .ANSI_4:
		return .Key_4
	case .ANSI_5:
		return .Key_5
	case .ANSI_6:
		return .Key_6
	case .ANSI_7:
		return .Key_7
	case .ANSI_8:
		return .Key_8
	case .ANSI_9:
		return .Key_9
	case .ANSI_0:
		return .Key_0

	case .Return:
		return .Return
	case .Escape:
		return .Escape
	case .Delete:
		return .Backspace // macOS "Delete" is backspace
	case .Tab:
		return .Tab
	case .Space:
		return .Space

	case .ANSI_Minus:
		return .Minus
	case .ANSI_Equal:
		return .Equals
	case .ANSI_LeftBracket:
		return .Left_Bracket
	case .ANSI_RightBracket:
		return .Right_Bracket
	case .ANSI_Backslash:
		return .Backslash
	case .ANSI_Semicolon:
		return .Semicolon
	case .ANSI_Quote:
		return .Apostrophe
	case .ANSI_Grave:
		return .Grave
	case .ANSI_Comma:
		return .Comma
	case .ANSI_Period:
		return .Period
	case .ANSI_Slash:
		return .Slash

	case .F1:
		return .F1
	case .F2:
		return .F2
	case .F3:
		return .F3
	case .F4:
		return .F4
	case .F5:
		return .F5
	case .F6:
		return .F6
	case .F7:
		return .F7
	case .F8:
		return .F8
	case .F9:
		return .F9
	case .F10:
		return .F10
	case .F11:
		return .F11
	case .F12:
		return .F12

	case .Home:
		return .Home
	case .PageUp:
		return .Page_Up
	case .ForwardDelete:
		return .Delete
	case .End:
		return .End
	case .PageDown:
		return .Page_Down

	case .RightArrow:
		return .Right
	case .LeftArrow:
		return .Left
	case .DownArrow:
		return .Down
	case .UpArrow:
		return .Up

	case .Shift:
		return .Left_Shift
	case .RightShift:
		return .Right_Shift
	case .Control:
		return .Left_Ctrl
	case .RightControl:
		return .Right_Ctrl
	case .Option:
		return .Left_Alt
	case .RightOption:
		return .Right_Alt
	case .Command:
		return .Left_Super
	case .RightCommand:
		return .Right_Super

	case:
		return nil
	}
}
