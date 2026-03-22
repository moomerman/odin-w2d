#+build !darwin
#+build !js
package engine

@(private = "package")
_autorelease_pool_begin :: proc() -> rawptr {
	return nil
}

@(private = "package")
_autorelease_pool_end :: proc(_: rawptr) {}
