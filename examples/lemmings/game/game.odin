package game

import a "../assets"

LoadLevelEvent :: struct {
	level: a.LevelName,
}

PlaySoundEvent :: struct {
	sound: a.SoundName,
}

GameEvent :: union {
	LoadLevelEvent,
	PlaySoundEvent,
}

Vec2 :: [2]f32

Rect :: struct {
	x, y, w, h: f32,
}

EntityKind :: enum {
	nil,
	lemming,
	trapdoor,
	exit,
}

AnimState :: struct {
	index:    f32,
	playing:  bool,
	loop:     bool,
	finished: bool,
}

Entity :: struct {
	kind:           EntityKind,
	pos:            Vec2,
	velocity:       Vec2,
	body_collider:  Rect,
	floor_collider: Rect,
	flip_x:         bool,
	speed:          f32,
	fall_distance:  f32,
	action_timer:   f32,
	action_count:   i32,
	anim:           AnimationName,
	anim_state:     AnimState,
}

Game :: struct {
	level:         Level,
	current_level: a.LevelName,
	events:        [dynamic]GameEvent,
}

init :: proc() -> ^Game {
	animations_init()
	game := new(Game)
	game^ = Game {
		events = make([dynamic]GameEvent),
	}
	append(&game.events, LoadLevelEvent{level = .Level0101})
	return game
}

set_level :: proc(game: ^Game, name: a.LevelName, terrain_data: [^]u8, width, height: i32) {
	if game.level.lemmings != nil {
		level_destroy(&game.level)
	}
	game.current_level = name
	game.level = level_create(game.current_level, terrain_data, width, height)
}

destroy :: proc(game: ^Game) {
	delete(game.events)
	level_destroy(&game.level)
	animations_destroy()
	free(game)
}
