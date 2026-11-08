#+build js
package engine

// Screenshots need a filesystem and a blocking readback; neither exists on web.
save_screenshot :: proc(path: string) -> bool {
	return false
}
