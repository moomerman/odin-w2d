#+build js
package audio_webaudio

import "base:runtime"
import "core:fmt"

import core "../../core"

// Returns an Audio_Backend vtable for Web Audio API.
backend :: proc() -> core.Audio_Backend {
	return core.Audio_Backend {
		init = wa_init,
		shutdown = wa_shutdown,
		update = wa_update,
		load = wa_load_audio,
		load_from_bytes = wa_load_audio_from_bytes,
		destroy = wa_destroy_audio,
		get_duration = wa_get_audio_duration,
		play = wa_play_audio,
		stop = wa_stop_audio,
		pause = wa_pause_audio,
		resume = wa_resume_audio,
		stop_all = wa_stop_all_audio,
		set_volume = wa_set_audio_volume,
		set_pan = wa_set_audio_pan,
		set_pitch = wa_set_audio_pitch,
		set_looping = wa_set_audio_looping,
		set_position = wa_set_audio_position,
		is_playing = wa_is_audio_playing,
		is_paused = wa_is_audio_paused,
		get_time = wa_get_audio_time,
		create_bus = wa_create_audio_bus,
		destroy_bus = wa_destroy_audio_bus,
		get_main_bus = wa_get_main_audio_bus,
		set_bus_volume = wa_set_audio_bus_volume,
		get_bus_volume = wa_get_audio_bus_volume,
		set_bus_muted = wa_set_audio_bus_muted,
		is_bus_muted = wa_is_audio_bus_muted,
		set_listener_position = wa_set_audio_listener_position,
		get_listener_position = wa_get_audio_listener_position,
	}
}

//------------------//
// JS FOREIGN FUNCS //
//------------------//

foreign import audio_js "audio_js"

@(default_calling_convention = "contextless")
foreign audio_js {
	_js_audio_init :: proc() -> u32 ---
	_js_audio_shutdown :: proc() ---
	_js_load_audio :: proc(data: [^]u8, len: int, is_stream: bool) -> u32 ---
	_js_destroy_audio :: proc(source: u32) ---
	_js_get_audio_duration :: proc(source: u32) -> f32 ---
	_js_play_audio :: proc(source: u32, bus: u32, volume: f32, pan: f32, pitch: f32, loop: bool, delay: f32, is_spatial: bool, pos_x: f32, pos_y: f32, min_distance: f32, max_distance: f32, has_callback: bool) -> u32 ---
	_js_stop_audio :: proc(instance: u32) ---
	_js_pause_audio :: proc(instance: u32) ---
	_js_resume_audio :: proc(instance: u32) ---
	_js_stop_all_audio :: proc(bus: u32) ---
	_js_set_audio_volume :: proc(instance: u32, volume: f32) ---
	_js_set_audio_pan :: proc(instance: u32, pan: f32) ---
	_js_set_audio_pitch :: proc(instance: u32, pitch: f32) ---
	_js_set_audio_looping :: proc(instance: u32, loop: bool) ---
	_js_set_audio_position :: proc(instance: u32, x: f32, y: f32) ---
	_js_is_audio_playing :: proc(instance: u32) -> bool ---
	_js_is_audio_paused :: proc(instance: u32) -> bool ---
	_js_get_audio_time :: proc(instance: u32) -> f32 ---
	_js_create_audio_bus :: proc() -> u32 ---
	_js_destroy_audio_bus :: proc(bus: u32) ---
	_js_set_audio_bus_volume :: proc(bus: u32, volume: f32) ---
	_js_get_audio_bus_volume :: proc(bus: u32) -> f32 ---
	_js_set_audio_bus_muted :: proc(bus: u32, muted: bool) ---
	_js_is_audio_bus_muted :: proc(bus: u32) -> bool ---
	_js_set_listener_position :: proc(x: f32, y: f32) ---
	_js_poll_finished_callback :: proc() -> u32 ---
}

//----------------//
// INTERNAL STATE //
//----------------//

@(private = "file")
Callback_Entry :: struct {
	instance:  core.Audio_Instance,
	on_end:    core.Audio_End_Callback,
	user_data: rawptr,
}

@(private = "file")
MAX_CALLBACKS :: 256

@(private = "file")
Webaudio_State :: struct {
	initialized:       bool,
	allocator:         runtime.Allocator,
	listener_position: core.Vec2,
	callbacks:         [MAX_CALLBACKS]Callback_Entry,
	callback_count:    int,
}

@(private = "file")
state: ^Webaudio_State

//-----------//
// LIFECYCLE //
//-----------//

@(private = "file")
wa_init :: proc(allocator: Maybe(runtime.Allocator)) -> bool {
	if state != nil {
		fmt.eprintln("audio: Already initialized")
		return true
	}

	alloc := allocator.? or_else context.allocator

	state = new(Webaudio_State, alloc)
	state.allocator = alloc

	result := _js_audio_init()
	if result != 0 {
		state.initialized = true
		return true
	}

	fmt.eprintln("audio: Failed to initialize Web Audio")
	state = nil
	return false
}

@(private = "file")
wa_shutdown :: proc() {
	if state == nil do return

	allocator := state.allocator
	_js_audio_shutdown()
	free(state, allocator)
	state = nil
}

@(private = "file")
wa_update :: proc() {
	if state == nil do return
	if !state.initialized do return

	finished_handle := _js_poll_finished_callback()
	if finished_handle == 0 do return

	instance := core.Audio_Instance(finished_handle)
	for i := 0; i < state.callback_count; i += 1 {
		if state.callbacks[i].instance == instance {
			if state.callbacks[i].on_end != nil {
				state.callbacks[i].on_end(instance, state.callbacks[i].user_data)
			}
			state.callback_count -= 1
			if i < state.callback_count {
				state.callbacks[i] = state.callbacks[state.callback_count]
			}
			break
		}
	}
}


//-------------------//
// SOURCE MANAGEMENT //
//-------------------//

@(private = "file")
wa_load_audio :: proc(path: string, type: core.Audio_Source_Type) -> core.Audio_Source {
	fmt.eprintln(
		"audio: load_audio with file path not supported on web. Use load_audio_from_bytes with #load.",
	)
	return core.AUDIO_SOURCE_NONE
}

@(private = "file")
wa_load_audio_from_bytes :: proc(data: []u8, type: core.Audio_Source_Type) -> core.Audio_Source {
	if state == nil || !state.initialized {
		fmt.eprintln("audio: System not initialized")
		return core.AUDIO_SOURCE_NONE
	}

	if len(data) == 0 {
		fmt.eprintln("audio: Cannot load from empty data")
		return core.AUDIO_SOURCE_NONE
	}

	handle := _js_load_audio(raw_data(data), len(data), type == .Stream)
	if handle == 0 {
		return core.AUDIO_SOURCE_NONE
	}

	return core.Audio_Source(handle)
}

@(private = "file")
wa_destroy_audio :: proc(source: core.Audio_Source) {
	if state == nil || !state.initialized do return
	if source == core.AUDIO_SOURCE_NONE do return

	_js_destroy_audio(u32(source))
}

@(private = "file")
wa_get_audio_duration :: proc(source: core.Audio_Source) -> f32 {
	if state == nil || !state.initialized do return 0
	if source == core.AUDIO_SOURCE_NONE do return 0

	return _js_get_audio_duration(u32(source))
}

//----------//
// PLAYBACK //
//----------//

@(private = "file")
wa_play_audio :: proc(
	source: core.Audio_Source,
	params: core.Audio_Play_Params,
) -> core.Audio_Instance {
	if state == nil || !state.initialized {
		fmt.eprintln("audio: System not initialized")
		return core.AUDIO_INSTANCE_NONE
	}

	if source == core.AUDIO_SOURCE_NONE {
		fmt.eprintln("audio: Invalid source handle")
		return core.AUDIO_INSTANCE_NONE
	}

	is_spatial := false
	pos_x: f32 = 0
	pos_y: f32 = 0
	min_distance: f32 = 100
	max_distance: f32 = 1000

	if spatial, has_spatial := params.spatial.?; has_spatial {
		is_spatial = true
		pos_x = spatial.position.x
		pos_y = spatial.position.y
		min_distance = spatial.min_distance
		max_distance = spatial.max_distance
	}

	has_callback := params.on_end != nil

	handle := _js_play_audio(
		u32(source),
		u32(params.bus),
		params.volume,
		params.pan,
		params.pitch,
		params.loop,
		params.delay,
		is_spatial,
		pos_x,
		pos_y,
		min_distance,
		max_distance,
		has_callback,
	)

	if handle == 0 {
		return core.AUDIO_INSTANCE_NONE
	}

	instance := core.Audio_Instance(handle)

	if params.on_end != nil && state.callback_count < MAX_CALLBACKS {
		state.callbacks[state.callback_count] = Callback_Entry {
			instance  = instance,
			on_end    = params.on_end,
			user_data = params.user_data,
		}
		state.callback_count += 1
	}

	return instance
}

@(private = "file")
wa_stop_audio :: proc(instance: core.Audio_Instance) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_stop_audio(u32(instance))

	for i := 0; i < state.callback_count; i += 1 {
		if state.callbacks[i].instance == instance {
			state.callback_count -= 1
			if i < state.callback_count {
				state.callbacks[i] = state.callbacks[state.callback_count]
			}
			break
		}
	}
}

@(private = "file")
wa_pause_audio :: proc(instance: core.Audio_Instance) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_pause_audio(u32(instance))
}

@(private = "file")
wa_resume_audio :: proc(instance: core.Audio_Instance) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_resume_audio(u32(instance))
}

@(private = "file")
wa_stop_all_audio :: proc(bus: core.Audio_Bus) {
	if state == nil || !state.initialized do return

	_js_stop_all_audio(u32(bus))

	if bus == core.AUDIO_BUS_NONE {
		state.callback_count = 0
	}
}

//--------------//
// LIVE CONTROL //
//--------------//

@(private = "file")
wa_set_audio_volume :: proc(instance: core.Audio_Instance, volume: f32) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_set_audio_volume(u32(instance), volume)
}

@(private = "file")
wa_set_audio_pan :: proc(instance: core.Audio_Instance, pan: f32) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_set_audio_pan(u32(instance), pan)
}

@(private = "file")
wa_set_audio_pitch :: proc(instance: core.Audio_Instance, pitch: f32) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_set_audio_pitch(u32(instance), pitch)
}

@(private = "file")
wa_set_audio_looping :: proc(instance: core.Audio_Instance, loop: bool) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_set_audio_looping(u32(instance), loop)
}

@(private = "file")
wa_set_audio_position :: proc(instance: core.Audio_Instance, position: core.Vec2) {
	if state == nil || !state.initialized do return
	if instance == core.AUDIO_INSTANCE_NONE do return

	_js_set_audio_position(u32(instance), position.x, position.y)
}

//---------//
// QUERIES //
//---------//

@(private = "file")
wa_is_audio_playing :: proc(instance: core.Audio_Instance) -> bool {
	if state == nil || !state.initialized do return false
	if instance == core.AUDIO_INSTANCE_NONE do return false

	return _js_is_audio_playing(u32(instance))
}

@(private = "file")
wa_is_audio_paused :: proc(instance: core.Audio_Instance) -> bool {
	if state == nil || !state.initialized do return false
	if instance == core.AUDIO_INSTANCE_NONE do return false

	return _js_is_audio_paused(u32(instance))
}

@(private = "file")
wa_get_audio_time :: proc(instance: core.Audio_Instance) -> f32 {
	if state == nil || !state.initialized do return 0
	if instance == core.AUDIO_INSTANCE_NONE do return 0

	return _js_get_audio_time(u32(instance))
}

//------//
// BUSES //
//------//

@(private = "file")
wa_create_audio_bus :: proc(name: string) -> core.Audio_Bus {
	if state == nil || !state.initialized {
		fmt.eprintln("audio: System not initialized")
		return core.AUDIO_BUS_NONE
	}

	handle := _js_create_audio_bus()
	if handle == 0 {
		return core.AUDIO_BUS_NONE
	}

	return core.Audio_Bus(handle)
}

@(private = "file")
wa_destroy_audio_bus :: proc(bus: core.Audio_Bus) {
	if state == nil || !state.initialized do return
	if bus == core.AUDIO_BUS_NONE do return
	if bus == core.Audio_Bus(1) do return

	_js_destroy_audio_bus(u32(bus))
}

@(private = "file")
wa_get_main_audio_bus :: proc() -> core.Audio_Bus {
	return core.Audio_Bus(1)
}

@(private = "file")
wa_set_audio_bus_volume :: proc(bus: core.Audio_Bus, volume: f32) {
	if state == nil || !state.initialized do return

	bus_handle := bus == core.AUDIO_BUS_NONE ? core.Audio_Bus(1) : bus
	_js_set_audio_bus_volume(u32(bus_handle), volume)
}

@(private = "file")
wa_get_audio_bus_volume :: proc(bus: core.Audio_Bus) -> f32 {
	if state == nil || !state.initialized do return 1.0

	bus_handle := bus == core.AUDIO_BUS_NONE ? core.Audio_Bus(1) : bus
	return _js_get_audio_bus_volume(u32(bus_handle))
}

@(private = "file")
wa_set_audio_bus_muted :: proc(bus: core.Audio_Bus, muted: bool) {
	if state == nil || !state.initialized do return

	bus_handle := bus == core.AUDIO_BUS_NONE ? core.Audio_Bus(1) : bus
	_js_set_audio_bus_muted(u32(bus_handle), muted)
}

@(private = "file")
wa_is_audio_bus_muted :: proc(bus: core.Audio_Bus) -> bool {
	if state == nil || !state.initialized do return false

	bus_handle := bus == core.AUDIO_BUS_NONE ? core.Audio_Bus(1) : bus
	return _js_is_audio_bus_muted(u32(bus_handle))
}

//----------//
// LISTENER //
//----------//

@(private = "file")
wa_set_audio_listener_position :: proc(position: core.Vec2) {
	if state == nil || !state.initialized do return

	state.listener_position = position
	_js_set_listener_position(position.x, position.y)
}

@(private = "file")
wa_get_audio_listener_position :: proc() -> core.Vec2 {
	if state == nil do return {0, 0}
	return state.listener_position
}
