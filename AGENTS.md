# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

macOS-only foobar2000 component that displays projectM (MilkDrop-compatible) visualizations. Receives PCM audio from foobar2000's visualization stream and feeds it to projectM, which renders via OpenGL.

- License: LGPL v2.1
- Version: 1.0.3 (projectM 4.1.6 C API, statically linked)

## Build Commands

```bash
# First time: build all deps + component + deploy to foobar2000
bash scripts/deploy-component.sh --build

# Rebuild deps only (needed if deps/projectm/lib/ is missing)
bash scripts/build-deps.sh

# Rebuild component only (if deps already built), then deploy
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build

# Deploy already-built component without rebuilding
bash scripts/deploy-component.sh

# Run XCTest suite only
bash scripts/run-tests.sh
```

The deploy script closes foobar2000 if it is running, runs `scripts/run-tests.sh`, copies the component to `~/Library/foobar2000-v2/user-components/foo_vis_projectMacOS/`, verifies binary UUIDs, and launches foobar2000.

Always run `bash scripts/deploy-component.sh` after implementing new features, bug fixes, or other behavior changes.

Place `projectMacOS.zip` in `~/Documents/foobar2000/` before first deploy. The component resolves `~/Documents/foobar2000/projectMacOS.zip` at runtime; deploy does not copy preset archives.

## Architecture

```
foobar2000 (macOS)
    |
    +-- visualisation_stream_v2 (PCM audio data)
    |
    v
foo_vis_projectMacOS.component (macOS bundle, statically linked)
    |
    +-- ProjectMView : NSOpenGLView
    |       |
    |       +-- ProjectMView.mm (render loop + audio)
    |       +-- ProjectMView+Presets.mm (source resolution + playlist)
    |       +-- ProjectMView+Menu.mm (menu + interaction)
    |       +-- ProjectMRegistration.mm (cfg globals + foobar2000 registration)
    |
    +-- zipfs (mac/zipfs/)  -- extracts projectMacOS.zip to temp dir at startup
```

## Key Files

| File | Purpose |
|------|---------|
| `mac/ProjectMView.h` | Shared `ProjectMView` interface, ivars, and cross-module method declarations |
| `mac/ProjectMView.mm` | Core render lifecycle: OpenGL setup, CVDisplayLink loop, PCM feed |
| `mac/ProjectMView+Presets.mm` | Preset data-source resolution, ZIP extraction, playlist lifecycle |
| `mac/ProjectMView+Menu.mm` | Context menu, preset browser UI, fullscreen/help/interactions |
| `mac/ProjectMRegistration.mm` | Component metadata, cfg globals, controller and `ui_element_mac` registration |
| `mac/ProjectMMenuLogic.h/.mm` | Pure helper logic: title truncation, preset display names, cycle favorites logic |
| `mac/tests/ProjectMMenuLogicTests.mm` | XCTest unit tests for all pure logic functions |
| `mac/stdafx.h` | Precompiled header: foobar2000 SDK + Cocoa imports |
| `mac/zipfs/zipfs.hpp/.cpp` | ZIP filesystem wrapper |
| `mac/zipfs/unzip.c`, `ioapi.c` | MiniZip decompression |
| `mac/projectMacOS.xcodeproj` | Xcode project |
| `scripts/build-deps.sh` | Builds foobar2000 SDK static libs + projectM 4.1.6 static libs (universal x86_64/arm64) |
| `scripts/run-tests.sh` | Runs XCTest target (`projectMacOSTests`) via `xcodebuild test` |
| `scripts/deploy-component.sh` | Optionally builds, then installs component to foobar2000 |

## Dependencies

All dependencies are built as static libraries (no dynamic linking) to avoid `SIGKILL (Code Signature Invalid)` on macOS with hardened-runtime processes.

- **foobar2000 SDK**: `deps/foobar2000-sdk/` -- five Xcode sub-projects built by `build-deps.sh`
- **projectM 4.1.6**: cloned and built by `build-deps.sh`, installed to `deps/projectm/lib/` and `deps/projectm/include/`

## Repository Constraints

- Do not modify anything under `deps/`.

## projectMacOS.zip Format

Expected at `~/Documents/foobar2000/projectMacOS.zip`.

Structure inside the zip:
- `Presets/*.milk` -- MilkDrop preset files
- `Textures/*` -- Optional texture files

The component extracts this zip to a temp directory at startup and cleans it up in `-dealloc`.

## Key Implementation Details

- **API version**: projectM 4.1.6 C API. Avoid `projectm_set_texture_load_event_callback` and `projectm_playlist_set_preset_load_event_callback` -- both are 4.2.0+ only.
- **Preset tracking**: via `projectm_playlist_set_preset_switched_event_callback`.
- **Audio**: `get_chunk_absolute()` returns float samples; convert to int16 via `audio_math::convert_to_int16()`, feed to `projectm_pcm_add_int16()`.
- **Render loop**: CVDisplayLink fires on vsync; `renderFrame` calls `projectm_opengl_render_frame()` under `[openGLContext makeCurrentContext]`.
- **Persistent settings**: `cfg_bool cfg_preset_shuffle`, `cfg_string cfg_preset_name`, `cfg_int cfg_preset_duration` (30s default), `cfg_string cfg_preset_favorites` (JSON), `cfg_int cfg_cycle_favorites_mode` (0=Off, 1=Ascending, 2=Descending, 3=Random).
- **Favorites**: stored as JSON in `cfg_preset_favorites`. Paths are relative to the presets directory when possible. Managed via `ProjectMView+Menu.mm` (`loadedFavorites`, `persistFavorites`).
- **Cycle Favorites**: timer-based cycling within the favorites list. Active only when music is playing and visualization is not paused. Mutual exclusion with shuffle. Any manual preset selection disables both via `disableAutoplay`.
- **Transitions**: all preset switches use smooth cross-fade (`PMUseHardCutTransitions()` returns `NO`).
- **foobar2000 bridging**: `fb2k::wrapNSObject()` / `unwrapNSObject()` from `commonObjects-Apple.h`; `instantiate()` returns wrapped `NSViewController`.
- **OpenGL deprecation**: suppressed via `#pragma clang diagnostic ignored "-Wdeprecated-declarations"`.
- **pfc assert stub**: `namespace pfc { void myassert(...) {} }` is required because SDK libs are Release but the component may build with debug flags.

## References

- projectM GitHub: https://github.com/projectM-visualizer/projectm
- Original Windows plugin: https://github.com/djdron/foo_vis_projectM
- foobar2000 SDK overview: https://wiki.hydrogenaudio.org/index.php?title=Foobar2000:Development:Overview
