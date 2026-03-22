package game

import a "../assets"

LevelConfig :: struct {
	texture:        a.LevelName,
	music:          a.MusicName,
	trapdoor:       Entity,
	trapdoor_pos:   [2]f32,
	exit_pos:       [2]f32,
	spawn_pos:      Vec2,
	spawn_rate:     f32,
	lemming_count:  int,
	target_percent: int,
	diggers:        int,
	blockers:       int,
}

levels := [a.LevelName]LevelConfig {
	.None = {},
	.Level0101 = {
		texture = .Level0101,
		music = .Track11,
		trapdoor_pos = {707, 36},
		exit_pos = {852, 108},
		spawn_pos = {720, 42},
		spawn_rate = 2,
		lemming_count = 10,
		target_percent = 10,
		diggers = 10,
		blockers = 10,
	},
	.Level0102 = {
		texture = .Level0102,
		music = .Track2,
		trapdoor_pos = {530, 8},
		exit_pos = {707, 100},
		spawn_pos = {707, 36},
		spawn_rate = 2,
		target_percent = 10,
		diggers = 10,
		blockers = 10,
	},
	.Level0103 = {
		texture = .Level0103,
		music = .Track7,
		trapdoor_pos = {612, 4},
		exit_pos = {707, 100},
		spawn_pos = {707, 36},
		spawn_rate = 2,
		target_percent = 10,
		diggers = 10,
		blockers = 10,
	},
	.Level0104 = {
		texture = .Level0104,
		music = .Track3,
		trapdoor_pos = {643, 12},
		exit_pos = {707, 100},
		spawn_pos = {707, 36},
		spawn_rate = 2,
		target_percent = 10,
		diggers = 10,
		blockers = 10,
	},
}
