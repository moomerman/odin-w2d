## Build and run

This project uses `just` (justfile) as the task runner.

## Code quality

All code must pass strict vetting: `-vet -strict-style -vet-semicolon -vet-cast -vet-using-param -vet-shadowing -warnings-as-errors`. Run `just check` to verify.

## Platform build tags

Cross-platform is handled via compile-time `#+build` tags, not runtime flags:
- `#+build !js` — desktop code
- `#+build js` — web/WASM code
- `#+build darwin` — macOS-specific code

## Architecture

- `core/` contains shared types and backend interfaces — this breaks circular import cycles. Don't import engine packages from `core/`.
- `backend/` selects the platform-appropriate window/render/audio backends at compile time.
- Examples live in `examples/` and import the engine as `import w "../.."`.

## Testing

`just test` runs `tests/render`: the engine with no window (`init_headless`), drawing known pictures and checking them with `read_pixels`, plus injected input. It needs a GPU but no display, runs in under a second, and exits non-zero on failure. `just verify` includes it.

- Add a test for every renderer or input fix: a `proc(step: int) -> (done: bool)` in `tests/render/main.odin`, added to the `tests` table. Run one with `./build/tests-render 1 <name-substring>`.
- To look at what something draws without a window: `init_headless`, draw, `save_screenshot("out.png")`, `quit()`.
- wgpu applies every `QueueWriteBuffer` before the frame's commands run. Anything that changes between draws in a frame (projection, uniforms, vertices) needs its own buffer region per change, and the batch must be flushed before the change.

## Workflow

- Use feature branches and pull requests.
- Run `just verify` before submitting changes.
