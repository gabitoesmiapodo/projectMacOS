# Configuration Options Design

## Goal

Add 18 user-facing configuration options to the foobar2000 preferences panel (Tools > projectMacOS), organized into logical sections. All settings persist across sessions via foobar2000's `cfg_*` system and take effect without restarting the component.

## Context

The component currently exposes only `cfg_debug_logging` in the preferences panel. All projectM parameters (mesh size, beat sensitivity, transition settings, etc.) are hardcoded in `createProjectM`. The right-click context menu handles immediate actions (pause, next/prev, shuffle, favorites) and stays unchanged.

Hardware reference: MacBook Pro 2019, Intel i9, AMD Radeon Pro 5500M, 60Hz Retina display + external 1x display.

## Settings

### Group 1: Performance

#### FPS Cap
- **cfg variable:** `cfg_int cfg_fps_cap` (default: 60)
- **Values:** 0 (Unlimited), 30, 45, 60, 90, 120
- **Control:** Popup button
- **Help text:** "Maximum frame rate during music playback. Lower values reduce CPU usage."
- **Behavior:** Changes the active-mode return value of `frameDurationInMachTicks()`. Value 0 (Unlimited) skips the software frame cap entirely -- CVDisplayLink governs callback timing (display refresh rate), and vsync (if enabled) governs buffer swap timing. With both Unlimited and vsync off, rendering occurs at CVDisplayLink callback rate (display refresh rate), not an unbounded spin loop. Also calls `projectm_set_fps` with the cap value (or 60 for Unlimited) as a hint to presets for animation timing calculations.

#### Idle FPS
- **cfg variable:** `cfg_int cfg_idle_fps` (default: 30)
- **Values:** 15, 30
- **Control:** Popup button
- **Help text:** "Frame rate when no music is playing. Presets still animate but don't react to sound."
- **Behavior:** Changes the idle-mode return value of `frameDurationInMachTicks()`.

#### Resolution Scale
- **cfg variable:** `cfg_int cfg_resolution_scale` (default: 1)
- **Values:** 0 (Half), 1 (Standard), 2 (Retina)
- **Control:** Popup button with labels "Half / Standard / Retina"
- **Help text:** "Rendering resolution relative to window size. Half uses less GPU power. Retina renders at native pixel density on high-DPI displays."
- **Behavior:**
  - Standard (1): `wantsBestResolutionOpenGLSurface = NO`. Current default. Renders at point resolution.
  - Retina (2): `wantsBestResolutionOpenGLSurface = YES`. Renders at native backing resolution (2x on Retina).
  - Half (0): `wantsBestResolutionOpenGLSurface = NO`, plus an FBO downscale pipeline. Render to an FBO at half the point dimensions, then `glBlitFramebuffer` to the full drawable with `GL_LINEAR` filtering.
- **FBO pipeline for Half mode:** Create FBO + color renderbuffer at `(width/2, height/2)` plus a depth/stencil renderbuffer (projectM uses depth). In `renderFrame`: bind FBO as `GL_FRAMEBUFFER`, set viewport to half dimensions, call `projectm_opengl_render_frame`. After rendering, projectM may leave its own internal FBOs bound, so explicitly rebind: set the half-res FBO as `GL_READ_FRAMEBUFFER`, bind framebuffer 0 as `GL_DRAW_FRAMEBUFFER`, set viewport to full dimensions, then call `glBlitFramebuffer(0, 0, halfW, halfH, 0, 0, fullW, fullH, GL_COLOR_BUFFER_BIT, GL_LINEAR)`. FBO is recreated when viewport dimensions change (in `reshape` or `viewDidChangeBackingProperties`).
- **Resolution scale runtime switching:** `wantsBestResolutionOpenGLSurface` should be set before the OpenGL context is fully configured. Changing it after `prepareOpenGL` may not take effect without recreating the context. To handle this: when switching between Standard and Retina, call `setWantsBestResolutionOpenGLSurface:`, then `[self.openGLContext update]`, then update the viewport via `getDrawableSizeWidth:height:`. If the backing size does not change after the update call, a full `destroyProjectMState` + `createProjectM` cycle is needed to force context rebuild. Half mode does not change `wantsBestResolutionOpenGLSurface` (stays NO) so it switches freely with Standard.

#### Vsync
- **cfg variable:** `cfg_bool cfg_vsync` (default: true)
- **Control:** Checkbox
- **Help text:** "Synchronize frame output with display refresh. Disable for lower latency at the cost of possible tearing."
- **Behavior:** Sets `NSOpenGLContextParameterSwapInterval` to 1 (on) or 0 (off) under CGL lock.

#### Mesh Quality
- **cfg variable:** `cfg_int cfg_mesh_quality` (default: 1)
- **Values:** 0 (Low: 64), 1 (Medium: 128), 2 (High: 192)
- **Control:** Popup button with labels "Low / Medium / High"
- **Help text:** "Detail level of the warp mesh. Higher values produce smoother distortion effects but use more GPU."
- **Behavior:** Calls `projectm_set_mesh_size(handle, size, size * heightWidthRatio)` where size is 64/128/192. Note: changing mesh size forces reallocation of internal per-pixel equation buffers and may cause a brief visual hitch. This is acceptable for a settings change.

#### Auto-pause
- **cfg variable:** `cfg_bool cfg_auto_pause` (default: false)
- **Control:** Checkbox
- **Help text:** "Automatically pause the visualization when music is not playing. Reduces CPU usage to near zero."
- **Behavior:** When `_isAudioPlaybackActive` transitions to NO and auto-pause is enabled, stop CVDisplayLink (same as manual pause but without setting `_isVisualizationPaused`). When playback resumes, restart CVDisplayLink if not manually paused. Requires a separate `_isAutoPaused` ivar to distinguish from manual pause. Logic: CVDisplayLink runs when `!_isVisualizationPaused && !_isAutoPaused`.

### Group 2: Transitions

#### Soft Cut Duration
- **cfg variable:** `cfg_int cfg_soft_cut_duration` (default: 3)
- **Values:** 1, 2, 3, 5
- **Control:** Popup button with labels "1s / 2s / 3s / 5s"
- **Help text:** "Cross-fade time when transitioning between presets."
- **Behavior:** Calls `projectm_set_soft_cut_duration(handle, (double)value)`.

#### Hard Cuts
- **cfg variable:** `cfg_bool cfg_hard_cuts` (default: false)
- **Control:** Checkbox
- **Help text:** "Allow instant beat-triggered transitions instead of always cross-fading."
- **Behavior:** Calls `projectm_set_hard_cut_enabled(handle, value)`.

#### Hard Cut Sensitivity
- **cfg variable:** `cfg_int cfg_hard_cut_sensitivity` (default: 1)
- **Values:** 0 (Low: 0.5), 1 (Medium: 1.0), 2 (High: 1.5), 3 (Max: 2.0)
- **Control:** Popup button with labels "Low / Medium / High / Max"
- **Help text:** "How strong a beat must be to trigger a hard cut. Only applies when hard cuts are enabled."
- **Behavior:** Calls `projectm_set_hard_cut_sensitivity(handle, floatValue)`. Visually disabled in preferences when hard cuts checkbox is off.

#### Hard Cut Minimum Interval
- **cfg variable:** `cfg_int cfg_hard_cut_interval` (default: 20)
- **Values:** 5, 10, 20, 30
- **Control:** Popup button with labels "5s / 10s / 20s / 30s"
- **Help text:** "Minimum time between hard cuts to prevent rapid flickering."
- **Behavior:** Calls `projectm_set_hard_cut_duration(handle, (double)value)`. Visually disabled when hard cuts checkbox is off.

#### Duration Randomization
- **cfg variable:** `cfg_int cfg_duration_randomization` (default: 0)
- **Values:** 0 (None: 0.001), 1 (Low: 0.25), 2 (Medium: 0.5), 3 (High: 1.0)
- **Control:** Popup button with labels "None / Low / Medium / High"
- **Help text:** "Add variation to preset switch timing. At None, presets switch at exactly the configured delay."
- **Behavior:** Calls `projectm_set_easter_egg(handle, floatValue)`. Note: the API requires a value > 0 (passing 0.0 silently reverts to sigma=1.0). "None" maps to 0.001, which produces negligible randomization.

### Group 3: Visualization

#### Beat Sensitivity
- **cfg variable:** `cfg_int cfg_beat_sensitivity` (default: 1)
- **Values:** 0 (Low: 0.5), 1 (Medium: 1.0), 2 (High: 1.5), 3 (Max: 2.0)
- **Control:** Popup button with labels "Low / Medium / High / Max"
- **Help text:** "How strongly the visualization reacts to beats in the music."
- **Behavior:** Calls `projectm_set_beat_sensitivity(handle, floatValue)`.

#### Aspect Correction
- **cfg variable:** `cfg_bool cfg_aspect_correction` (default: true)
- **Control:** Checkbox
- **Help text:** "Preserve preset aspect ratio. When off, presets stretch to fill the window."
- **Behavior:** Calls `projectm_set_aspect_correction(handle, value)`.

#### Mouse Interaction
- **cfg variable:** `cfg_bool cfg_mouse_interaction` (default: false)
- **Control:** Checkbox
- **Help text:** "Click or drag on the visualization to create visual effects."
- **Behavior:** When enabled, `mouseDown:` calls `projectm_touch(x, y, 1, type)`, `mouseDragged:` calls `projectm_touch_drag(x, y, 1)`, `mouseUp:` calls `projectm_touch_destroy(x, y)`. Pressure is hardcoded to 1 (standard click -- NSEvent pressure is only meaningful for Force Touch trackpads). Coordinates are converted from view space to pixel space via `convertPointToBacking:`. When disabled, mouse events are not consumed (default NSOpenGLView behavior -- right-click still opens context menu regardless).

#### Mouse Effect Type
- **cfg variable:** `cfg_int cfg_mouse_effect` (default: 0)
- **Values:** 0 (Random), 1 (Circle), 2 (Radial Blob), 7 (Line), 8 (Double Line)
- **Control:** Popup button with labels "Random / Circle / Radial Blob / Line / Double Line"
- **Help text:** "Type of visual effect created by mouse interaction. Only applies when mouse interaction is enabled."
- **Behavior:** Value stored as the raw `projectm_touch_type` enum value and passed directly to `projectm_touch()`. Enum mapping: PROJECTM_TOUCH_TYPE_RANDOM=0, PROJECTM_TOUCH_TYPE_CIRCLE=1, PROJECTM_TOUCH_TYPE_RADIAL_BLOB=2, PROJECTM_TOUCH_TYPE_LINE=7, PROJECTM_TOUCH_TYPE_DOUBLE_LINE=8. Values 3-6 (Blob2, Blob3, Derivative Line, Blob5) are excluded as they are visually similar to existing options. Visually disabled when mouse interaction checkbox is off.

### Group 4: Presets

#### Custom Presets Folder
- **cfg variable:** `cfg_string cfg_custom_presets_folder` (default: "")
- **Control:** Text field + "Browse..." button (NSOpenPanel for directory selection)
- **Help text:** "Override the default preset source with a folder of .milk files. Leave empty to use the built-in collection."
- **Behavior:** When non-empty, `resolvedDataDirectoryPathUsedZip:` returns this path instead of resolving from the ZIP. Changing this triggers a playlist reload. The preset browser menu reflects the new source. Validation: check path exists and contains at least one .milk file; if invalid, log error and fall back to ZIP.

#### Sort Order
- **cfg variable:** `cfg_int cfg_preset_sort_order` (default: 0)
- **Values:** 0 (Name A-Z), 1 (Name Z-A), 2 (Path A-Z), 3 (Path Z-A)
- **Control:** Popup button
- **Help text:** "Order of presets in the browser menu and initial playlist."
- **Behavior:** After loading presets into the playlist, calls `projectm_playlist_sort` with the appropriate predicate (`SORT_PREDICATE_FILENAME_ONLY` or `SORT_PREDICATE_FULL_PATH`) and order (`SORT_ORDER_ASCENDING` or `SORT_ORDER_DESCENDING`). Note: the projectM sort is case-sensitive (uppercase sorts before lowercase). This replaces the current `localizedCaseInsensitiveCompare:` sort in `addPresetsFromPath:`. Affects both the internal playlist order and the preset browser menu display.

#### Preset Filter
- **cfg variable:** `cfg_string cfg_preset_filter` (default: "")
- **Control:** Text field
- **Help text:** "Comma-separated glob patterns to include presets (e.g. *warp*, *spiral*). Leave empty to load all presets."
- **Behavior:** The comma-separated string is split into individual C strings and passed as an array to `projectm_playlist_set_filter(playlist, patterns, count)`. After setting the filter on an existing playlist, `projectm_playlist_apply_filter()` must also be called to apply it to already-loaded entries. Empty string clears the filter (passes count=0). The API uses glob-style matching on filenames.

#### Preset Retry Count
- **cfg variable:** `cfg_int cfg_preset_retry_count` (default: 3)
- **Values:** 1, 3, 5, 10
- **Control:** Popup button
- **Help text:** "How many times to retry loading a broken preset before skipping it."
- **Behavior:** Calls `projectm_playlist_set_retry_count(playlist, value)`.

### Group 5: Diagnostics (existing)

#### Debug Logging
- Already implemented. No changes.

## Settings Change Propagation

Settings changes must propagate from the preferences page to the running visualization without restart.

**Mechanism:** Global atomic generation counter.

```
// In ProjectMRegistration.mm:
std::atomic<uint32_t> g_settingsGeneration(0);

// Preferences page increments on any change:
g_settingsGeneration.fetch_add(1, std::memory_order_relaxed);

// In renderFrame, before rendering:
static uint32_t lastGen = 0;
uint32_t gen = g_settingsGeneration.load(std::memory_order_relaxed);
if (gen != lastGen) {
    [self applySettingsFromPreferences];
    lastGen = gen;
}
```

`applySettingsFromPreferences` reads all cfg_ values and applies them:

**Immediate projectM calls** (cheap, safe to call even if value unchanged):
- `projectm_set_beat_sensitivity`, `projectm_set_soft_cut_duration`, `projectm_set_hard_cut_enabled`, `projectm_set_hard_cut_sensitivity`, `projectm_set_hard_cut_duration`, `projectm_set_aspect_correction`, `projectm_set_easter_egg`, `projectm_set_fps`

**Conditional updates** (only when value actually changed from cached):
- FPS cap / idle FPS: update cached durations in `frameDurationInMachTicks` (use new static getter/setter or global)
- Vsync: `setValues:forParameter:NSOpenGLContextParameterSwapInterval` under CGL lock
- Mesh quality: `projectm_set_mesh_size` with recalculated dimensions
- Resolution scale: toggle `wantsBestResolutionOpenGLSurface`, setup/teardown FBO, update viewport
- Auto-pause: evaluate whether CVDisplayLink should stop/start
- Mouse effect type: just cache the value (read on mouse event)
- Retry count: `projectm_playlist_set_retry_count`

**Heavyweight updates** (require playlist reload):
- Custom presets folder: reload presets from new source
- Sort order: re-sort playlist
- Preset filter: re-filter and reload playlist

These three are grouped: if any changed, do a full playlist reload with the new settings applied.

## New Files

| File | Purpose |
|------|---------|
| `mac/ProjectMPreferences.mm` | **Modified.** Expand from single checkbox to full preferences panel with 5 sections. |

## Modified Files

| File | Change |
|------|--------|
| `mac/ProjectMView.h` | Add extern declarations for 18 new cfg_ variables. Add `_isAutoPaused` and FBO-related ivars. |
| `mac/ProjectMRegistration.mm` | Add 18 new GUID + cfg_ definitions. Add `g_settingsGeneration` atomic. Add `PMSettingsDidChange()` helper. |
| `mac/ProjectMView.mm` | Add `applySettingsFromPreferences`, generation counter check in `renderFrame`, FBO setup/teardown for half-res mode, mouse event handlers, `frameDurationInMachTicks` changes for configurable FPS. Replace hardcoded values in `createProjectM` with cfg_ reads. |
| `mac/ProjectMView+Presets.mm` | Modify `resolvedDataDirectoryPathUsedZip:` to check `cfg_custom_presets_folder`. Apply sort order and filter after loading presets. |
| `mac/ProjectMView+Menu.mm` | No changes for auto-pause (addPCM is in ProjectMView.mm). May need minor adjustments if menu items reflect new settings. |
| `mac/projectMacOS.xcodeproj` | No new files to add (ProjectMPreferences.mm already in project). |

## Preferences Panel Layout

Built programmatically (no XIB). Uses `NSScrollView` wrapping an `NSStackView` with section headers (`NSTextField` bold labels) and consistent spacing. The scroll view is necessary because 5 sections with help text will exceed the preferences window height.

```
Performance
  FPS Cap:              [60          v]  "Maximum frame rate during..."
  Idle FPS:             [30          v]  "Frame rate when no music..."
  Resolution:           [Standard    v]  "Rendering resolution..."
  Mesh Quality:         [Medium      v]  "Detail level of the warp..."
  [x] Vsync                              "Synchronize frame output..."
  [ ] Auto-pause                         "Automatically pause..."

Transitions
  Soft Cut Duration:    [3s          v]  "Cross-fade time..."
  [ ] Hard Cuts                          "Allow instant beat..."
  Hard Cut Sensitivity: [Medium      v]  "How strong a beat..."
  Hard Cut Min Interval:[20s         v]  "Minimum time between..."
  Duration Randomization:[None       v]  "Add variation to..."

Visualization
  Beat Sensitivity:     [Medium      v]  "How strongly the..."
  [x] Aspect Correction                  "Preserve preset aspect..."
  [ ] Mouse Interaction                  "Click or drag on..."
  Mouse Effect:         [Random      v]  "Type of visual effect..."

Presets
  Presets Folder:       [___________] [Browse...]  "Override the default..."
  Sort Order:           [Name A-Z    v]  "Order of presets..."
  Filter:               [___________]    "Comma-separated patterns..."
  Retry Count:          [3           v]  "How many times..."

Diagnostics
  [x] Debug Logging                      "Log diagnostic messages..."
```

Help text is displayed as secondary text (small, gray `NSTextField`) below each control row.

Dependent controls (hard cut sensitivity/interval when hard cuts off, mouse effect when mouse interaction off) are visually dimmed via `setEnabled:NO` and update dynamically when the parent checkbox toggles.

## Out of Scope

- Changes to the right-click context menu (it handles immediate actions and stays as-is)
- XIB/storyboard files (programmatic layout matches existing pattern)
- Preferences search/filter functionality
- Undo/redo for preference changes
- "Reset to defaults" button (could be added later)
- Touch interaction via trackpad gestures (only mouse clicks/drags for now)

## Testing

- Build: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
- Verify each setting takes effect without restarting the component
- Verify FBO half-resolution mode renders correctly and scales up without artifacts
- Verify mouse interaction creates visual effects at the clicked position
- Verify custom presets folder loads .milk files from the specified path
- Verify preset filter excludes non-matching presets
- Verify dependent controls dim/enable correctly in preferences
- Verify all settings persist across foobar2000 restarts
- Verify settings that were changed while visualization was paused take effect on resume
