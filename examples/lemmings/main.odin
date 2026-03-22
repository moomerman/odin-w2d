// odin run examples/lemmings

package main

import w "../.."

import "core:image"
import _ "core:image/png"
import "core:slice"

import a "./assets"
import g "./game"

game: ^g.Game

UTILITY_BAR_HEIGHT :: 70
LEVEL_HEIGHT :: 160
MIN_ZOOM :: 2
MAX_ZOOM :: 4
WINDOW_WIDTH :: 320 * MAX_ZOOM
WINDOW_HEIGHT :: LEVEL_HEIGHT * MAX_ZOOM + UTILITY_BAR_HEIGHT

splat: w.Audio_Source
letsgo: w.Audio_Source
yippee: w.Audio_Source
music: w.Audio_Source

terrain_tex: w.Texture
lemmings_tex: w.Texture
trapdoors_tex: w.Texture
exits_tex: w.Texture

// Camera

Camera :: struct {
	target: w.Vec2,
	offset: w.Vec2,
	zoom:   f32,
}

camera: Camera

main :: proc() {
	w.init(WINDOW_WIDTH, WINDOW_HEIGHT, "Lemmings!")
	w.run(init, frame, shutdown)
}

init :: proc() {
	w.init_audio()
	splat = w.load_audio_from_bytes(a.sounds[.Splat])
	letsgo = w.load_audio_from_bytes(a.sounds[.LetsGo])
	yippee = w.load_audio_from_bytes(a.sounds[.Yippee])
	update_camera()
	lemmings_tex = w.load_texture(a.textures[.Lemmings])
	trapdoors_tex = w.load_texture(a.textures[.Trapdoors])
	exits_tex = w.load_texture(a.textures[.Exits])
	game = g.init()
}

frame :: proc(dt: f32) {
	w.clear(w.DARK_BLUE)

	for event in game.events {
		switch e in event {
		case g.LoadLevelEvent:
			load_level(e.level)
		case g.PlaySoundEvent:
			play_sound(e.sound)
		}
	}
	clear(&game.events)

	{ 	// input
		if w.key_is_held(.Left) || w.key_is_held(.A) {
			camera.target.x += -200 * dt
		}
		if w.key_is_held(.Right) || w.key_is_held(.D) {
			camera.target.x += 200 * dt
		}
		if game.level.current_lemming == nil && w.mouse_button_is_held(.Left) {
			mouse_world := screen_to_world(w.get_mouse_position())
			mx := i32(mouse_world.x)
			my := i32(mouse_world.y)
			if my >= 0 && my < game.level.terrain.height {
				g.terrain_remove_circle(&game.level.terrain, mx, my, 8)
			}
		}
	}

	{ 	// update
		update_camera()
		g.update(
			game,
			screen_to_world(w.get_mouse_position()),
			w.mouse_button_went_down(.Left),
			dt,
		)
		update_terrain()
	}

	{ 	// draw game level
		render_frame()
	}

	{ 	// draw ui
		draw_utility_bar()
	}

	w.draw_stats()
	w.present()
	free_all(context.temp_allocator)
}

shutdown :: proc() {
	g.destroy(game)
	w.destroy_audio(music)
	w.destroy_audio(letsgo)
	w.destroy_audio(splat)
	w.destroy_audio(yippee)
	w.destroy_texture(&terrain_tex)
	w.destroy_texture(&lemmings_tex)
	w.destroy_texture(&trapdoors_tex)
	w.destroy_texture(&exits_tex)
	w.shutdown_audio()
}

// Camera helpers

screen_to_world :: proc(screen_pos: w.Vec2) -> w.Vec2 {
	return {
		(screen_pos.x - camera.offset.x) / camera.zoom + camera.target.x,
		(screen_pos.y - camera.offset.y) / camera.zoom + camera.target.y,
	}
}

world_to_screen :: proc(world_pos: w.Vec2) -> w.Vec2 {
	return {
		(world_pos.x - camera.target.x) * camera.zoom + camera.offset.x,
		(world_pos.y - camera.target.y) * camera.zoom + camera.offset.y,
	}
}

update_camera :: proc() {
	screen_w, screen_h := w.get_screen_size()
	available_height := f32(screen_h) - UTILITY_BAR_HEIGHT
	desired_zoom := available_height / LEVEL_HEIGHT
	camera.zoom = clamp(desired_zoom, MIN_ZOOM, MAX_ZOOM)
	camera.offset.x = f32(screen_w) / 2

	// limit scrolling to terrain
	half_view := camera.offset.x / camera.zoom
	level_width := f32(terrain_tex.width)
	camera.target.x = clamp(camera.target.x, half_view, max(level_width - half_view, half_view))
}

update_terrain :: proc() {
	if game.level.terrain.dirty {
		pixel_bytes := slice.reinterpret([]u8, game.level.terrain.pixels)
		w.update_texture(
			terrain_tex,
			pixel_bytes,
			0,
			0,
			int(game.level.terrain.width),
			int(game.level.terrain.height),
		)
		game.level.terrain.dirty = false
	}
}

render_frame :: proc() {
	draw_world_texture(terrain_tex, {0, 0})
	draw_entity(trapdoors_tex, game.level.trapdoor)
	draw_entity(exits_tex, game.level.exit)
	draw_lemmings(game)
}

draw_utility_bar :: proc() {
	screen_w, screen_h := w.get_screen_size()
	bar_y := f32(screen_h) - UTILITY_BAR_HEIGHT
	w.draw_rect({0, bar_y, f32(screen_w), UTILITY_BAR_HEIGHT}, w.DARK_GRAY)
}

draw_lemmings :: proc(game: ^g.Game) {
	for &lemming in game.level.lemmings {
		draw_entity(lemmings_tex, lemming)
	}
}

draw_entity :: proc(tex: w.Texture, e: g.Entity) {
	sprite := g.anim_get_frame(e.anim_state, g.all_animations[e.anim])
	draw_world_sprite(tex, sprite, e.pos, e.flip_x)
}

// Draw a full texture in world space (applies camera transform and zoom).
draw_world_texture :: proc(tex: w.Texture, world_pos: w.Vec2) {
	screen_pos := world_to_screen(world_pos)
	src := w.Rect{0, 0, f32(tex.width), f32(tex.height)}
	dst := w.Rect {
		screen_pos.x,
		screen_pos.y,
		f32(tex.width) * camera.zoom,
		f32(tex.height) * camera.zoom,
	}
	w.draw_texture_rect(tex, src, dst)
}

// Draw a sprite from a texture atlas in world space (applies camera transform and zoom).
draw_world_sprite :: proc(
	tex: w.Texture,
	sprite: g.Sprite,
	world_pos: w.Vec2,
	flip_x: bool = false,
) {
	screen_pos := world_to_screen(world_pos)
	src := w.Rect{sprite.source.x, sprite.source.y, sprite.source.w, sprite.source.h}
	if flip_x {
		src.x = src.x + src.w
		src.w = -src.w
	}
	dst := w.Rect {
		screen_pos.x,
		screen_pos.y,
		abs(sprite.source.w) * camera.zoom,
		sprite.source.h * camera.zoom,
	}
	w.draw_texture_rect(tex, src, dst)
}

load_level :: proc(name: a.LevelName) {
	config := g.levels[name]
	texture_data := a.levels[config.texture]
	music = w.load_audio_from_bytes(a.music[config.music], .Stream)

	if terrain_tex.width != 0 {
		w.destroy_texture(&terrain_tex)
	}

	terrain_tex = w.load_texture(texture_data)

	img, img_err := image.load_from_bytes(texture_data, {.alpha_add_if_missing})
	if img_err != nil {
		return
	}
	defer image.destroy(img)

	g.set_level(game, name, raw_data(img.pixels.buf), i32(img.width), i32(img.height))

	camera.target.x = f32(terrain_tex.width) / 2

	w.play_audio(letsgo)
	params := w.default_audio_play_params()
	params.delay = 1.75
	params.loop = true
	params.volume = 0.05
	w.play_audio(music, params)
}

play_sound :: proc(name: a.SoundName) {
	#partial switch name {
	case .Splat:
		w.play_audio(splat)
	case .Yippee:
		w.play_audio(yippee)
	}
}
