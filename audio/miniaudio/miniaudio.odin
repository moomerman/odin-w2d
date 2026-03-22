#+build windows, linux, darwin
package audio_miniaudio

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "vendor:miniaudio"

import core "../../core"

// Returns an Audio_Backend vtable for miniaudio.
backend :: proc() -> core.Audio_Backend {
	return core.Audio_Backend {
		init = ma_init,
		shutdown = ma_shutdown,
		update = ma_update,
		load = ma_load_audio,
		load_from_bytes = ma_load_audio_from_bytes,
		destroy = ma_destroy_audio,
		get_duration = ma_get_audio_duration,
		play = ma_play_audio,
		stop = ma_stop_audio,
		pause = ma_pause_audio,
		resume = ma_resume_audio,
		stop_all = ma_stop_all_audio,
		set_volume = ma_set_audio_volume,
		set_pan = ma_set_audio_pan,
		set_pitch = ma_set_audio_pitch,
		set_looping = ma_set_audio_looping,
		set_position = ma_set_audio_position,
		is_playing = ma_is_audio_playing,
		is_paused = ma_is_audio_paused,
		get_time = ma_get_audio_time,
		create_bus = ma_create_audio_bus,
		destroy_bus = ma_destroy_audio_bus,
		get_main_bus = ma_get_main_audio_bus,
		set_bus_volume = ma_set_audio_bus_volume,
		get_bus_volume = ma_get_audio_bus_volume,
		set_bus_muted = ma_set_audio_bus_muted,
		is_bus_muted = ma_is_audio_bus_muted,
		set_listener_position = ma_set_audio_listener_position,
		get_listener_position = ma_get_audio_listener_position,
	}
}

//----------------//
// INTERNAL TYPES //
//----------------//

@(private = "file")
Loaded_Source :: struct {
	type:        core.Audio_Source_Type,
	duration:    f32,
	data:        []u8,
	format:      miniaudio.format,
	channels:    u32,
	sample_rate: u32,
	frame_count: u64,
	stream_data: []u8,
	path:        string,
}

@(private = "file")
Audio_Bus_Data :: struct {
	handle:      core.Audio_Bus,
	name:        string,
	sound_group: miniaudio.sound_group,
	volume:      f32,
	muted:       bool,
}

@(private = "file")
Pending_Callback :: struct {
	instance:  core.Audio_Instance,
	on_end:    core.Audio_End_Callback,
	user_data: rawptr,
}

@(private = "file")
CALLBACK_QUEUE_SIZE :: 256

@(private = "file")
Callback_Queue :: struct {
	callbacks:   [CALLBACK_QUEUE_SIZE]Pending_Callback,
	write_index: u32,
	read_index:  u32,
}

@(private = "file")
Playing_Instance :: struct {
	handle:      core.Audio_Instance,
	source:      core.Audio_Source,
	source_type: core.Audio_Source_Type,
	bus:         core.Audio_Bus,
	sound:       miniaudio.sound,
	buffer:      miniaudio.audio_buffer,
	decoder:     miniaudio.decoder,
	has_decoder: bool,
	paused:      bool,
	is_spatial:  bool,
	finished:    b32,
	on_end:      core.Audio_End_Callback,
	user_data:   rawptr,
}

@(private = "file")
Miniaudio_State :: struct {
	allocator:         runtime.Allocator,
	engine:            miniaudio.engine,
	main_sound_group:  miniaudio.sound_group,
	main_bus_volume:   f32,
	main_bus_muted:    bool,
	buses:             [dynamic]^Audio_Bus_Data,
	next_bus_id:       u32,
	callback_queue:    Callback_Queue,
	listener_position: core.Vec2,
	sources:           [dynamic]^Loaded_Source,
	instances:         [dynamic]^Playing_Instance,
	next_instance_id:  u32,
}

@(private = "file")
state: ^Miniaudio_State

//-----------//
// LIFECYCLE //
//-----------//

@(private = "file")
ma_init :: proc(allocator: Maybe(runtime.Allocator)) -> bool {
	if state != nil {
		fmt.eprintln("audio: Already initialized")
		return true
	}

	alloc := allocator.? or_else context.allocator

	state = new(Miniaudio_State, alloc)
	state.allocator = alloc

	result := miniaudio.engine_init(nil, &state.engine)
	if result != .SUCCESS {
		fmt.eprintfln("audio: Failed to initialize miniaudio engine: %v", result)
		state = nil
		return false
	}

	result = miniaudio.sound_group_init(&state.engine, {}, nil, &state.main_sound_group)
	if result != .SUCCESS {
		fmt.eprintfln("audio: Failed to initialize main sound group: %v", result)
		miniaudio.engine_uninit(&state.engine)
		state = nil
		return false
	}

	state.sources = make([dynamic]^Loaded_Source, alloc)
	state.instances = make([dynamic]^Playing_Instance, alloc)
	state.buses = make([dynamic]^Audio_Bus_Data, alloc)
	state.next_instance_id = 1
	state.next_bus_id = 2
	state.main_bus_volume = 1.0
	state.main_bus_muted = false

	return true
}

@(private = "file")
ma_shutdown :: proc() {
	if state == nil do return

	allocator := state.allocator

	for inst in state.instances {
		if inst != nil {
			miniaudio.sound_uninit(&inst.sound)
			if inst.source_type == .Static {
				miniaudio.audio_buffer_uninit(&inst.buffer)
			} else if inst.has_decoder {
				miniaudio.decoder_uninit(&inst.decoder)
			}
			free(inst, state.allocator)
		}
	}
	delete(state.instances)

	for bus in state.buses {
		if bus != nil {
			miniaudio.sound_group_uninit(&bus.sound_group)
			if len(bus.name) > 0 {
				delete(bus.name, state.allocator)
			}
			free(bus, state.allocator)
		}
	}
	delete(state.buses)

	for src in state.sources {
		if src != nil {
			if src.type == .Static {
				delete(src.data, state.allocator)
			} else {
				if len(src.stream_data) > 0 {
					delete(src.stream_data, state.allocator)
				}
				if len(src.path) > 0 {
					delete(src.path, state.allocator)
				}
			}
			free(src, state.allocator)
		}
	}
	delete(state.sources)

	miniaudio.sound_group_uninit(&state.main_sound_group)
	miniaudio.engine_uninit(&state.engine)

	free(state, allocator)
	state = nil
}

@(private = "file")
ma_update :: proc() {
	if state == nil do return

	for {
		read_idx := intrinsics.atomic_load(&state.callback_queue.read_index)
		write_idx := intrinsics.atomic_load(&state.callback_queue.write_index)

		if read_idx == write_idx {
			break
		}

		cb := state.callback_queue.callbacks[read_idx]
		next_read := (read_idx + 1) % CALLBACK_QUEUE_SIZE
		intrinsics.atomic_store(&state.callback_queue.read_index, next_read)

		if cb.on_end != nil {
			cb.on_end(cb.instance, cb.user_data)
		}
	}

	#reverse for inst, i in state.instances {
		if inst == nil do continue

		if intrinsics.atomic_load(&inst.finished) {
			miniaudio.sound_uninit(&inst.sound)
			if inst.source_type == .Static {
				miniaudio.audio_buffer_uninit(&inst.buffer)
			} else if inst.has_decoder {
				miniaudio.decoder_uninit(&inst.decoder)
			}
			free(inst, state.allocator)
			state.instances[i] = nil
		}
	}
}


//-------------------//
// SOURCE MANAGEMENT //
//-------------------//

@(private = "file")
ma_load_audio :: proc(path: string, type: core.Audio_Source_Type) -> core.Audio_Source {
	if state == nil {
		fmt.eprintln("audio: System not initialized")
		return core.AUDIO_SOURCE_NONE
	}

	if type == .Stream {
		source := new(Loaded_Source, state.allocator)
		source.type = .Stream
		source.path = strings.clone(path, state.allocator)

		cpath := strings.clone_to_cstring(path, context.temp_allocator)
		decoder: miniaudio.decoder
		if miniaudio.decoder_init_file(cpath, nil, &decoder) == .SUCCESS {
			length: u64
			if miniaudio.decoder_get_length_in_pcm_frames(&decoder, &length) == .SUCCESS {
				source.duration = f32(length) / f32(decoder.outputSampleRate)
			}
			miniaudio.decoder_uninit(&decoder)
		}

		append(&state.sources, source)
		return core.Audio_Source(len(state.sources))
	}

	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	engine_sample_rate := miniaudio.engine_get_sample_rate(&state.engine)
	decoder_config := miniaudio.decoder_config_init(.f32, 0, engine_sample_rate)
	decoder: miniaudio.decoder

	result := miniaudio.decoder_init_file(cpath, &decoder_config, &decoder)
	if result != .SUCCESS {
		fmt.eprintfln("audio: Failed to load '%s': %v", path, result)
		return core.AUDIO_SOURCE_NONE
	}
	defer miniaudio.decoder_uninit(&decoder)

	return load_from_decoder(&decoder, .Static)
}

@(private = "file")
ma_load_audio_from_bytes :: proc(data: []u8, type: core.Audio_Source_Type) -> core.Audio_Source {
	if state == nil {
		fmt.eprintln("audio: System not initialized")
		return core.AUDIO_SOURCE_NONE
	}

	if len(data) == 0 {
		fmt.eprintln("audio: Cannot load from empty data")
		return core.AUDIO_SOURCE_NONE
	}

	if type == .Stream {
		source := new(Loaded_Source, state.allocator)
		source.type = .Stream
		source.stream_data = make([]u8, len(data), state.allocator)
		copy(source.stream_data, data)

		decoder: miniaudio.decoder
		if miniaudio.decoder_init_memory(
			   raw_data(source.stream_data),
			   c.size_t(len(source.stream_data)),
			   nil,
			   &decoder,
		   ) ==
		   .SUCCESS {
			length: u64
			if miniaudio.decoder_get_length_in_pcm_frames(&decoder, &length) == .SUCCESS {
				source.duration = f32(length) / f32(decoder.outputSampleRate)
			}
			miniaudio.decoder_uninit(&decoder)
		}

		append(&state.sources, source)
		return core.Audio_Source(len(state.sources))
	}

	engine_sample_rate := miniaudio.engine_get_sample_rate(&state.engine)
	decoder_config := miniaudio.decoder_config_init(.f32, 0, engine_sample_rate)
	decoder: miniaudio.decoder

	result := miniaudio.decoder_init_memory(
		raw_data(data),
		c.size_t(len(data)),
		&decoder_config,
		&decoder,
	)
	if result != .SUCCESS {
		fmt.eprintfln("audio: Failed to decode from memory: %v", result)
		return core.AUDIO_SOURCE_NONE
	}
	defer miniaudio.decoder_uninit(&decoder)

	return load_from_decoder(&decoder, .Static)
}

@(private = "file")
load_from_decoder :: proc(
	decoder: ^miniaudio.decoder,
	type: core.Audio_Source_Type,
) -> core.Audio_Source {
	channels := decoder.outputChannels
	bytes_per_frame := channels * size_of(f32)

	frame_count: u64
	result := miniaudio.decoder_get_length_in_pcm_frames(decoder, &frame_count)

	pcm_data: []u8

	if result != .SUCCESS || frame_count == 0 {
		CHUNK_SIZE :: 4096
		chunks: [dynamic][]u8
		defer {
			for chunk in chunks {
				delete(chunk, state.allocator)
			}
			delete(chunks)
		}

		frame_count = 0
		for {
			chunk := make([]u8, CHUNK_SIZE * int(bytes_per_frame), state.allocator)
			frames_read: u64
			miniaudio.decoder_read_pcm_frames(decoder, raw_data(chunk), CHUNK_SIZE, &frames_read)

			if frames_read == 0 {
				delete(chunk, state.allocator)
				break
			}

			frame_count += frames_read
			if frames_read < CHUNK_SIZE {
				append(&chunks, chunk[:frames_read * u64(bytes_per_frame)])
			} else {
				append(&chunks, chunk)
			}
		}

		total_bytes := int(frame_count) * int(bytes_per_frame)
		pcm_data = make([]u8, total_bytes, state.allocator)
		offset := 0
		for chunk in chunks {
			copy(pcm_data[offset:], chunk)
			offset += len(chunk)
		}
	} else {
		total_bytes := int(frame_count) * int(bytes_per_frame)
		pcm_data = make([]u8, total_bytes, state.allocator)

		frames_read: u64
		result = miniaudio.decoder_read_pcm_frames(
			decoder,
			raw_data(pcm_data),
			frame_count,
			&frames_read,
		)
		if result != .SUCCESS {
			fmt.eprintfln("audio: Failed to read PCM frames: %v", result)
			delete(pcm_data, state.allocator)
			return core.AUDIO_SOURCE_NONE
		}
		frame_count = frames_read
	}

	source := new(Loaded_Source, state.allocator)
	source.type = type
	source.data = pcm_data
	source.format = .f32
	source.channels = channels
	source.sample_rate = decoder.outputSampleRate
	source.frame_count = frame_count
	source.duration = f32(frame_count) / f32(decoder.outputSampleRate)

	append(&state.sources, source)
	return core.Audio_Source(len(state.sources))
}

@(private = "file")
ma_destroy_audio :: proc(source: core.Audio_Source) {
	if state == nil do return
	if source == core.AUDIO_SOURCE_NONE do return

	idx := int(source) - 1
	if idx < 0 || idx >= len(state.sources) do return

	src := state.sources[idx]
	if src == nil do return

	if src.type == .Static {
		delete(src.data, state.allocator)
	} else {
		if len(src.stream_data) > 0 {
			delete(src.stream_data, state.allocator)
		}
		if len(src.path) > 0 {
			delete(src.path, state.allocator)
		}
	}
	free(src, state.allocator)
	state.sources[idx] = nil
}

@(private = "file")
ma_get_audio_duration :: proc(source: core.Audio_Source) -> f32 {
	if state == nil do return 0
	if source == core.AUDIO_SOURCE_NONE do return 0

	idx := int(source) - 1
	if idx < 0 || idx >= len(state.sources) do return 0

	src := state.sources[idx]
	if src == nil do return 0

	return src.duration
}

//----------//
// PLAYBACK //
//----------//

@(private = "file")
ma_play_audio :: proc(
	source: core.Audio_Source,
	params: core.Audio_Play_Params,
) -> core.Audio_Instance {
	if state == nil {
		fmt.eprintln("audio: System not initialized")
		return core.AUDIO_INSTANCE_NONE
	}

	if source == core.AUDIO_SOURCE_NONE {
		fmt.eprintln("audio: Invalid source handle")
		return core.AUDIO_INSTANCE_NONE
	}

	idx := int(source) - 1
	if idx < 0 || idx >= len(state.sources) {
		fmt.eprintln("audio: Source handle out of range")
		return core.AUDIO_INSTANCE_NONE
	}

	src := state.sources[idx]
	if src == nil {
		fmt.eprintln("audio: Source has been destroyed")
		return core.AUDIO_INSTANCE_NONE
	}

	inst := new(Playing_Instance, state.allocator)
	inst.source = source
	inst.source_type = src.type
	inst.bus = params.bus
	inst.on_end = params.on_end
	inst.user_data = params.user_data

	inst.handle = core.Audio_Instance(state.next_instance_id)
	state.next_instance_id += 1

	sound_group: ^miniaudio.sound_group
	if params.bus == core.AUDIO_BUS_NONE || params.bus == core.Audio_Bus(1) {
		sound_group = &state.main_sound_group
	} else {
		bus := find_bus(params.bus)
		if bus != nil {
			sound_group = &bus.sound_group
		} else {
			sound_group = &state.main_sound_group
		}
	}

	result: miniaudio.result

	if src.type == .Static {
		buffer_config := miniaudio.audio_buffer_config_init(
			src.format,
			src.channels,
			src.frame_count,
			raw_data(src.data),
			nil,
		)

		result = miniaudio.audio_buffer_init(&buffer_config, &inst.buffer)
		if result != .SUCCESS {
			fmt.eprintfln("audio: Failed to create audio buffer: %v", result)
			free(inst, state.allocator)
			return core.AUDIO_INSTANCE_NONE
		}

		result = miniaudio.sound_init_from_data_source(
			&state.engine,
			cast(^miniaudio.data_source)&inst.buffer,
			{},
			sound_group,
			&inst.sound,
		)
		if result != .SUCCESS {
			fmt.eprintfln("audio: Failed to create sound: %v", result)
			miniaudio.audio_buffer_uninit(&inst.buffer)
			free(inst, state.allocator)
			return core.AUDIO_INSTANCE_NONE
		}
	} else {
		if len(src.path) > 0 {
			cpath := strings.clone_to_cstring(src.path, context.temp_allocator)
			result = miniaudio.sound_init_from_file(
				&state.engine,
				cpath,
				{.STREAM},
				sound_group,
				nil,
				&inst.sound,
			)
			if result != .SUCCESS {
				fmt.eprintfln("audio: Failed to stream from file '%s': %v", src.path, result)
				free(inst, state.allocator)
				return core.AUDIO_INSTANCE_NONE
			}
		} else if len(src.stream_data) > 0 {
			decoder_config := miniaudio.decoder_config_init_default()
			result = miniaudio.decoder_init_memory(
				raw_data(src.stream_data),
				c.size_t(len(src.stream_data)),
				&decoder_config,
				&inst.decoder,
			)
			if result != .SUCCESS {
				fmt.eprintfln("audio: Failed to init decoder from memory: %v", result)
				free(inst, state.allocator)
				return core.AUDIO_INSTANCE_NONE
			}
			inst.has_decoder = true

			result = miniaudio.sound_init_from_data_source(
				&state.engine,
				cast(^miniaudio.data_source)&inst.decoder,
				{.STREAM},
				sound_group,
				&inst.sound,
			)
			if result != .SUCCESS {
				fmt.eprintfln("audio: Failed to create sound from decoder: %v", result)
				miniaudio.decoder_uninit(&inst.decoder)
				free(inst, state.allocator)
				return core.AUDIO_INSTANCE_NONE
			}
		} else {
			fmt.eprintln("audio: Stream source has no data")
			free(inst, state.allocator)
			return core.AUDIO_INSTANCE_NONE
		}
	}

	miniaudio.sound_set_volume(&inst.sound, params.volume)
	miniaudio.sound_set_pan(&inst.sound, params.pan)
	miniaudio.sound_set_pitch(&inst.sound, params.pitch == 0 ? 1.0 : params.pitch)
	miniaudio.sound_set_looping(&inst.sound, b32(params.loop))

	if spatial_params, has_spatial := params.spatial.?; has_spatial {
		inst.is_spatial = true
		miniaudio.sound_set_spatialization_enabled(&inst.sound, true)
		miniaudio.sound_set_position(
			&inst.sound,
			spatial_params.position.x,
			spatial_params.position.y,
			0,
		)
		miniaudio.sound_set_min_distance(&inst.sound, spatial_params.min_distance)
		miniaudio.sound_set_max_distance(&inst.sound, spatial_params.max_distance)
		miniaudio.sound_set_attenuation_model(&inst.sound, .linear)
	} else {
		miniaudio.sound_set_spatialization_enabled(&inst.sound, false)
	}

	miniaudio.sound_set_end_callback(&inst.sound, instance_end_callback, inst)

	if params.delay > 0 {
		engine_time := miniaudio.engine_get_time_in_milliseconds(&state.engine)
		start_time := engine_time + u64(params.delay * 1000)
		miniaudio.sound_set_start_time_in_milliseconds(&inst.sound, start_time)
	}

	result = miniaudio.sound_start(&inst.sound)
	if result != .SUCCESS {
		fmt.eprintfln("audio: Failed to start sound: %v", result)
		miniaudio.sound_uninit(&inst.sound)
		if src.type == .Static {
			miniaudio.audio_buffer_uninit(&inst.buffer)
		} else if inst.has_decoder {
			miniaudio.decoder_uninit(&inst.decoder)
		}
		free(inst, state.allocator)
		return core.AUDIO_INSTANCE_NONE
	}

	append(&state.instances, inst)

	return inst.handle
}

@(private = "file")
instance_end_callback :: proc "c" (user_data: rawptr, snd: ^miniaudio.sound) {
	inst := cast(^Playing_Instance)user_data

	if inst.on_end != nil {
		queue_callback(inst.handle, inst.on_end, inst.user_data)
	}

	intrinsics.atomic_store(&inst.finished, true)
}

@(private = "file")
queue_callback :: proc "c" (
	instance: core.Audio_Instance,
	on_end: core.Audio_End_Callback,
	user_data: rawptr,
) {
	write_idx := intrinsics.atomic_load(&state.callback_queue.write_index)
	next_write := (write_idx + 1) % CALLBACK_QUEUE_SIZE

	read_idx := intrinsics.atomic_load(&state.callback_queue.read_index)
	if next_write == read_idx {
		return
	}

	state.callback_queue.callbacks[write_idx] = Pending_Callback {
		instance  = instance,
		on_end    = on_end,
		user_data = user_data,
	}

	intrinsics.atomic_store(&state.callback_queue.write_index, next_write)
}

@(private = "file")
find_instance :: proc(handle: core.Audio_Instance) -> ^Playing_Instance {
	if handle == core.AUDIO_INSTANCE_NONE do return nil

	for inst in state.instances {
		if inst != nil && inst.handle == handle {
			return inst
		}
	}
	return nil
}

@(private = "file")
ma_stop_audio :: proc(instance: core.Audio_Instance) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	miniaudio.sound_stop(&inst.sound)
	inst.paused = false
	intrinsics.atomic_store(&inst.finished, true)
}

@(private = "file")
ma_pause_audio :: proc(instance: core.Audio_Instance) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	miniaudio.sound_stop(&inst.sound)
	inst.paused = true
}

@(private = "file")
ma_resume_audio :: proc(instance: core.Audio_Instance) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	if inst.paused {
		miniaudio.sound_start(&inst.sound)
		inst.paused = false
	}
}

@(private = "file")
ma_stop_all_audio :: proc(bus: core.Audio_Bus) {
	if state == nil do return

	for inst in state.instances {
		if inst == nil do continue
		if intrinsics.atomic_load(&inst.finished) do continue

		if bus != core.AUDIO_BUS_NONE {
			if inst.bus != bus do continue
		}

		miniaudio.sound_stop(&inst.sound)
		inst.paused = false
		intrinsics.atomic_store(&inst.finished, true)
	}
}

//--------------//
// LIVE CONTROL //
//--------------//

@(private = "file")
ma_set_audio_volume :: proc(instance: core.Audio_Instance, volume: f32) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_volume(&inst.sound, volume)
}

@(private = "file")
ma_set_audio_pan :: proc(instance: core.Audio_Instance, pan: f32) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_pan(&inst.sound, pan)
}

@(private = "file")
ma_set_audio_pitch :: proc(instance: core.Audio_Instance, pitch: f32) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_pitch(&inst.sound, pitch == 0 ? 1.0 : pitch)
}

@(private = "file")
ma_set_audio_looping :: proc(instance: core.Audio_Instance, loop: bool) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_looping(&inst.sound, b32(loop))
}

@(private = "file")
ma_set_audio_position :: proc(instance: core.Audio_Instance, position: core.Vec2) {
	if state == nil do return

	inst := find_instance(instance)
	if inst == nil do return

	if inst.is_spatial {
		miniaudio.sound_set_position(&inst.sound, position.x, position.y, 0)
	}
}

//---------//
// QUERIES //
//---------//

@(private = "file")
ma_is_audio_playing :: proc(instance: core.Audio_Instance) -> bool {
	if state == nil do return false

	inst := find_instance(instance)
	if inst == nil do return false

	return bool(miniaudio.sound_is_playing(&inst.sound))
}

@(private = "file")
ma_is_audio_paused :: proc(instance: core.Audio_Instance) -> bool {
	if state == nil do return false

	inst := find_instance(instance)
	if inst == nil do return false

	return inst.paused
}

@(private = "file")
ma_get_audio_time :: proc(instance: core.Audio_Instance) -> f32 {
	if state == nil do return 0

	inst := find_instance(instance)
	if inst == nil do return 0

	cursor: u64
	if miniaudio.sound_get_cursor_in_pcm_frames(&inst.sound, &cursor) == .SUCCESS {
		engine_sample_rate := miniaudio.engine_get_sample_rate(&state.engine)
		if engine_sample_rate > 0 {
			return f32(cursor) / f32(engine_sample_rate)
		}
	}
	return 0
}

//------//
// BUSES //
//------//

@(private = "file")
find_bus :: proc(handle: core.Audio_Bus) -> ^Audio_Bus_Data {
	if handle == core.AUDIO_BUS_NONE do return nil
	if handle == core.Audio_Bus(1) do return nil

	for bus in state.buses {
		if bus != nil && bus.handle == handle {
			return bus
		}
	}
	return nil
}

@(private = "file")
ma_create_audio_bus :: proc(name: string) -> core.Audio_Bus {
	if state == nil {
		fmt.eprintln("audio: System not initialized")
		return core.AUDIO_BUS_NONE
	}

	bus := new(Audio_Bus_Data, state.allocator)
	bus.handle = core.Audio_Bus(state.next_bus_id)
	state.next_bus_id += 1
	bus.volume = 1.0
	bus.muted = false

	if len(name) > 0 {
		bus.name = strings.clone(name, state.allocator)
	}

	result := miniaudio.sound_group_init(
		&state.engine,
		{},
		&state.main_sound_group,
		&bus.sound_group,
	)
	if result != .SUCCESS {
		fmt.eprintfln("audio: Failed to create bus '%s': %v", name, result)
		if len(bus.name) > 0 {
			delete(bus.name, state.allocator)
		}
		free(bus, state.allocator)
		return core.AUDIO_BUS_NONE
	}

	append(&state.buses, bus)
	return bus.handle
}

@(private = "file")
ma_destroy_audio_bus :: proc(bus_handle: core.Audio_Bus) {
	if state == nil do return
	if bus_handle == core.AUDIO_BUS_NONE do return
	if bus_handle == core.Audio_Bus(1) do return

	for &bus, i in state.buses {
		if bus != nil && bus.handle == bus_handle {
			miniaudio.sound_group_uninit(&bus.sound_group)
			if len(bus.name) > 0 {
				delete(bus.name, state.allocator)
			}
			free(bus, state.allocator)
			state.buses[i] = nil
			return
		}
	}
}

@(private = "file")
ma_get_main_audio_bus :: proc() -> core.Audio_Bus {
	return core.Audio_Bus(1)
}

@(private = "file")
ma_set_audio_bus_volume :: proc(bus_handle: core.Audio_Bus, volume: f32) {
	if state == nil do return

	if bus_handle == core.Audio_Bus(1) || bus_handle == core.AUDIO_BUS_NONE {
		state.main_bus_volume = volume
		if !state.main_bus_muted {
			miniaudio.sound_group_set_volume(&state.main_sound_group, volume)
		}
		return
	}

	bus := find_bus(bus_handle)
	if bus == nil do return

	bus.volume = volume
	if !bus.muted {
		miniaudio.sound_group_set_volume(&bus.sound_group, volume)
	}
}

@(private = "file")
ma_get_audio_bus_volume :: proc(bus_handle: core.Audio_Bus) -> f32 {
	if state == nil do return 1.0

	if bus_handle == core.Audio_Bus(1) || bus_handle == core.AUDIO_BUS_NONE {
		return state.main_bus_volume
	}

	bus := find_bus(bus_handle)
	if bus == nil do return 1.0

	return bus.volume
}

@(private = "file")
ma_set_audio_bus_muted :: proc(bus_handle: core.Audio_Bus, muted: bool) {
	if state == nil do return

	if bus_handle == core.Audio_Bus(1) || bus_handle == core.AUDIO_BUS_NONE {
		state.main_bus_muted = muted
		if muted {
			miniaudio.sound_group_set_volume(&state.main_sound_group, 0)
		} else {
			miniaudio.sound_group_set_volume(&state.main_sound_group, state.main_bus_volume)
		}
		return
	}

	bus := find_bus(bus_handle)
	if bus == nil do return

	bus.muted = muted
	if muted {
		miniaudio.sound_group_set_volume(&bus.sound_group, 0)
	} else {
		miniaudio.sound_group_set_volume(&bus.sound_group, bus.volume)
	}
}

@(private = "file")
ma_is_audio_bus_muted :: proc(bus_handle: core.Audio_Bus) -> bool {
	if state == nil do return false

	if bus_handle == core.Audio_Bus(1) || bus_handle == core.AUDIO_BUS_NONE {
		return state.main_bus_muted
	}

	bus := find_bus(bus_handle)
	if bus == nil do return false

	return bus.muted
}

//----------//
// LISTENER //
//----------//

@(private = "file")
ma_set_audio_listener_position :: proc(position: core.Vec2) {
	if state == nil do return

	state.listener_position = position
	miniaudio.engine_listener_set_position(&state.engine, 0, position.x, position.y, 0)
}

@(private = "file")
ma_get_audio_listener_position :: proc() -> core.Vec2 {
	if state == nil do return {0, 0}
	return state.listener_position
}
