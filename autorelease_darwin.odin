#+build darwin
package engine

import NS "core:sys/darwin/Foundation"

@(private = "package")
_autorelease_pool_begin :: proc() -> rawptr {
	return NS.AutoreleasePool.alloc()->init()
}

@(private = "package")
_autorelease_pool_end :: proc(pool: rawptr) {
	if pool != nil {
		(cast(^NS.AutoreleasePool)pool)->drain()
	}
}
