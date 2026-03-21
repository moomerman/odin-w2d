// Audio example — press Space to play a click sound.
package main

import w "../.."

CLICK_WAV :: #load("click.wav")

click: w.Audio_Source

main :: proc() {
	w.init(640, 480, "Audio Example")
	w.run(init, frame, shutdown)
}

init :: proc() {
	w.init_audio()
	click = w.load_audio_from_bytes(CLICK_WAV)
}

frame :: proc(dt: f32) {
	w.clear(w.DARK_GRAY)

	if w.key_went_down(.Space) {
		w.play_audio(click)
	}

	w.draw_text("Press SPACE to play a click", {180, 220}, 20)
	w.present()
}

shutdown :: proc() {
	w.destroy_audio(click)
	w.shutdown_audio()
}
