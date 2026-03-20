package engine

import "core"
import "vendor:fontstash"

FONT_ATLAS_SIZE :: 1024

@(private = "file")
Font_Data :: struct {
	fs_font: int, // fontstash font index
	atlas:   Texture,
}

@(private = "package")
Text_State :: struct {
	fs:    fontstash.FontContext,
	fonts: [dynamic]Font_Data,
}

@(private = "package")
text_state: Text_State

@(private = "file")
DEFAULT_FONT :: #load("fonts/roboto.ttf")

// Initialize the text subsystem. Called from on_renderer_initialized.
@(private = "package")
text_init :: proc() {
	fontstash.Init(&text_state.fs, FONT_ATLAS_SIZE, FONT_ATLAS_SIZE, .TOPLEFT)
	fontstash.SetAlignVertical(&text_state.fs, .TOP)

	// Set up the atlas resize callback so we can recreate the GPU texture.
	text_state.fs.callbackResize = _on_atlas_resize

	// Sentinel at index 0 (invalid font).
	text_state.fonts = make([dynamic]Font_Data)
	append(&text_state.fonts, Font_Data{})

	// Load the embedded default font.
	_ = load_font(DEFAULT_FONT)
}

// Shut down the text subsystem. Called from engine_shutdown.
@(private = "package")
text_shutdown :: proc() {
	// Destroy font atlas textures.
	for &fd in text_state.fonts {
		if fd.atlas.handle != {} {
			ctx.renderer.destroy_texture(fd.atlas.handle)
			fd.atlas.handle = {}
		}
	}
	delete(text_state.fonts)
	fontstash.Destroy(&text_state.fs)
}

// Load a font from TTF data. Returns a Font handle.
load_font :: proc(data: []u8) -> Font {
	fs := &text_state.fs
	idx := fontstash.AddFontMem(fs, "font", data, false)
	if idx == fontstash.INVALID {
		return Font(0)
	}

	// Create the atlas texture for this font entry.
	// All fonts share the same fontstash atlas, so only create a texture once.
	atlas_tex: Texture
	if len(text_state.fonts) == 1 {
		// First real font — create the atlas texture.
		atlas_tex = Texture {
			handle = ctx.renderer.create_texture_empty(fs.width, fs.height),
			width  = fs.width,
			height = fs.height,
		}
	} else {
		// Reuse the atlas texture from the first font.
		atlas_tex = text_state.fonts[1].atlas
	}

	append(&text_state.fonts, Font_Data{fs_font = idx, atlas = atlas_tex})
	return Font(len(text_state.fonts) - 1)
}

// Get the default font handle.
get_default_font :: proc() -> Font {
	return Font(1) // First loaded font after sentinel.
}

// Draw text at the given position with the default font.
draw_text :: proc(text: string, pos: Vec2, size: f32, color: Color = WHITE) {
	draw_text_ex(get_default_font(), text, pos, size, color)
}

// Draw text at the given position with a specific font.
draw_text_ex :: proc(font: Font, text: string, pos: Vec2, size: f32, color: Color = WHITE) {
	if int(font) <= 0 || int(font) >= len(text_state.fonts) {
		return
	}

	fd := &text_state.fonts[int(font)]
	fs := &text_state.fs

	fontstash.SetFont(fs, fd.fs_font)
	fontstash.SetSize(fs, size)

	// Sync atlas to GPU before drawing.
	_update_font(fd)

	iter := fontstash.TextIterInit(fs, pos.x, pos.y, text)
	quad: fontstash.Quad

	for fontstash.TextIterNext(fs, &iter, &quad) {
		// After iterating, new glyphs may have been rasterized.
		_update_font(fd)

		// Build UV coordinates (already normalized 0-1 from fontstash).
		uv := [4][2]f32 {
			{quad.s0, quad.t0}, // top-left
			{quad.s1, quad.t0}, // top-right
			{quad.s1, quad.t1}, // bottom-right
			{quad.s0, quad.t1}, // bottom-left
		}

		// Build screen-space destination rect.
		dst := Rect {
			x = quad.x0,
			y = quad.y0,
			w = quad.x1 - quad.x0,
			h = quad.y1 - quad.y0,
		}

		ctx.renderer.push_quad(dst, uv, fd.atlas.handle, color)
	}
}

// Draw outlined text with the default font.
draw_text_outlined :: proc(
	text: string,
	pos: Vec2,
	size: f32,
	color: Color = WHITE,
	outline_color: Color = BLACK,
	outline_size: f32 = 1,
) {
	draw_text_outlined_ex(get_default_font(), text, pos, size, color, outline_color, outline_size)
}

// Draw outlined text with a specific font.
draw_text_outlined_ex :: proc(
	font: Font,
	text: string,
	pos: Vec2,
	size: f32,
	color: Color = WHITE,
	outline_color: Color = BLACK,
	outline_size: f32 = 1,
) {
	d := int(outline_size)
	if d < 1 {
		d = 1
	}

	// Draw outline passes at surrounding offsets.
	for dy in -d ..= d {
		for dx in -d ..= d {
			if dx == 0 && dy == 0 {
				continue
			}
			draw_text_ex(font, text, {pos.x + f32(dx), pos.y + f32(dy)}, size, outline_color)
		}
	}

	// Draw main text on top.
	draw_text_ex(font, text, pos, size, color)
}

// Measure the dimensions of text with the default font.
measure_text :: proc(text: string, size: f32) -> Vec2 {
	return measure_text_ex(get_default_font(), text, size)
}

// Measure the dimensions of text with a specific font.
measure_text_ex :: proc(font: Font, text: string, size: f32) -> Vec2 {
	if int(font) <= 0 || int(font) >= len(text_state.fonts) {
		return {}
	}

	fd := &text_state.fonts[int(font)]
	fs := &text_state.fs

	fontstash.SetFont(fs, fd.fs_font)
	fontstash.SetSize(fs, size)

	bounds: [4]f32
	advance := fontstash.TextBounds(fs, text, 0, 0, &bounds)
	_, _, line_height := fontstash.VerticalMetrics(fs)

	return {advance, line_height}
}

// Sync any dirty atlas regions to the GPU texture.
@(private = "file")
_update_font :: proc(fd: ^Font_Data) {
	fs := &text_state.fs
	dirty: [4]f32

	if !fontstash.ValidateTexture(fs, &dirty) {
		return
	}

	// Extract dirty region dimensions.
	dx := int(dirty[0])
	dy := int(dirty[1])
	dw := int(dirty[2]) - dx
	dh := int(dirty[3]) - dy

	if dw <= 0 || dh <= 0 {
		return
	}

	// Expand single-channel atlas data to RGBA for the dirty region.
	rgba := make([]u8, dw * dh * 4)
	defer delete(rgba)

	for row in 0 ..< dh {
		for col in 0 ..< dw {
			src_idx := (dy + row) * fs.width + (dx + col)
			alpha := fs.textureData[src_idx]
			dst_idx := (row * dw + col) * 4
			rgba[dst_idx + 0] = 255
			rgba[dst_idx + 1] = 255
			rgba[dst_idx + 2] = 255
			rgba[dst_idx + 3] = alpha
		}
	}

	ctx.renderer.update_texture(fd.atlas.handle, rgba, dx, dy, dw, dh)
}

// Called by fontstash when the atlas needs to expand.
@(private = "file")
_on_atlas_resize :: proc(data: rawptr, w, h: int) {
	// Destroy old atlas texture and create a new, larger one.
	if len(text_state.fonts) > 1 {
		old_handle := text_state.fonts[1].atlas.handle
		if old_handle != {} {
			ctx.renderer.destroy_texture(old_handle)
		}

		new_atlas := Texture {
			handle = ctx.renderer.create_texture_empty(w, h),
			width  = w,
			height = h,
		}

		// Update all font entries to point to the new atlas.
		for i in 1 ..< len(text_state.fonts) {
			text_state.fonts[i].atlas = new_atlas
		}
	}
}
