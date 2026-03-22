# odin-wgpu

A 2D game development library for Odin using WebGPU (wgpu-native) and SDL3.

## Install

### Upgrading wgpu-native

Odin's vendor library ships wgpu-native v27.0.2.0 which has a [command encoder memory leak](https://github.com/gfx-rs/wgpu-native/issues/541) — internal cleanup is skipped every frame, causing steady memory growth (~3-4 MB/min).

This is fixed in v27.0.4.0. To upgrade:

1. Download the release for your platform from https://github.com/gfx-rs/wgpu-native/releases/tag/v27.0.4.0

2. Replace the library files in your Odin install:
   ```
   ~/.odin-install/<version>/vendor/wgpu/lib/wgpu-macos-aarch64-release/lib/libwgpu_native.a
   ~/.odin-install/<version>/vendor/wgpu/lib/wgpu-macos-aarch64-release/lib/libwgpu_native.dylib
   ```

3. Relax the version check in `~/.odin-install/<version>/vendor/wgpu/wgpu.odin` (around line 1699). Change:
   ```odin
   if v.xyz != BINDINGS_VERSION.xyz {
   ```
   to:
   ```odin
   if v.xy != BINDINGS_VERSION.xy {
   ```
   This allows the compatible patch release (27.0.4) to pass validation against the 27.0.2 bindings.
