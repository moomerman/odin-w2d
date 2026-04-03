package engine

// Set a scissor rectangle to clip all subsequent drawing to the given region.
// Coordinates are in logical pixels (matching screen/draw coordinates).
// Only pixels inside the rectangle will be affected by draw calls.
//
// Call reset_scissor_rect() to restore full-viewport drawing.
//
// Example:
//   w.set_scissor_rect({100, 100, 400, 300})
//   // draw calls here are clipped to the 400x300 region
//   w.reset_scissor_rect()
set_scissor_rect :: proc(rect: Rect) {
	ctx.renderer.set_scissor_rect(rect)
}

// Reset the scissor rectangle, restoring drawing to the full viewport.
reset_scissor_rect :: proc() {
	ctx.renderer.set_scissor_rect(nil)
}
