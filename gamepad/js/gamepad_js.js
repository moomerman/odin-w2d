// Browser Gamepad API implementation for the w2d gamepad package.
// Provides navigator.getGamepads() polling to Odin/WASM, packing a numeric
// snapshot into the WASM heap each frame.

const engineGamepad = {
  // Maps the browser "standard" mapping button indices onto w2d's
  // Gamepad_Button enum order:
  //   South,East,West,North, Left_Shoulder,Right_Shoulder,
  //   Left_Trigger,Right_Trigger, Left_Stick,Right_Stick,
  //   Dpad_Up,Dpad_Down,Dpad_Left,Dpad_Right, Start,Select,Guide
  // Value is the index into gamepad.buttons[]; -1 means "no source".
  BUTTON_SOURCE: [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 9, 8, 16],

  // Number of floats written per pad: 1 connected + 17 buttons + 6 axes.
  N_BUTTONS: 17,
  N_AXES: 6,
  get SLOTS_PER_PAD() {
    return 1 + this.N_BUTTONS + this.N_AXES
  },

  // Returns the live gamepad list (a fresh snapshot each call in most browsers).
  list: function () {
    if (!navigator.getGamepads) return []
    return navigator.getGamepads()
  },

  // The gamepad occupying w2d slot `index`, or null. Browsers report a stable
  // `gamepad.index`, so we match on that.
  atSlot: function (index) {
    for (const gp of this.list()) {
      if (gp && gp.index === index) return gp
    }
    return null
  },
}

window.engineGamepad = engineGamepad

;(function () {
  let wasmMemory = null

  // Called by the HTML entry after WASM instantiation so JS can write the heap.
  window.setGamepadWasmMemory = function (memory) {
    wasmMemory = memory
  }

  window.gamepadJsImports = {
    gamepad_js: {
      _js_poll_gamepads: (ptr, len) => {
        if (!wasmMemory) return
        const out = new Float32Array(wasmMemory.buffer, ptr, len)
        out.fill(0)

        const slots = len / engineGamepad.SLOTS_PER_PAD
        const stride = engineGamepad.SLOTS_PER_PAD
        for (let slot = 0; slot < slots; slot++) {
          const gp = engineGamepad.atSlot(slot)
          if (!gp) continue

          const base = slot * stride
          out[base] = 1 // connected

          // Buttons.
          for (let i = 0; i < engineGamepad.N_BUTTONS; i++) {
            const src = engineGamepad.BUTTON_SOURCE[i]
            const btn = src >= 0 ? gp.buttons[src] : undefined
            out[base + 1 + i] = btn && btn.pressed ? 1 : 0
          }

          // Axes: sticks come straight from gp.axes; the two trigger axes use
          // the analog value of the trigger buttons (indices 6 and 7).
          const axBase = base + 1 + engineGamepad.N_BUTTONS
          out[axBase + 0] = gp.axes[0] || 0 // Left_X
          out[axBase + 1] = gp.axes[1] || 0 // Left_Y
          out[axBase + 2] = gp.axes[2] || 0 // Right_X
          out[axBase + 3] = gp.axes[3] || 0 // Right_Y
          out[axBase + 4] = gp.buttons[6] ? gp.buttons[6].value : 0 // Left_Trigger
          out[axBase + 5] = gp.buttons[7] ? gp.buttons[7].value : 0 // Right_Trigger
        }
      },

      _js_get_gamepad_name: (index, ptr, maxLen) => {
        if (!wasmMemory) return 0
        const gp = engineGamepad.atSlot(index)
        if (!gp) return 0
        const bytes = new TextEncoder().encode(gp.id || "Gamepad")
        const n = Math.min(bytes.length, maxLen)
        new Uint8Array(wasmMemory.buffer, ptr, n).set(bytes.subarray(0, n))
        return n
      },

      _js_set_gamepad_vibration: (index, left, right, durationMs) => {
        const gp = engineGamepad.atSlot(index)
        if (!gp) return
        const act = gp.vibrationActuator
        if (!act || !act.playEffect) return
        // Stop when both motors are zero; otherwise play a dual-rumble effect.
        if (left <= 0 && right <= 0) {
          if (act.reset) act.reset()
          return
        }
        act
          .playEffect("dual-rumble", {
            duration: durationMs,
            strongMagnitude: Math.min(Math.max(left, 0), 1),
            weakMagnitude: Math.min(Math.max(right, 0), 1),
          })
          .catch(() => {})
      },
    },
  }
})()
