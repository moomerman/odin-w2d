// UI example — a horizontal toolbar with padding, hover/click states, and
// animated transitions, plus a row of clickable cards.
package main

import w "../.."
import ui "../../ui"

BG :: w.Color{24, 26, 32, 255}
BAR :: w.Color{35, 38, 46, 255}
CARD :: w.Color{44, 48, 58, 255}
CARD_HOVER :: w.Color{56, 61, 74, 255}
ACCENT :: w.Color{0, 121, 241, 255}

TAB :: ui.Style {
	px = 14,
	py = 8,
	radius = 6,
	fg = w.WHITE,
	hover = {bg = CARD_HOVER, scale = 1.05},
	press = {offset = {0, 1}},
	transition = 0.15,
	cursor = .Pointer,
}

tabs := [?]string{"Home", "Library", "Settings"}
active_tab := 0
plays := 0

main :: proc() {
	w.init(1280, 720, "UI Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	ui.init()
}

frame :: proc(_: f32) {
	w.clear(BG)

	if ui.frame() {
		if ui.vbox({w = ui.pct(100), h = ui.pct(100)}) {
			// Toolbar: horizontal, padded, animated hover on each tab.
			if ui.hbox({w = ui.GROW, p = 12, gap = 8, bg = BAR, align = .Center}) {
				ui.label("my game", {fg = w.WHITE, font_size = 22})
				ui.spacer()
				for tab, i in tabs {
					if ui.button(
						tab,
						ui.merge(TAB, {bg = i == active_tab ? ACCENT : w.BLANK}),
						idx = i,
					) {
						active_tab = i
					}
				}
			}

			// Content: a row of clickable cards — any container is interactive.
			if ui.hbox({p = 24, gap = 16}) {
				for i in 0 ..< 3 {
					if ui.vbox(
						{
							w = 160,
							h = 100,
							p = 12,
							gap = 6,
							radius = 8,
							bg = CARD,
							hover = {bg = CARD_HOVER},
							transition = 0.2,
							cursor = .Pointer,
						},
						idx = i,
					) {
						if ui.clicked() {
							plays += 1
						}
						ui.label("LEVEL", {fg = w.LIGHT_GRAY, font_size = 12})
						ui.label(tabs[i % len(tabs)], {fg = w.WHITE, font_size = 20})
					}
				}
			}
		}
	}

	w.present()
}

shutdown :: proc() {
	ui.shutdown()
}
