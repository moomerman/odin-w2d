// odin run examples/showcase
// odin run tools/build_web -- examples/showcase --serve
//
// A showcase demonstrating all engine features in one interactive scene:
// rendering (rects, lines, textures), text (outlined, measured), input (keyboard,
// mouse, scroll), audio (stereo panning), custom shaders (animated background),
// and the stats overlay.

package main

import w "../.."

import "core:fmt"
import "core:math"
import "core:math/rand"

// --- Constants ---

MAX_PARTICLES :: 400
CONNECTION_DIST :: 100.0
CONNECTION_CHECK :: 20
SPAWN_RATE :: 30.0
BURST_COUNT :: 40
DAMPING :: 0.985
FORCE_STRENGTH :: 300.0

// --- Types ---

Mode :: enum {
	Attract,
	Repel,
	Orbit,
	Explode,
}

Particle :: struct {
	pos:      w.Vec2,
	vel:      w.Vec2,
	hue:      f32,
	size:     f32,
	life:     f32,
	max_life: f32,
	active:   bool,
}

// --- State ---

particles: [MAX_PARTICLES]Particle
current_mode: Mode
base_size: f32
hue_offset: f32
spawn_timer: f32
show_connections: bool
show_stats_overlay: bool
active_count: int

bg_shader: w.Shader
click_sound: w.Audio_Source
glow_tex: w.Texture

// --- Entry points ---

main :: proc() {
	w.init(1280, 720, "Particle Symphony")
	w.run(init, frame, shutdown)
}

init :: proc() {
	// Audio: load a click sound for burst feedback.
	w.init_audio()
	click_sound = w.load_audio_from_bytes(#load("../audio/click.wav"))
	w.set_audio_listener_position({640, 360})

	// Shader: animated aurora background.
	bg_shader = w.load_shader(#load("aurora.wgsl"))
	w.set_shader_uniform(&bg_shader, "intensity", f32(0.6))

	// Texture: procedurally generate a soft radial glow (16x16 RGBA).
	GLOW_SIZE :: 16
	pixels: [GLOW_SIZE * GLOW_SIZE * 4]u8
	glow_center := f32(GLOW_SIZE) / 2.0
	for y in 0 ..< GLOW_SIZE {
		for x in 0 ..< GLOW_SIZE {
			dx := f32(x) - glow_center + 0.5
			dy := f32(y) - glow_center + 0.5
			dist := math.sqrt(dx * dx + dy * dy) / glow_center
			brightness := clamp(1.0 - dist, 0, 1)
			i := (y * GLOW_SIZE + x) * 4
			pixels[i + 0] = 255
			pixels[i + 1] = 255
			pixels[i + 2] = 255
			pixels[i + 3] = u8(brightness * brightness * 255)
		}
	}
	glow_tex = w.load_texture(pixels[:], GLOW_SIZE, GLOW_SIZE)

	// Defaults.
	current_mode = .Attract
	base_size = 5.0
	show_connections = true

	// Pre-populate with an initial burst from center.
	spawn_burst({640, 360}, 100)
}

frame :: proc(dt: f32) {
	handle_input()
	update_particles(dt)

	w.clear({8, 8, 16, 255})

	draw_background()
	if show_connections {
		draw_connections()
	}
	draw_particles()
	draw_ui()

	if show_stats_overlay {
		w.draw_stats()
	}

	w.present()
	free_all(context.temp_allocator)
}

shutdown :: proc() {
	w.destroy_texture(&glow_tex)
	w.destroy_shader(&bg_shader)
	w.destroy_audio(click_sound)
	w.shutdown_audio()
}

// --- Input ---

handle_input :: proc() {
	// Keyboard: switch particle behavior modes.
	if w.key_went_down(.Key_1) {
		current_mode = .Attract
	}
	if w.key_went_down(.Key_2) {
		current_mode = .Repel
	}
	if w.key_went_down(.Key_3) {
		current_mode = .Orbit
	}
	if w.key_went_down(.Key_4) {
		current_mode = .Explode
	}

	// Keyboard: burst spawn from screen center.
	if w.key_went_down(.Space) {
		spawn_burst({640, 360}, BURST_COUNT)
		play_burst_sound({640, 360})
	}

	// Mouse: burst spawn at cursor with stereo panning.
	if w.mouse_button_went_down(.Left) {
		mouse_pos := w.get_mouse_position()
		spawn_burst(mouse_pos, BURST_COUNT)
		play_burst_sound(mouse_pos)
	}

	// Scroll: adjust particle size.
	scroll := w.get_scroll_delta(include_momentum = false)
	base_size = clamp(base_size + scroll.y * 0.5, 2, 20)

	// Toggle keys.
	if w.key_went_down(.L) {
		show_connections = !show_connections
	}
	if w.key_went_down(.S) {
		show_stats_overlay = !show_stats_overlay
	}

	// Reset all particles.
	if w.key_went_down(.R) {
		for &p in particles {
			p.active = false
		}
		active_count = 0
	}
}

// --- Simulation ---

update_particles :: proc(dt: f32) {
	mouse := w.get_mouse_position()
	screen_w, screen_h := w.get_screen_size()
	sw := f32(screen_w)
	sh := f32(screen_h)

	hue_offset += dt * 30.0

	// Continuous spawning.
	spawn_timer += dt * SPAWN_RATE
	for spawn_timer >= 1.0 {
		spawn_timer -= 1.0
		pos := w.Vec2{rand.float32() * sw, rand.float32() * sh}
		vel := w.Vec2{rand.float32() * 40 - 20, rand.float32() * 40 - 20}
		spawn_particle(pos, vel)
	}

	// Physics update.
	active_count = 0
	for &p in particles {
		if !p.active {
			continue
		}

		p.life -= dt
		if p.life <= 0 {
			p.active = false
			continue
		}

		active_count += 1

		// Direction and distance to mouse.
		dx := mouse.x - p.pos.x
		dy := mouse.y - p.pos.y
		dist := math.sqrt(dx * dx + dy * dy)
		if dist < 1 {
			dist = 1
		}
		nx := dx / dist
		ny := dy / dist

		// Apply mode-specific forces.
		switch current_mode {
		case .Attract:
			strength := FORCE_STRENGTH / max(dist * 0.05, 1)
			p.vel.x += nx * strength * dt
			p.vel.y += ny * strength * dt
		case .Repel:
			strength := FORCE_STRENGTH * 3 / max(dist * 0.03, 1)
			p.vel.x -= nx * strength * dt
			p.vel.y -= ny * strength * dt
		case .Orbit:
			radial := FORCE_STRENGTH * 0.3 / max(dist * 0.02, 1)
			tangent := FORCE_STRENGTH * 0.6 / max(dist * 0.01, 1)
			p.vel.x += nx * radial * dt - ny * tangent * dt
			p.vel.y += ny * radial * dt + nx * tangent * dt
		case .Explode:
			cdx := p.pos.x - sw / 2
			cdy := p.pos.y - sh / 2
			cdist := math.sqrt(cdx * cdx + cdy * cdy)
			if cdist > 1 {
				p.vel.x += (cdx / cdist) * FORCE_STRENGTH * dt
				p.vel.y += (cdy / cdist) * FORCE_STRENGTH * dt
			}
		}

		// Damping and integration.
		p.vel *= DAMPING
		p.pos += p.vel * dt

		// Wrap around screen edges.
		if p.pos.x < -20 {
			p.pos.x = sw + 20
		}
		if p.pos.x > sw + 20 {
			p.pos.x = -20
		}
		if p.pos.y < -20 {
			p.pos.y = sh + 20
		}
		if p.pos.y > sh + 20 {
			p.pos.y = -20
		}
	}
}

// --- Rendering ---

draw_background :: proc() {
	screen_w, screen_h := w.get_screen_size()
	sw := f32(screen_w)
	sh := f32(screen_h)
	mouse := w.get_mouse_position()

	// Update shader uniforms each frame.
	w.set_shader_uniform(&bg_shader, "time", f32(w.get_time()))
	w.set_shader_uniform(&bg_shader, "mouse_x", mouse.x / sw)
	w.set_shader_uniform(&bg_shader, "mouse_y", mouse.y / sh)

	// Draw a full-screen quad with the aurora shader.
	w.set_shader(&bg_shader)
	w.draw_rect({0, 0, sw, sh}, w.WHITE)
	w.reset_shader()
}

draw_connections :: proc() {
	for i in 0 ..< MAX_PARTICLES {
		if !particles[i].active {
			continue
		}

		life_i := particles[i].life / particles[i].max_life
		limit := min(i + CONNECTION_CHECK, MAX_PARTICLES)

		for j in (i + 1) ..< limit {
			if !particles[j].active {
				continue
			}

			dx := particles[i].pos.x - particles[j].pos.x
			dy := particles[i].pos.y - particles[j].pos.y
			dist_sq := dx * dx + dy * dy

			if dist_sq > CONNECTION_DIST * CONNECTION_DIST {
				continue
			}

			dist := math.sqrt(dist_sq)
			life_j := particles[j].life / particles[j].max_life
			alpha := (1.0 - dist / CONNECTION_DIST) * min(life_i, life_j) * 0.4

			avg_hue := (particles[i].hue + particles[j].hue) / 2
			color := hsv_to_color(avg_hue, 0.6, 0.8, u8(alpha * 255))

			w.draw_line(particles[i].pos, particles[j].pos, 1, color)
		}
	}
}

draw_particles :: proc() {
	src := w.Rect{0, 0, f32(glow_tex.width), f32(glow_tex.height)}

	// Pass 1: outer glow (larger, softer, behind cores).
	for &p in particles {
		if !p.active {
			continue
		}
		alpha := clamp(p.life / p.max_life, 0, 1)
		glow_size := p.size * (0.5 + alpha * 0.5) * 2.5
		glow_color := hsv_to_color(p.hue, 0.4, 1.0, u8(alpha * 0.3 * 255))
		w.draw_texture_rect(
			glow_tex,
			src,
			{p.pos.x - glow_size, p.pos.y - glow_size, glow_size * 2, glow_size * 2},
			glow_color,
		)
	}

	// Pass 2: bright core (smaller, vivid, on top).
	for &p in particles {
		if !p.active {
			continue
		}
		alpha := clamp(p.life / p.max_life, 0, 1)
		core_size := p.size * (0.5 + alpha * 0.5)
		core_color := hsv_to_color(p.hue, 0.8, 1.0, u8(alpha * 255))
		w.draw_texture_rect(
			glow_tex,
			src,
			{p.pos.x - core_size, p.pos.y - core_size, core_size * 2, core_size * 2},
			core_color,
		)
	}
}

draw_ui :: proc() {
	screen_w, screen_h := w.get_screen_size()
	sw := f32(screen_w)
	sh := f32(screen_h)

	// Title: outlined text, centered at top.
	title := "PARTICLE SYMPHONY"
	title_size := w.measure_text(title, 36)
	w.draw_text_outlined(title, {(sw - title_size.x) / 2, 16}, 36, w.WHITE, {0, 0, 0, 200}, 2)

	// Mode indicator: top-right, color-cycling.
	mode_color := hsv_to_color(hue_offset * 2, 0.8, 1.0, 255)
	label := mode_name(current_mode)
	label_size := w.measure_text(label, 28)
	w.draw_text(label, {sw - label_size.x - 20, 20}, 28, mode_color)

	// Particle count: below title.
	w.draw_text(fmt.tprintf("Particles: %d", active_count), {20, 60}, 16, w.LIGHT_GRAY)

	// Controls panel: bottom, with dark background for readability.
	panel_y := sh - 70
	w.draw_rect({10, panel_y, sw - 20, 55}, {0, 0, 0, 100})
	w.draw_rect_outline({10, panel_y, sw - 20, 55}, 1, {255, 255, 255, 30})

	w.draw_text(
		"[1-4] Mode   [Space/Click] Burst   [Scroll] Size   [L] Lines   [S] Stats   [R] Reset",
		{20, panel_y + 8},
		14,
		{180, 180, 180, 255},
	)

	conn_label := show_connections ? "ON" : "OFF"
	w.draw_text(
		fmt.tprintf("Size: %.1f   Lines: %s", base_size, conn_label),
		{20, panel_y + 30},
		14,
		{140, 140, 140, 255},
	)
}

// --- Particle management ---

spawn_burst :: proc(origin: w.Vec2, count: int) {
	for _ in 0 ..< count {
		angle := rand.float32() * 2 * math.PI
		speed: f32 = 50 + rand.float32() * 250
		vel := w.Vec2{math.cos(angle) * speed, math.sin(angle) * speed}
		spawn_particle(origin, vel)
	}
}

spawn_particle :: proc(pos: w.Vec2, vel: w.Vec2) {
	for &p in particles {
		if p.active {
			continue
		}

		life: f32 = 2 + rand.float32() * 4
		p = Particle {
			pos      = pos,
			vel      = vel,
			hue      = hue_offset + rand.float32() * 120,
			size     = base_size * (0.5 + rand.float32()),
			life     = life,
			max_life = life,
			active   = true,
		}
		return
	}
}

play_burst_sound :: proc(pos: w.Vec2) {
	screen_w, _ := w.get_screen_size()
	params := w.default_audio_play_params()
	params.pan = (pos.x / f32(screen_w)) * 2.0 - 1.0
	params.pitch = 0.8 + rand.float32() * 0.6
	params.volume = 0.5
	w.play_audio(click_sound, params)
}

// --- Utilities ---

hsv_to_color :: proc(h, s, v: f32, a: u8 = 255) -> w.Color {
	// Wrap hue to [0, 360).
	h_norm := h - 360.0 * math.floor(h / 360.0)

	c := v * s
	sector := h_norm / 60.0
	sector_frac := sector - 2.0 * math.floor(sector / 2.0)
	x := c * (1.0 - abs(sector_frac - 1.0))
	m := v - c

	r, g, b: f32
	switch {
	case h_norm < 60:
		r = c
		g = x
	case h_norm < 120:
		r = x
		g = c
	case h_norm < 180:
		g = c
		b = x
	case h_norm < 240:
		g = x
		b = c
	case h_norm < 300:
		r = x
		b = c
	case:
		r = c
		b = x
	}

	return w.Color{u8((r + m) * 255), u8((g + m) * 255), u8((b + m) * 255), a}
}

mode_name :: proc(m: Mode) -> string {
	switch m {
	case .Attract:
		return "Attract"
	case .Repel:
		return "Repel"
	case .Orbit:
		return "Orbit"
	case .Explode:
		return "Explode"
	}
	return ""
}
