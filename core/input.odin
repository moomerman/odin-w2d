package core

Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}

// Physical keyboard keys. Values match SDL3 scancodes for efficient desktop mapping.
Key :: enum u16 {
	// Letters
	A = 4,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,

	// Digits
	Key_1 = 30,
	Key_2,
	Key_3,
	Key_4,
	Key_5,
	Key_6,
	Key_7,
	Key_8,
	Key_9,
	Key_0,

	// Common keys
	Return = 40,
	Escape = 41,
	Backspace = 42,
	Tab = 43,
	Space = 44,

	// Punctuation
	Minus = 45,
	Equals = 46,
	Left_Bracket = 47,
	Right_Bracket = 48,
	Backslash = 49,
	Semicolon = 51,
	Apostrophe = 52,
	Grave = 53,
	Comma = 54,
	Period = 55,
	Slash = 56,

	// Function keys
	F1 = 58,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,

	// Navigation
	Insert = 73,
	Home = 74,
	Page_Up = 75,
	Delete = 76,
	End = 77,
	Page_Down = 78,

	// Arrows
	Right = 79,
	Left = 80,
	Down = 81,
	Up = 82,

	// Modifiers
	Left_Ctrl = 224,
	Left_Shift = 225,
	Left_Alt = 226,
	Left_Super = 227,
	Right_Ctrl = 228,
	Right_Shift = 229,
	Right_Alt = 230,
	Right_Super = 231,
}

Event :: union {
	Mouse_Move_Event,
	Mouse_Button_Event,
	Key_Event,
}

Mouse_Move_Event :: struct {
	pos:   Vec2,
	delta: Vec2,
}

Mouse_Button_Event :: struct {
	button: Mouse_Button,
	down:   bool, // true = pressed, false = released
	pos:    Vec2,
}

Key_Event :: struct {
	key:    Key,
	down:   bool, // true = pressed, false = released
	repeat: bool, // true if this is a key-repeat event
}
