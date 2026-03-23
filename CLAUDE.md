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

## Workflow

- Use feature branches and pull requests.
- Run `just verify` before submitting changes.
