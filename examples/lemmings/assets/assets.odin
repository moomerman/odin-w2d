package assets

LevelName :: enum {
	None,
	Level0101,
	Level0102,
	Level0103,
	Level0104,
}

MusicName :: enum {
	None,
	Track2,
	Track3,
	Track7,
	Track11,
}

SoundName :: enum {
	None,
	LetsGo,
	Splat,
	Yippee,
}

TextureName :: enum {
	None,
	Cursor,
	Exits,
	Lemmings,
	Trapdoors,
}

levels := [LevelName][]u8 {
	.None      = {},
	.Level0101 = #load("levels/orig/0101.png"),
	.Level0102 = #load("levels/orig/0102.png"),
	.Level0103 = #load("levels/orig/0103.png"),
	.Level0104 = #load("levels/orig/0104.png"),
}

music := [MusicName][]u8 {
	.None    = {},
	.Track2  = #load("music/track2.mp3"),
	.Track3  = #load("music/track3.mp3"),
	.Track7  = #load("music/track7.mp3"),
	.Track11 = #load("music/track11.mp3"),
}

sounds := [SoundName][]u8 {
	.None   = {},
	.LetsGo = #load("sound/letsgo.wav"),
	.Splat  = #load("sound/splat.wav"),
	.Yippee = #load("sound/yippee.wav"),
}

textures := [TextureName][]u8 {
	.None      = {},
	.Cursor    = #load("texture/cursor.png"),
	.Exits     = #load("texture/exits.png"),
	.Lemmings  = #load("texture/lemmings.png"),
	.Trapdoors = #load("texture/trapdoors.png"),
}
