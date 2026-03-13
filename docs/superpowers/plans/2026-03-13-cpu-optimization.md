# CPU Optimization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce CPU usage across active, idle, and paused visualization states through frame rate management and per-frame overhead elimination.

**Architecture:** Five independent optimizations: stop CVDisplayLink when paused (0% CPU paused), throttle to 30fps when idle (halve idle CPU), replace per-frame heap allocation with stack buffer, cache mach_timebase_info, and remove redundant per-frame coordinate conversion. All changes are in ProjectMView.mm and ProjectMView+Menu.mm.

**Tech Stack:** CVDisplayLink, mach_absolute_time, OpenGL (NSOpenGLView), Objective-C++

**Spec:** `docs/superpowers/specs/2026-03-13-cpu-optimization-design.md`

---

### Task 1: Stop CVDisplayLink when paused

**Files:**
- Modify: `mac/ProjectMView+Menu.mm:444-477` (togglePausePlayback:)
- Modify: `mac/ProjectMView.mm:302-306` (remove early return for paused check in renderFrame)

- [ ] **Step 1: Modify togglePausePlayback: to stop/start CVDisplayLink**

In `mac/ProjectMView+Menu.mm`, replace the entire `togglePausePlayback:` method (lines 444-477) with:

```objc
- (void)togglePausePlayback:(id)sender {
    (void)sender;

    BOOL nowPaused;
    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    BOOL contextLocked = NO;
    @try {
        if (cglContext) {
            CGLLockContext(cglContext);
            contextLocked = YES;
        }

        _isVisualizationPaused = !_isVisualizationPaused;
        nowPaused = _isVisualizationPaused;

        if (!nowPaused) {
            _lastRenderTimestamp = 0;
        }

        if (_projectM) {
            projectm_set_preset_locked(_projectM, PMShouldLockPreset(cfg_preset_shuffle, _isVisualizationPaused, _isAudioPlaybackActive));
        }

        if (contextLocked) {
            CGLUnlockContext(cglContext);
            contextLocked = NO;
        }
    }
    @catch (NSException *exception) {
        PMLogError("projectM: Objective-C exception in togglePausePlayback: ", [[exception description] UTF8String]);
        if (contextLocked) {
            CGLUnlockContext(cglContext);
        }
        return;
    }

    if (nowPaused) {
        if (_displayLink) {
            CVDisplayLinkStop(_displayLink);
        }
    } else {
        if (_displayLink) {
            CVReturn status = CVDisplayLinkStart(_displayLink);
            if (status != kCVReturnSuccess) {
                PMLogError("projectM: CVDisplayLinkStart() failed on unpause.");
            }
        }
    }
}
```

Key changes from current code:
- Capture `nowPaused` local before releasing lock (avoids reading ivar outside lock)
- Reset `_lastRenderTimestamp = 0` on unpause (prevents frame burst)
- After releasing CGL lock: stop CVDisplayLink if pausing, start if unpausing
- Error handling for CVDisplayLinkStart failure on unpause

- [ ] **Step 2: Remove paused early-return from renderFrame**

In `mac/ProjectMView.mm`, remove lines 302-306 (the `_isVisualizationPaused` check inside renderFrame):

```objc
        if (_isVisualizationPaused) {
            CGLUnlockContext(cglContext);
            contextLocked = NO;
            return;
        }
```

This check is no longer needed because the CVDisplayLink is stopped when paused, so renderFrame will never be called in the paused state. Note: there is a brief race between setting the ivar and calling CVDisplayLinkStop (outside the lock), so one final frame may render during that window. This is benign -- a single extra frame is invisible to the user.

- [ ] **Step 3: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000: pause visualization (Space key or menu), confirm CPU drops to ~0%. Unpause, confirm rendering resumes without glitches. Rapid pause/unpause toggling should not deadlock.

- [ ] **Step 4: Commit**

```
fix: stop CVDisplayLink when visualization is paused
```

---

**Note for Tasks 2-4:** Line numbers reference the file as it exists before any modifications. Task 1 removes 5 lines from renderFrame, shifting subsequent line numbers. Match by code content, not line number.

---

### Task 2: Idle throttle to 30fps when no audio

**Files:**
- Modify: `mac/ProjectMView.mm:15-24` (frameDurationInMachTicks)
- Modify: `mac/ProjectMView.mm:309` (frame cap check in renderFrame)

- [ ] **Step 1: Modify frameDurationInMachTicks to accept idle parameter**

In `mac/ProjectMView.mm`, replace lines 15-24:

```cpp
static uint64_t frameDurationInMachTicks() {
    static uint64_t duration = 0;
    if (duration == 0) {
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        double nsPerTick = (double)info.numer / info.denom;
        duration = (uint64_t)((1e9 / 60.0) / nsPerTick);
    }
    return duration;
}
```

With:

```cpp
static uint64_t frameDurationInMachTicks(bool idle) {
    static uint64_t duration60 = 0;
    static uint64_t duration30 = 0;
    if (duration60 == 0) {
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        double nsPerTick = (double)info.numer / info.denom;
        duration60 = (uint64_t)((1e9 / 60.0) / nsPerTick);
        duration30 = (uint64_t)((1e9 / 30.0) / nsPerTick);
    }
    return idle ? duration30 : duration60;
}
```

- [ ] **Step 2: Update frame cap check in renderFrame**

In `mac/ProjectMView.mm`, replace line 309:

```objc
        if (now_mach - _lastRenderTimestamp < frameDurationInMachTicks()) {
```

With:

```objc
        if (now_mach - _lastRenderTimestamp < frameDurationInMachTicks(!_isAudioPlaybackActive)) {
```

Note: `_isAudioPlaybackActive` is one frame behind (updated in `addPCM` after this check). This is acceptable -- one frame at the wrong rate is imperceptible.

- [ ] **Step 3: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000 with debug logging enabled: FPS counter should report ~60fps during playback, ~30fps when playback is stopped. CPU usage should drop noticeably when idle.

- [ ] **Step 4: Commit**

```
fix: throttle rendering to 30fps when no audio is playing
```

---

### Task 3: Stack-allocated audio sample buffer

**Files:**
- Modify: `mac/ProjectMView.mm:466-469` (addPCM heap allocation)

- [ ] **Step 1: Replace vector allocation with stack buffer**

In `mac/ProjectMView.mm`, replace lines 466-469:

```objc
        t_size count = chunk.get_sample_count();
        auto channels = chunk.get_channel_count();
        std::vector<t_int16> data(count * channels, 0);
        audio_math::convert_to_int16(chunk.get_data(), count * channels, data.data(), 1.0);
```

With:

```objc
        t_size count = chunk.get_sample_count();
        auto channels = chunk.get_channel_count();
        t_size totalSamples = count * channels;

        t_int16 stackBuffer[32768];
        t_int16 *pcmData;
        std::vector<t_int16> heapFallback;

        if (totalSamples <= 32768) {
            memset(stackBuffer, 0, totalSamples * sizeof(t_int16));
            pcmData = stackBuffer;
        } else {
            heapFallback.resize(totalSamples, 0);
            pcmData = heapFallback.data();
        }

        audio_math::convert_to_int16(chunk.get_data(), totalSamples, pcmData, 1.0);
```

- [ ] **Step 2: Update pcm_add calls to use pcmData**

In the same method, replace lines 471-474:

```objc
        if (channels == 2)
            projectm_pcm_add_int16(_projectM, data.data(), (unsigned int)count, PROJECTM_STEREO);
        else
            projectm_pcm_add_int16(_projectM, data.data(), (unsigned int)count, PROJECTM_MONO);
```

With:

```objc
        if (channels == 2)
            projectm_pcm_add_int16(_projectM, pcmData, (unsigned int)count, PROJECTM_STEREO);
        else
            projectm_pcm_add_int16(_projectM, pcmData, (unsigned int)count, PROJECTM_MONO);
```

- [ ] **Step 3: Remove unused vector import if no other users**

Check if `<vector>` (line 10 of ProjectMView.mm) is still needed. It is -- the heap fallback path still uses `std::vector`. Keep it.

- [ ] **Step 4: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. Audio-reactive visualization works identically -- presets respond to music as before.

- [ ] **Step 5: Commit**

```
fix: use stack-allocated buffer for PCM audio samples
```

---

### Task 4: Cache mach_timebase_info and remove per-frame getDrawableSizeWidth

**Files:**
- Modify: `mac/ProjectMView.mm:317-328` (FPS counter block)
- Modify: `mac/ProjectMView.mm:330-338` (remove getDrawableSizeWidth from renderFrame)
- Modify: `mac/ProjectMView.mm:221-222` (add cached size writes in createProjectM)

- [ ] **Step 1: Cache mach_timebase_info in FPS counter**

In `mac/ProjectMView.mm`, in the FPS counter block (inside `renderFrame`), replace lines 318-321:

```objc
            if (_fpsCounterStart > 0) {
                mach_timebase_info_data_t tbInfo;
                mach_timebase_info(&tbInfo);
                double elapsed = (double)(now_mach - _fpsCounterStart) * tbInfo.numer / tbInfo.denom / 1e9;
```

With:

```objc
            if (_fpsCounterStart > 0) {
                static mach_timebase_info_data_t tbInfo = {0, 0};
                if (tbInfo.denom == 0) mach_timebase_info(&tbInfo);
                double elapsed = (double)(now_mach - _fpsCounterStart) * tbInfo.numer / tbInfo.denom / 1e9;
```

- [ ] **Step 2: Remove per-frame getDrawableSizeWidth call from renderFrame**

In `mac/ProjectMView.mm`, remove lines 330-338 entirely:

```objc
        int width = 0;
        int height = 0;
        [self getDrawableSizeWidth:&width height:&height];
        if (width != _cachedWidth || height != _cachedHeight) {
            glViewport(0, 0, width, height);
            projectm_set_window_size(_projectM, width, height);
            _cachedWidth = width;
            _cachedHeight = height;
        }
```

The `reshape` method (line 481) already handles size updates under the CGL lock.

- [ ] **Step 3: Set cached dimensions in createProjectM**

In `mac/ProjectMView.mm`, after line 222 (`projectm_set_window_size(_projectM, width, height);`), add:

```objc
    _cachedWidth = width;
    _cachedHeight = height;
```

This ensures the cache is valid before the first `reshape` fires. At this point the CVDisplayLink has not been created yet (happens later in `prepareOpenGL`), so there is no concurrent reader.

- [ ] **Step 4: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. Resize the visualization window -- rendering adapts correctly to the new size. FPS counter still reports accurate values with debug logging enabled.

- [ ] **Step 5: Commit**

```
fix: cache mach_timebase_info and remove per-frame size polling
```
