package core

import "base:runtime"

// Audio_Source is a handle to a loaded audio asset.
// Can be played multiple times simultaneously.
Audio_Source :: distinct u64
AUDIO_SOURCE_NONE :: Audio_Source(0)

// Audio_Instance is a handle to a currently playing instance.
// Used to control playback (pause, volume, etc.)
Audio_Instance :: distinct u64
AUDIO_INSTANCE_NONE :: Audio_Instance(0)

// Audio_Bus is a handle to an audio bus for grouping and volume control.
Audio_Bus :: distinct u64
AUDIO_BUS_NONE :: Audio_Bus(0)

// Audio_Source_Type determines how the audio is loaded.
Audio_Source_Type :: enum {
	Static, // Pre-decode into memory (best for short sounds)
	Stream, // Stream from disk/memory (best for long music)
}

// Audio_End_Callback is called when an audio instance finishes playing.
Audio_End_Callback :: proc(instance: Audio_Instance, user_data: rawptr)

// Audio_Spatial_Params controls 2D positional audio.
Audio_Spatial_Params :: struct {
	position:     Vec2, // Position of the sound in world space
	min_distance: f32, // Distance at which sound is at full volume
	max_distance: f32, // Distance at which sound is inaudible
}

DEFAULT_AUDIO_SPATIAL_PARAMS :: Audio_Spatial_Params {
	position     = {0, 0},
	min_distance = 100,
	max_distance = 1000,
}

// Audio_Play_Params controls how an audio source is played.
Audio_Play_Params :: struct {
	bus:       Audio_Bus, // Which bus to play on (AUDIO_BUS_NONE = main bus)
	volume:    f32, // Volume multiplier (0.0 to 1.0+)
	pan:       f32, // Stereo pan (-1.0 = left, 0.0 = center, 1.0 = right)
	pitch:     f32, // Pitch multiplier (1.0 = normal, 2.0 = octave up)
	loop:      bool, // Whether to loop the audio
	delay:     f32, // Delay in seconds before playback starts
	spatial:   Maybe(Audio_Spatial_Params), // Optional spatial audio
	on_end:    Audio_End_Callback, // Callback when audio ends
	user_data: rawptr, // User data passed to callback
}

default_audio_play_params :: proc() -> Audio_Play_Params {
	return Audio_Play_Params {
		bus = AUDIO_BUS_NONE,
		volume = 1.0,
		pan = 0.0,
		pitch = 1.0,
		loop = false,
		delay = 0.0,
		spatial = nil,
		on_end = nil,
		user_data = nil,
	}
}

// Audio_Backend abstracts over different audio implementations.
// Desktop uses miniaudio, web uses Web Audio API.
Audio_Backend :: struct {
	// Initialize the audio system. Returns true on success.
	init:                  proc(allocator: Maybe(runtime.Allocator)) -> bool,

	// Shut down the audio system and release all resources.
	shutdown:              proc(),

	// Per-frame update — dispatches callbacks and cleans up finished instances.
	update:                proc(),

	// Load audio from a file path. Returns AUDIO_SOURCE_NONE on failure.
	load:                  proc(path: string, type: Audio_Source_Type) -> Audio_Source,

	// Load audio from raw bytes in memory. Returns AUDIO_SOURCE_NONE on failure.
	load_from_bytes:       proc(data: []u8, type: Audio_Source_Type) -> Audio_Source,

	// Destroy a loaded audio source and free its resources.
	destroy:               proc(source: Audio_Source),

	// Get the duration of a loaded source in seconds.
	get_duration:          proc(source: Audio_Source) -> f32,

	// Play an audio source with the given parameters. Returns an instance handle.
	play:                  proc(source: Audio_Source, params: Audio_Play_Params) -> Audio_Instance,

	// Stop a playing instance immediately.
	stop:                  proc(instance: Audio_Instance),

	// Pause a playing instance (can be resumed).
	pause:                 proc(instance: Audio_Instance),

	// Resume a paused instance.
	resume:                proc(instance: Audio_Instance),

	// Stop all playing instances, optionally filtered by bus.
	stop_all:              proc(bus: Audio_Bus),

	// Set volume of a playing instance (0.0 to 1.0+).
	set_volume:            proc(instance: Audio_Instance, volume: f32),

	// Set stereo pan of a playing instance (-1.0 left, 0.0 center, 1.0 right).
	set_pan:               proc(instance: Audio_Instance, pan: f32),

	// Set pitch of a playing instance (1.0 = normal).
	set_pitch:             proc(instance: Audio_Instance, pitch: f32),

	// Set whether a playing instance should loop.
	set_looping:           proc(instance: Audio_Instance, loop: bool),

	// Set the position of a spatial audio instance.
	set_position:          proc(instance: Audio_Instance, position: Vec2),

	// Check if an instance is currently playing.
	is_playing:            proc(instance: Audio_Instance) -> bool,

	// Check if an instance is paused.
	is_paused:             proc(instance: Audio_Instance) -> bool,

	// Get the current playback time of an instance in seconds.
	get_time:              proc(instance: Audio_Instance) -> f32,

	// Create a named audio bus for grouping sounds.
	create_bus:            proc(name: string) -> Audio_Bus,

	// Destroy a user-created audio bus.
	destroy_bus:           proc(bus: Audio_Bus),

	// Get the main (master) audio bus handle.
	get_main_bus:          proc() -> Audio_Bus,

	// Set the volume of an audio bus.
	set_bus_volume:        proc(bus: Audio_Bus, volume: f32),

	// Get the volume of an audio bus.
	get_bus_volume:        proc(bus: Audio_Bus) -> f32,

	// Set whether an audio bus is muted.
	set_bus_muted:         proc(bus: Audio_Bus, muted: bool),

	// Check if an audio bus is muted.
	is_bus_muted:          proc(bus: Audio_Bus) -> bool,

	// Set the listener position for spatial audio.
	set_listener_position: proc(position: Vec2),

	// Get the current listener position.
	get_listener_position: proc() -> Vec2,
}
