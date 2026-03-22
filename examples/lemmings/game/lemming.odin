package game

lemming_create :: proc(pos: Vec2) -> Entity {
	return {
		kind = .lemming,
		pos = pos,
		anim = .Walk,
		anim_state = {playing = true, index = 0, loop = true},
		velocity = {1, 0},
		body_collider = {4, 0, 8, 16},
		floor_collider = {8, 15, 1, 1},
		speed = 12,
	}
}

lemming_update :: proc(game: ^Game, lemming: ^Entity, dt: f32) {
	level := &game.level
	feet_x :=
		lemming.pos.x +
		(lemming.flip_x ? (16 - lemming.floor_collider.x - lemming.floor_collider.w) : lemming.floor_collider.x)
	feet := Vec2{feet_x, lemming.pos.y + lemming.floor_collider.y}

	switch lemming.anim {
	case .None, .Splat, .Rescue, .Trapdoor, .Exit:
	case .Block:
		if !terrain_is_solid(&level.terrain, i32(feet.x), i32(feet.y)) {
			lemming_state_walk(lemming)
		}
	case .Dig:
		dig_speed: f32 = 0.5
		if lemming.action_timer > 0 {
			lemming.action_timer -= dt
			break
		} else {
			lemming.action_timer = dig_speed
		}
		if terrain_is_solid(&level.terrain, i32(feet.x), i32(feet.y)) {
			terrain_remove_rect(&level.terrain, {feet.x - 2, feet.y, 5, 1})
			lemming.pos.y += 1
		} else {
			lemming_state_walk(lemming)
		}
	case .Fall:
		lemming.fall_distance += lemming.velocity.y * lemming.speed * dt
		if terrain_is_solid(&level.terrain, i32(feet.x), i32(feet.y)) {
			lemming_state_walk(lemming)
		}
	case .Walk:
		if lemming.fall_distance != 0 {
			if lemming.fall_distance >= 53 {
				lemming_state_splat(lemming)
				append(&game.events, PlaySoundEvent{sound = .Splat})
			} else {
				lemming.fall_distance = 0
			}
		}

		// step up for up to 4 pixels or turn around
		if terrain_is_solid(&level.terrain, i32(feet.x), i32(feet.y - 1)) {
			step_up := false
			for step in i32(1) ..= i32(4) {
				if !terrain_is_solid(&level.terrain, i32(feet.x), i32(feet.y) - step - 1) {
					lemming.pos.y -= f32(step)
					step_up = true
					break
				}
			}
			if !step_up {
				lemming.flip_x = !lemming.flip_x
				lemming.velocity.x = -1 * lemming.velocity.x
			}
		}

		// step down for up to 4 pixels or fall
		if !terrain_is_solid(&level.terrain, i32(feet.x), i32(feet.y)) {
			step_down := false
			for step in i32(1) ..= i32(4) {
				if terrain_is_solid(&level.terrain, i32(feet.x), i32(feet.y) + step) {
					lemming.pos.y += f32(step)
					step_down = true
					break
				}
			}
			if !step_down {
				lemming_state_fall(lemming)
				break
			}
		}

		// check if there is a blocker in front, turn around if so
		for &other in level.lemmings {
			if other.anim != .Block do continue
			if &other == lemming do continue

			blocker_rect := get_entity_collider(other, other.body_collider)
			entity_rect := get_entity_collider(lemming^, lemming.body_collider)

			blocker_in_front :=
				(lemming.velocity.x > 0 && blocker_rect.x >= entity_rect.x) ||
				(lemming.velocity.x < 0 && blocker_rect.x <= entity_rect.x)

			if blocker_in_front && rects_intersect(entity_rect, blocker_rect) {
				lemming.flip_x = !lemming.flip_x
				lemming.velocity.x = -1 * lemming.velocity.x
				break
			}
		}
	}

	if (lemming.anim == .Rescue || lemming.anim == .Splat) && lemming.anim_state.finished {
		lemming_remove(level, lemming)
	}
}

lemming_remove :: proc(level: ^Level, lemming: ^Entity) {
	#partial switch lemming.anim {
	case .Rescue:
		level.rescue_count += 1
	case .Splat:
	}

	for i in 0 ..< len(level.lemmings) {
		if &level.lemmings[i] == lemming {
			ordered_remove(&level.lemmings, i)
			break
		}
	}
}

lemming_state_walk :: proc(entity: ^Entity) {
	entity.action_count = 0
	entity.anim = .Walk
	entity.anim_state = {
		playing = true,
		loop    = true,
	}
	if entity.flip_x {
		entity.velocity = {-1, 0}
	} else {
		entity.velocity = {1, 0}
	}
}

lemming_state_splat :: proc(lemming: ^Entity) {
	lemming.anim = .Splat
	lemming.anim_state = {
		playing = true,
	}
	lemming.velocity = {0, 0}
}

lemming_state_fall :: proc(lemming: ^Entity) {
	lemming.anim = .Fall
	lemming.velocity = {0, 2}
	lemming.anim_state = {
		playing = true,
		loop    = true,
	}
}

lemming_state_release :: proc(lemming: ^Entity) {
	lemming.anim = .Rescue
	lemming.anim_state = {
		playing = true,
	}
	lemming.velocity = {0, 0}
}
