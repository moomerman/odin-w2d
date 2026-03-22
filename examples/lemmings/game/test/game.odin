package test

import "core:testing"

import game ".."

@(test)
game_smoke_test :: proc(t: ^testing.T) {
	g := game.init()
	defer game.destroy(g)
}
