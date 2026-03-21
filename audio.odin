// Public audio API. Delegates to the active Audio_Backend (miniaudio on desktop,
// Web Audio on web). Users call init_audio() in their init proc and
// shutdown_audio() in their shutdown proc. The engine calls update_audio() each
// frame and shutdown_audio() as a safety net on exit.

package engine

import "core"

//---------------------//
// LIFECYCLE           //
//---------------------//

// Initialize the audio system. Call this in your init proc.
init_audio :: proc() -> bool {
	return ctx.audio.init(nil)
}

// Shut down the audio system. Call this in your shutdown proc.
shutdown_audio :: proc() {
	ctx.audio.shutdown()
}

//---------------------//
// SOURCE MANAGEMENT   //
//---------------------//

// Load audio from a file path (desktop only).
load_audio :: proc(path: string, type: Audio_Source_Type = .Static) -> Audio_Source {
	return ctx.audio.load(path, type)
}

// Load audio from raw bytes in memory (works on all platforms).
load_audio_from_bytes :: proc(data: []u8, type: Audio_Source_Type = .Static) -> Audio_Source {
	return ctx.audio.load_from_bytes(data, type)
}

// Destroy a loaded audio source.
destroy_audio :: proc(source: Audio_Source) {
	ctx.audio.destroy(source)
}

// Get the duration of a loaded audio source in seconds.
get_audio_duration :: proc(source: Audio_Source) -> f32 {
	return ctx.audio.get_duration(source)
}

//---------------------//
// PLAYBACK            //
//---------------------//

// Play an audio source. Overloaded: call with just a source, or with params.
play_audio :: proc {
	play_audio_with_params,
	play_audio_default,
}

play_audio_default :: proc(source: Audio_Source) -> Audio_Instance {
	return ctx.audio.play(source, default_audio_play_params())
}

play_audio_with_params :: proc(source: Audio_Source, params: Audio_Play_Params) -> Audio_Instance {
	return ctx.audio.play(source, params)
}

// Stop a playing audio instance immediately.
stop_audio :: proc(instance: Audio_Instance) {
	ctx.audio.stop(instance)
}

// Pause a playing audio instance (can be resumed).
pause_audio :: proc(instance: Audio_Instance) {
	ctx.audio.pause(instance)
}

// Resume a paused audio instance.
resume_audio :: proc(instance: Audio_Instance) {
	ctx.audio.resume(instance)
}

// Stop all playing audio, optionally filtered by bus.
stop_all_audio :: proc(bus: Audio_Bus = AUDIO_BUS_NONE) {
	ctx.audio.stop_all(bus)
}

//---------------------//
// LIVE CONTROL        //
//---------------------//

// Set the volume of a playing instance (0.0 to 1.0+).
set_audio_volume :: proc(instance: Audio_Instance, volume: f32) {
	ctx.audio.set_volume(instance, volume)
}

// Set the stereo pan of a playing instance (-1.0 left, 0.0 center, 1.0 right).
set_audio_pan :: proc(instance: Audio_Instance, pan: f32) {
	ctx.audio.set_pan(instance, pan)
}

// Set the pitch of a playing instance (1.0 = normal speed).
set_audio_pitch :: proc(instance: Audio_Instance, pitch: f32) {
	ctx.audio.set_pitch(instance, pitch)
}

// Set whether a playing instance should loop.
set_audio_looping :: proc(instance: Audio_Instance, loop: bool) {
	ctx.audio.set_looping(instance, loop)
}

// Set the 2D position of a spatial audio instance.
set_audio_position :: proc(instance: Audio_Instance, position: Vec2) {
	ctx.audio.set_position(instance, position)
}

//---------------------//
// QUERIES             //
//---------------------//

// Check if an audio instance is currently playing.
is_audio_playing :: proc(instance: Audio_Instance) -> bool {
	return ctx.audio.is_playing(instance)
}

// Check if an audio instance is paused.
is_audio_paused :: proc(instance: Audio_Instance) -> bool {
	return ctx.audio.is_paused(instance)
}

// Get the current playback time of an instance in seconds.
get_audio_time :: proc(instance: Audio_Instance) -> f32 {
	return ctx.audio.get_time(instance)
}

//---------------------//
// BUSES               //
//---------------------//

// Create a named audio bus for grouping sounds.
create_audio_bus :: proc(name: string) -> Audio_Bus {
	return ctx.audio.create_bus(name)
}

// Destroy a user-created audio bus.
destroy_audio_bus :: proc(bus: Audio_Bus) {
	ctx.audio.destroy_bus(bus)
}

// Get the main (master) audio bus handle.
get_main_audio_bus :: proc() -> Audio_Bus {
	return ctx.audio.get_main_bus()
}

// Set the volume of an audio bus.
set_audio_bus_volume :: proc(bus: Audio_Bus, volume: f32) {
	ctx.audio.set_bus_volume(bus, volume)
}

// Get the volume of an audio bus.
get_audio_bus_volume :: proc(bus: Audio_Bus) -> f32 {
	return ctx.audio.get_bus_volume(bus)
}

// Set whether an audio bus is muted.
set_audio_bus_muted :: proc(bus: Audio_Bus, muted: bool) {
	ctx.audio.set_bus_muted(bus, muted)
}

// Check if an audio bus is muted.
is_audio_bus_muted :: proc(bus: Audio_Bus) -> bool {
	return ctx.audio.is_bus_muted(bus)
}

//---------------------//
// LISTENER            //
//---------------------//

// Set the listener position for spatial audio.
set_audio_listener_position :: proc(position: Vec2) {
	ctx.audio.set_listener_position(position)
}

// Get the current listener position for spatial audio.
get_audio_listener_position :: proc() -> Vec2 {
	return ctx.audio.get_listener_position()
}

//---------------------//
// DEFAULT PARAMS      //
//---------------------//

// Helper to get default play parameters.
default_audio_play_params :: core.default_audio_play_params
