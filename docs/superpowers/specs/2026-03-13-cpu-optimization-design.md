# CPU Optimization Design

## Goal

Reduce CPU usage of the projectMacOS visualization component during active playback, idle (no audio), and paused states through frame rate management and per-frame overhead reduction.

## Context

After the initial 60fps mach_absolute_time cap (which reduced active CPU from ~20-25% to ~12-15%), several optimization opportunities remain:

- **Paused state**: CVDisplayLink fires at 60fps even when paused (~5% CPU doing nothing)
- **Idle state**: Full 60fps rendering when no audio is playing (presets animate but don't react to sound)
- **Per-frame overhead**: Heap allocation, redundant system calls, and unnecessary coordinate conversions on every frame

Hardware reference: MacBook Pro 2019, Intel UHD 630 + AMD Radeon Pro 5500M.

## Design

### 1. Stop CVDisplayLink when paused

When visualization is paused via `togglePausePlayback:`, stop the CVDisplayLink entirely. The last rendered frame remains in the OpenGL front buffer. On unpause, restart the link.

**Thread safety:** `CVDisplayLinkStop` can block until the current callback completes. If called while holding the CGL lock, and the callback is waiting on the CGL lock, deadlock occurs. Therefore CVDisplayLinkStop/Start must be called **outside** the CGL lock. The current `togglePausePlayback:` already releases the CGL lock before line 474, so the stop/start calls go there.

**Behavior on pause:**
1. Acquire CGL lock
2. Set `_isVisualizationPaused = YES`, update preset lock state
3. Release CGL lock
4. Call `CVDisplayLinkStop(_displayLink)` -- outside the lock

**Behavior on unpause:**
1. Acquire CGL lock
2. Reset `_lastRenderTimestamp = 0` (prevents frame burst from stale timestamp)
3. Set `_isVisualizationPaused = NO`, update preset lock state
4. Release CGL lock
5. Call `CVDisplayLinkStart(_displayLink)` -- outside the lock

**Error handling:** If `CVDisplayLinkStart` fails on unpause, log via `PMLogError`. The view remains in a non-rendering state. The user can retry by toggling pause again or closing/reopening the visualization.

**Teardown while paused:** `destroyDisplayLink` calls `CVDisplayLinkStop` on an already-stopped link. The API tolerates this; no special handling needed.

**Display sleep:** macOS suspends CVDisplayLink callbacks when the display sleeps and resumes them on wake. If paused during sleep, the link is already stopped so wake has no effect. If active during sleep, on wake the `_lastRenderTimestamp` delta will be large and a frame renders immediately -- correct behavior.

**Expected savings:** ~5% CPU eliminated entirely when paused (0% instead of ~5%).

**Files:** `mac/ProjectMView+Menu.mm` (togglePausePlayback:)

### 2. Idle throttle to 30fps

When `_isAudioPlaybackActive` is NO, cap rendering at 30fps instead of 60fps. Presets still animate smoothly but CPU work is halved.

**Interface change:** `frameDurationInMachTicks(bool idle)` takes a boolean parameter. Internally, two `static uint64_t` locals store the precomputed 60fps and 30fps durations (both computed on first call). Returns the appropriate one.

**Behavior:**
- In `renderFrame`, call `frameDurationInMachTicks(!_isAudioPlaybackActive)` for the frame cap check
- `_isAudioPlaybackActive` is updated in `addPCM` which runs after the cap check, so the idle state is one frame behind. This is acceptable: one frame at the wrong rate (16ms vs 33ms) is imperceptible to the user. On playback start, the first audio frame renders at 30fps timing; on stop, one extra frame renders at 60fps timing.

**Expected savings:** ~50% reduction in idle CPU (renders half as many frames).

**Files:** `mac/ProjectMView.mm` (frameDurationInMachTicks, renderFrame)

### 3. Stack-allocated audio sample buffer

Replace per-frame heap allocation `std::vector<t_int16> data(count * channels, 0)` in `addPCM` with a stack buffer.

**Behavior:**
- Declare `t_int16 stackBuffer[32768]` on the stack (32768 * 2 bytes = 64KB)
- Use stack buffer when `count * channels <= 32768`
- Fall back to `std::vector` heap allocation if exceeded (safety valve, should never happen in practice)
- Zero only the used portion: `memset(stackBuffer, 0, count * channels * sizeof(t_int16))`, not the full 64KB

**Sizing rationale:** At 44100Hz stereo with dt clamped to max 0.1s, worst case is 4410 * 2 = 8820 int16s. 32768 provides generous headroom. 64KB is 0.01% of the default 512KB macOS thread stack.

**Expected savings:** Eliminates 60 malloc/free cycles per second during active playback.

**Files:** `mac/ProjectMView.mm` (addPCM)

### 4. Cache mach_timebase_info in FPS counter

The FPS counter calls `mach_timebase_info(&tbInfo)` every 300 frames. This is a minor cleanup: make it a `static` local computed once on first use.

**Files:** `mac/ProjectMView.mm` (renderFrame, FPS counter block)

### 5. Remove per-frame getDrawableSizeWidth call

`renderFrame` calls `getDrawableSizeWidth:height:` every frame (involves `convertRectToBacking:`), then compares against cached values. This is redundant because `reshape` already updates `_cachedWidth`/`_cachedHeight` and calls `glViewport`/`projectm_set_window_size` under the CGL lock.

**Behavior:**
- Remove `getDrawableSizeWidth:height:` call and size comparison block from `renderFrame`
- Add `_cachedWidth = width; _cachedHeight = height;` in `createProjectM` so the cache is valid before the first reshape
- `reshape` remains the sole updater of cached dimensions

**Thread safety:** `_cachedWidth`/`_cachedHeight` are written by `reshape` (main thread, under CGL lock) and read by `renderFrame` (CVDisplayLink thread, under CGL lock). Both operations hold the CGL lock, so access is synchronized. In `createProjectM`, the writes happen before the CVDisplayLink is created and started (in `prepareOpenGL`), so there is no concurrent reader at that point.

**Files:** `mac/ProjectMView.mm` (renderFrame, createProjectM)

## Out of scope

- Synchronization changes (`@synchronized`, lock-free config reads) -- uncontended locks cost ~20-50ns/frame, negligible
- Moving processing outside CGL lock -- `processPendingPresetRequestInRenderLoop` is a no-op 99.9% of frames
- Caching config variable reads per frame -- already just memory loads

## Testing

- Build: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
- Verify in foobar2000: active playback renders at 60fps, idle (no audio) at 30fps, paused at 0fps
- With debug logging enabled, FPS counter confirms frame rates
- Verify pause/unpause cycle works correctly (no visual glitches, frame burst, or stuck state)
- Stress test: rapid pause/unpause toggling to verify no deadlocks
- Stress test: rapid window resizing while rendering to verify section 5 is safe
- Verify smooth transition between idle/active when playback starts/stops
