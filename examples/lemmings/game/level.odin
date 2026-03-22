package game

import a "../assets"

Level :: struct {
	config:          a.LevelName,
	terrain:         Terrain,
	lemmings:        [dynamic]Entity,
	current_lemming: ^Entity,
	trapdoor:        Entity,
	exit:            Entity,
	spawn_timer:     f32,
	spawn_rate:      f32,
	spawn_pos:       Vec2,
	current_action:  AnimationName,
	max_lemmings:    int,
	rescue_count:    int,
	diggers:         int,
}

level_create :: proc(name: a.LevelName, terrain_data: [^]u8, width, height: i32) -> Level {
	config := levels[name]
	level := Level {
		config         = name,
		terrain        = terrain_create(width, height, terrain_data),
		lemmings       = make([dynamic]Entity),
		trapdoor       = create_trapdoor(config.trapdoor_pos),
		exit           = create_exit(config.exit_pos),
		spawn_pos      = config.spawn_pos,
		spawn_rate     = config.spawn_rate,
		spawn_timer    = 2,
		diggers        = config.diggers,
		current_action = .Dig,
	}
	return level
}

level_update :: proc(level: ^Level, dt: f32) {
	level.spawn_timer += f32(dt)
	if level.spawn_timer >= level.spawn_rate {
		level.spawn_timer = -level.spawn_rate
		level_spawn_lemming(level, level.spawn_pos)
	}
}

level_destroy :: proc(level: ^Level) {
	terrain_destroy(&level.terrain)
	delete(level.lemmings)
}

level_spawn_lemming :: proc(level: ^Level, pos: Vec2) {
	lemming := lemming_create(pos)
	append(&level.lemmings, lemming)
}

create_trapdoor :: proc(pos: Vec2) -> Entity {
	return {kind = .trapdoor, pos = pos, anim = .Trapdoor, anim_state = {playing = true}}
}

create_exit :: proc(pos: Vec2) -> Entity {
	return {
		kind = .exit,
		pos = pos,
		anim = .Exit,
		anim_state = {playing = true, loop = true},
		floor_collider = {25, 24, 35 - 25, 1},
	}
}
