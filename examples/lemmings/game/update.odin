package game

update :: proc(g: ^Game, mouse: Vec2, click: bool, dt: f32) {
	// detect clicking on current lemming
	if click &&
	   g.level.current_lemming != nil &&
	   g.level.current_lemming.anim != g.level.current_action {
		g.level.current_lemming.anim = g.level.current_action
		g.level.current_lemming.anim_state = {
			playing = true,
			loop    = true,
		}
		g.level.current_lemming.velocity = {0, 0}
	}

	clear(&g.events)
	update_animations(g, dt)
	update_lemmings(g, dt)
	level_update(&g.level, dt)

	// detect hovering over a lemming and set as current
	g.level.current_lemming = nil
	for &lemming in g.level.lemmings {
		lemming_rect := get_entity_collider(lemming, lemming.body_collider)
		if point_in_rect(mouse, lemming_rect) {
			g.level.current_lemming = &lemming
			break
		}
	}
}

update_animations :: proc(g: ^Game, dt: f32) {
	for &lemming in g.level.lemmings {
		entity_anim_update(&lemming, dt)
	}
	entity_anim_update(&g.level.trapdoor, dt)
	entity_anim_update(&g.level.exit, dt)
}

update_lemmings :: proc(g: ^Game, dt: f32) {
	for &lemming in g.level.lemmings {
		lemming_update(g, &lemming, dt)
		move_entity(&lemming, dt)
		if lemming.anim != .Rescue {
			check_exit_collision(g, &lemming)
		}
	}
}

check_exit_collision :: proc(game: ^Game, lemming: ^Entity) {
	lemming_rect := get_entity_collider(lemming^, lemming.body_collider)
	exit_rect := get_entity_collider(game.level.exit, game.level.exit.floor_collider)
	if rects_intersect(lemming_rect, exit_rect) {
		lemming_state_release(lemming)
		append(&game.events, PlaySoundEvent{sound = .Yippee})
	}
}

entity_anim_update :: proc(e: ^Entity, dt: f32) {
	anim_update(&e.anim_state, all_animations[e.anim], dt)
}

move_entity :: proc(entity: ^Entity, dt: f32) {
	if entity.velocity == {0, 0} || entity.speed == 0 do return
	entity.pos.x += entity.velocity.x * entity.speed * dt
	entity.pos.y += entity.velocity.y * entity.speed * dt
}

get_entity_collider :: proc(entity: Entity, collider: Rect) -> Rect {
	return {
		x = entity.pos.x + collider.x,
		y = entity.pos.y + collider.y,
		w = collider.w,
		h = collider.h,
	}
}

rects_intersect :: proc(a, b: Rect) -> bool {
	return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

point_in_rect :: proc(p: Vec2, r: Rect) -> bool {
	return p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h
}
