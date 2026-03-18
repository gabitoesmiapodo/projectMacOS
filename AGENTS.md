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
    |       +-- ProjectMView+Presets.mm (source resolution + playlist + caching)
    |       +-- ProjectMView+Menu.mm (menu + interaction)
    |       +-- ProjectMRegistration.mm (cfg globals + foobar2000 registration)
    |
    +-- Preferences tree (under Tools in foobar2000 prefs)
    |       |
    |       +-- ProjectMPreferences.mm (parent page registration)
    |       +-- ProjectMPrefsPerformance.mm (FPS, resolution, vsync, mesh, auto-pause)
    |       +-- ProjectMPrefsPresets.mm (custom source, sort, browse/reset/reload)
    |       +-- ProjectMPrefsTransitions.mm (soft/hard cuts, sensitivity, randomization)
    |       +-- ProjectMPrefsVisualization.mm (beat sensitivity, aspect correction)
    |       +-- ProjectMPrefsDiagnostics.mm (debug logging toggle)
    |
    +-- Caching (~/Library/Caches/projectMacOS/)
    |       |
    |       +-- preset-index.json (playlist path index with fingerprint)
    |       +-- zip-content/ + zip-content-meta.json (extracted ZIP cache)
    |
    +-- zipfs (mac/zipfs/) -- extracts projectMacOS.zip to temp dir at startup
```

## Key Files

| File | Purpose |
|------|---------|
| `mac/ProjectMView.h` | Shared `ProjectMView` interface, ivars, and cross-module method declarations |
| `mac/ProjectMView.mm` | Core render lifecycle: OpenGL setup, CVDisplayLink loop, PCM feed, FBO half-resolution pipeline |
| `mac/ProjectMView+Presets.mm` | Preset data-source resolution, ZIP extraction, playlist lifecycle, index caching, custom source handling |
| `mac/ProjectMView+Menu.mm` | Context menu, preset browser UI, fullscreen/help/interactions |
| `mac/ProjectMRegistration.mm` | Component metadata, cfg globals, controller and `ui_element_mac` registration |
| `mac/ProjectMMenuLogic.h/.mm` | Pure helper logic: title truncation, preset display names, cycle favorites, path normalization, cache paths, fingerprinting, validation |
| `mac/ProjectMPrefsParent.h` | Shared header: `kPrefsParentGUID` and `PMPrefsHelpers` category interface |
| `mac/ProjectMPrefsHelpers.mm` | Layout utility category: `rowWithLabel`, `helpText`, `spacer`, `popupWithTitles:values:` |
| `mac/ProjectMPreferences.mm` | Parent preferences page registration (under Tools) |
| `mac/ProjectMPrefsPerformance.mm` | Performance section: FPS cap, idle FPS, resolution scale, mesh quality, vsync, auto-pause |
| `mac/ProjectMPrefsPresets.mm` | Presets section: custom folder/ZIP source, sort order, browse/reset/reload, error feedback |
| `mac/ProjectMPrefsTransitions.mm` | Transitions section: soft cut duration, hard cuts, sensitivity, duration randomization |
| `mac/ProjectMPrefsVisualization.mm` | Visualization section: beat sensitivity, aspect correction |
| `mac/ProjectMPrefsDiagnostics.mm` | Diagnostics section: debug logging checkbox |
| `mac/tests/ProjectMMenuLogicTests.mm` | XCTest unit tests for all pure logic functions |
| `mac/stdafx.h` | Precompiled header: foobar2000 SDK + Cocoa imports |
| `mac/zipfs/zipfs.hpp/.cpp` | ZIP filesystem wrapper |
| `mac/zipfs/unzip.c`, `ioapi.c` | MiniZip decompression |
| `mac/projectMacOS.xcodeproj` | Xcode project |
| `scripts/build-deps.sh` | Builds foobar2000 SDK static libs + projectM 4.1.6 static libs (universal x86_64/arm64) |
| `scripts/run-tests.sh` | Runs XCTest target (`projectMacOSTests`) via `xcodebuild test` |
| `scripts/deploy-component.sh` | Optionally builds, then installs component to foobar2000 |
| `scripts/release.sh` | Release workflow: tag, build, package artifacts |

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

The component extracts this zip to a temp directory at startup and cleans it up in `-dealloc`. Extracted content is cached at `~/Library/Caches/projectMacOS/zip-content/` with a metadata fingerprint; subsequent launches skip extraction if the cache matches.

## Custom Preset Source

Users can override the default ZIP source via Preferences > Tools > Presets:
- **Folder**: must contain a `Presets/` subfolder with `.milk` files (same structure as the ZIP)
- **ZIP file**: any `.zip` with the same internal structure as `projectMacOS.zip`
- Stored in `cfg_custom_presets_folder`; empty string means use the default ZIP
- Browse button filters to `.zip` files and folders; Reset button clears the custom source
- Reload button forces cache invalidation and full preset reload
- Invalid sources show inline error feedback and revert to defaults

## Key Implementation Details

- **API version**: projectM 4.1.6 C API. Avoid `projectm_set_texture_load_event_callback` and `projectm_playlist_set_preset_load_event_callback` -- both are 4.2.0+ only.
- **Preset tracking**: via `projectm_playlist_set_preset_switched_event_callback`.
- **Audio**: `get_chunk_absolute()` returns float samples; convert to int16 via `audio_math::convert_to_int16()`, feed to `projectm_pcm_add_int16()`.
- **Render loop**: CVDisplayLink fires on vsync; `renderFrame` calls `projectm_opengl_render_frame()` under `[openGLContext makeCurrentContext]`. Configurable FPS cap (30/45/60/90/120) and idle FPS (15/30). Auto-pause stops the display link when no music is playing.
- **Half-resolution rendering**: optional FBO pipeline (`_halfResFBO`) renders at half resolution and blits to the full-size backbuffer. Controlled by `cfg_resolution_scale` (0=Half, 1=Standard, 2=Retina).
- **Persistent settings**: see full list below.
- **Favorites**: stored as JSON in `cfg_preset_favorites`. Paths are relative to the presets directory when possible. Managed via `ProjectMView+Menu.mm` (`loadedFavorites`, `persistFavorites`).
- **Cycle Favorites**: timer-based cycling within the favorites list. Active only when music is playing and visualization is not paused. Mutual exclusion with shuffle. Any manual preset selection disables both via `disableAutoplay`.
- **Transitions**: all preset switches use smooth cross-fade (`PMUseHardCutTransitions()` returns `NO` by default). Hard cuts can be enabled via `cfg_hard_cuts` with configurable sensitivity.
- **Preset index caching**: playlist path index is serialized to `~/Library/Caches/projectMacOS/preset-index.json` with a fingerprint (source type, mtime, size/count, sort order). On reload, the cache is reused if the fingerprint matches, avoiding a full directory walk.
- **Path normalization**: `PMNormalizePath()` resolves symlinks and standardizes paths; results are memoized for process lifetime. `PMPresetPathsMatch()` compares via normalized paths.
- **In-memory preset path index**: `_presetPathIndex` (NSDictionary) provides O(1) lookup of playlist indices by normalized path, used in `applyPresetSelectionPathInRenderLoop` and `handlePresetLoadFailureForFilename`.
- **foobar2000 bridging**: `fb2k::wrapNSObject()` / `unwrapNSObject()` from `commonObjects-Apple.h`; `instantiate()` returns wrapped `NSViewController`.
- **OpenGL deprecation**: suppressed via `#pragma clang diagnostic ignored "-Wdeprecated-declarations"`.
- **pfc assert stub**: `namespace pfc { void myassert(...) {} }` is required because SDK libs are Release but the component may build with debug flags.
- **Debug logging**: gated behind `cfg_debug_logging`; uses `PMLog()` / `PMLogError()` macros. Toggle via Preferences > Tools > Diagnostics.

## Persistent Settings (cfg_ globals)

All defined in `ProjectMRegistration.mm`:

| Setting | Type | Default | Values |
|---------|------|---------|--------|
| `cfg_preset_shuffle` | bool | false | |
| `cfg_preset_name` | string | "" | Last active preset path |
| `cfg_preset_duration` | int | 30 | Seconds between auto-advance |
| `cfg_preset_favorites` | string | "" | JSON array of relative paths |
| `cfg_cycle_favorites_mode` | int | 0 | 0=Off, 1=Ascending, 2=Descending, 3=Random |
| `cfg_custom_presets_folder` | string | "" | Custom source path (folder or .zip) |
| `cfg_preset_sort_order` | int | 0 | 0=A-Z, 1=Z-A |
| `cfg_fps_cap` | int | 60 | 0 (unlimited), 30, 45, 60, 90, 120 |
| `cfg_idle_fps` | int | 30 | 15, 30 |
| `cfg_resolution_scale` | int | 1 | 0=Half, 1=Standard, 2=Retina |
| `cfg_vsync` | bool | true | |
| `cfg_mesh_quality` | int | 1 | 0=64, 1=128, 2=192 |
| `cfg_auto_pause` | bool | false | Pause visualization when no audio |
| `cfg_soft_cut_duration` | int | 3 | 1, 2, 3, 5 seconds |
| `cfg_hard_cuts` | bool | false | |
| `cfg_hard_cut_sensitivity` | int | 1 | 0-3 mapping to 0.2/1.0/3.0/5.0 |
| `cfg_duration_randomization` | int | 0 | 0-3 mapping to 0.001/0.25/0.5/1.0 |
| `cfg_beat_sensitivity` | int | 1 | 0-3 range |
| `cfg_aspect_correction` | bool | true | |
| `cfg_debug_logging` | bool | false | |

## Preferences Tree

Registered under **Tools** in foobar2000's preferences:

1. **Performance** -- FPS cap, idle FPS, resolution scale, mesh quality, vsync, auto-pause
2. **Presets** -- Custom source (folder or ZIP), sort order, browse/reset/reload buttons, error feedback
3. **Transitions** -- Soft cut duration, hard cuts toggle, hard cut sensitivity, duration randomization
4. **Visualization** -- Beat sensitivity, aspect correction
5. **Diagnostics** -- Debug logging toggle

All section pages use `PMPrefsHelpers` for consistent layout. Settings propagation uses a generation counter (`_lastSettingsGeneration`) checked each render frame.

## References

- projectM GitHub: https://github.com/projectM-visualizer/projectm
- Original Windows plugin: https://github.com/djdron/foo_vis_projectM
- foobar2000 SDK overview: https://wiki.hydrogenaudio.org/index.php?title=Foobar2000:Development:Overview
