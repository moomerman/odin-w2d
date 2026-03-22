Most impactful to add next:

  1. Window modes (fullscreen/fixed/resizable) — you'll want this almost immediately for any game. It's already on your roadmap and should be straightforward since the
  window backends already handle resize events.
  2. Error handling instead of panics — right now a bad PNG or a GPU failure crashes the whole game. Returning optionals from load_texture, load_audio, load_font etc.
  would let you show fallback content or log and continue. This matters as soon as you're loading user-facing assets.
  3. Mouse wheel / scroll input — notably absent from the input system. You'll need it for menus, inventory scrolling, zoom, etc.

  Nice to have but not blocking:

  4. Texture atlas / sprite batching — the current texture-switch flushing works fine for small games, but if you're drawing lots of different sprites per frame you'll
  hit performance limits. The lemmings example probably already benefits from sprites being on one sheet.
  5. Camera/viewport — a 2D camera with position + zoom that transforms the projection matrix. Almost every game beyond a single-screen needs this. It's a small addition
  (modify the orthographic projection).
  6. Index buffer — switching from 6 vertices to 4 vertices + 6 indices per quad is a 33% reduction in vertex data. Easy win but not urgent.
