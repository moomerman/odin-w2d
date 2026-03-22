package game

TILE_SIZE: f32 = 16

AnimationName :: enum {
	None,
	// lemming animations
	Block,
	Dig,
	Fall,
	Rescue,
	Splat,
	Walk,
	// other animations
	Trapdoor,
	Exit,
}

Sprite :: struct {
	source: Rect,
}

Animation :: struct {
	frames: []Sprite,
	fps:    f32,
}

all_animations: [AnimationName]Animation

animations_init :: proc() {
	all_animations = {
		.None     = {},
		.Block    = anim_from_grid(0, 4, 17, 15),
		.Dig      = anim_from_grid(0, 5, 8, 12),
		.Fall     = anim_from_grid(0, 1, 4, 12),
		.Rescue   = anim_from_grid(0, 8, 8, 12),
		.Splat    = anim_from_grid(0, 6, 17, 12),
		.Walk     = anim_from_grid(0, 0, 9, 12),
		.Trapdoor = anim_from_grid(0, 1, 10, 8, 41, 25),
		.Exit     = anim_from_grid(0, 0, 6, 8, 41, 25),
	}
}

animations_destroy :: proc() {
	for &anim in all_animations {
		delete(anim.frames)
	}
}

anim_from_grid :: proc(
	col, row: int,
	count: int,
	fps: f32,
	w: f32 = TILE_SIZE,
	h: f32 = TILE_SIZE,
) -> Animation {
	frames := make([]Sprite, count)
	for i in 0 ..< count {
		frames[i] = Sprite {
			source = {f32(col + i) * w, f32(row) * h, w, h},
		}
	}
	return Animation{frames = frames, fps = fps}
}

anim_update :: proc(state: ^AnimState, anim: Animation, dt: f32) -> Sprite {
	if !state.playing || len(anim.frames) == 0 {
		return anim_get_frame(state^, anim)
	}

	state.index += dt * anim.fps
	frame_count := f32(len(anim.frames))

	if state.index >= frame_count {
		if state.loop {
			state.index -= frame_count
			if state.index >= frame_count {
				state.index = 0
			}
		} else {
			state.index = frame_count - 1
			state.finished = true
			state.playing = false
		}
	}

	return anim_get_frame(state^, anim)
}

anim_get_frame :: proc(state: AnimState, anim: Animation) -> Sprite {
	if len(anim.frames) == 0 {
		return {}
	}
	idx := clamp(int(state.index), 0, len(anim.frames) - 1)
	return anim.frames[idx]
}
