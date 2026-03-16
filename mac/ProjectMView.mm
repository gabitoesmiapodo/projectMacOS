#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#import <OpenGL/gl.h>
#pragma clang diagnostic pop

#import <vector>
#import <mach/mach_time.h>

namespace {

static uint64_t frameDurationInMachTicks(int fpsCap) {
    if (fpsCap <= 0) return 0;  // Unlimited
    static mach_timebase_info_data_t info = {0, 0};
    if (info.denom == 0) mach_timebase_info(&info);
    double nsPerTick = (double)info.numer / info.denom;
    return (uint64_t)((1e9 / (double)fpsCap) / nsPerTick);
}

} // anonymous namespace

namespace {

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                     const CVTimeStamp *now,
                                     const CVTimeStamp *outputTime,
                                     CVOptionFlags flagsIn,
                                     CVOptionFlags *flagsOut,
                                     void *displayLinkContext);

} // anonymous namespace

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation ProjectMView

- (void)destroyDisplayLink {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }
}

- (void)destroyProjectMState {
    if (_projectM) {
        [[self openGLContext] makeCurrentContext];
        [self teardownHalfResFBO];
    }

    if (_playlist) {
        projectm_playlist_destroy(_playlist);
        _playlist = NULL;
    }

    if (_projectM) {
        projectm_destroy(_projectM);
        _projectM = NULL;
    }

    _projectMInitialized = NO;
}

- (instancetype)initWithFrame:(NSRect)frame {
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize, 32,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAStencilSize, 8,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion4_1Core,
        0
    };
    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    self = [super initWithFrame:frame pixelFormat:pixelFormat];
    if (self) {
        [self setWantsBestResolutionOpenGLSurface:(PMValidatedResolutionScale((int)cfg_resolution_scale) == 2)];
        _projectM = NULL;
        _playlist = NULL;
        _displayLink = NULL;
        _lastTime = 0.0;
        _lastPresetSwitchTimestamp = 0.0;
        _shuffleEnableDeadline = 0.0;
        _remainingShuffleDurationOnPause = (double)cfg_preset_duration;
        _projectMInitialized = NO;
        _didLogGLInfo = NO;
        _isVisualizationPaused = NO;
        _isAudioPlaybackActive = NO;
        _pendingShuffleEnable = NO;
        _playlistShuffleEnabled = NO;
        _pendingPresetRequest = PMPresetRequestTypeNone;
        _pendingPresetPath = nil;
        _hasPausedShuffleProgress = NO;
        _shuffleResumeToken = 0;
        _helpWindow = nil;
        _activePresetsRootPath = nil;
        _cycleFavoritesIndex = 0;
        _cycleFavoritesRandomOrder = nil;
        _cycleFavoritesRandomPosition = NSNotFound;
        _cycleFavoritesDeadline = 0.0;
        _cycleFavoritesActive = NO;
        _resolvedCyclePaths = nil;
        _lastRenderTimestamp = 0;
        _cachedWidth = 0;
        _cachedHeight = 0;
        _fpsCounterStart = 0;
        _fpsFrameCount = 0;
        _isAutoPaused = NO;
        _lastSettingsGeneration = 0;
        _halfResFBO = 0;
        _halfResColorRB = 0;
        _halfResDepthRB = 0;
        _halfResWidth = 0;
        _halfResHeight = 0;
        _cachedResolutionScale = PMValidatedResolutionScale((int)cfg_resolution_scale);
        _cachedFpsCap = 60;
        _cachedIdleFps = 30;
        _cachedMeshQuality = 1;
        _lastSortOrder = 0;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self destroyDisplayLink];
    [self cleanupHelpWindow];

    if (_visStream.is_valid()) {
        _visStream.release();
    }

    [self destroyProjectMState];
}

- (void)prepareOpenGL {
    [super prepareOpenGL];

    GLint swapInt = cfg_vsync ? 1 : 0;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLContextParameterSwapInterval];

    static_api_ptr_t<visualisation_manager> visManager;
    visManager->create_stream(_visStream, visualisation_manager::KStreamFlagNewFFT);
    _visStream->request_backlog(0.8);

    int width = 0;
    int height = 0;
    [self getDrawableSizeWidth:&width height:&height];
    [self createProjectM:width height:height];

    [self destroyDisplayLink];

    CVReturn createStatus = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (createStatus != kCVReturnSuccess || !_displayLink) {
        PMLogError("projectM: CVDisplayLinkCreateWithActiveCGDisplays() failed.");
        return;
    }

    CVReturn callbackStatus = CVDisplayLinkSetOutputCallback(_displayLink, &displayLinkCallback, (__bridge void *)self);
    if (callbackStatus != kCVReturnSuccess) {
        PMLogError("projectM: CVDisplayLinkSetOutputCallback() failed.");
        [self destroyDisplayLink];
        return;
    }

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    CVReturn linkStatus = CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglContext, cglPixelFormat);
    if (linkStatus != kCVReturnSuccess) {
        PMLogError("projectM: CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext() failed.");
        [self destroyDisplayLink];
        return;
    }

    CVReturn startStatus = CVDisplayLinkStart(_displayLink);
    if (startStatus != kCVReturnSuccess) {
        PMLogError("projectM: CVDisplayLinkStart() failed.");
        [self destroyDisplayLink];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePlaybackStateChange:)
                                                 name:PMPlaybackStateChangedNotification
                                               object:nil];
}

- (void)createProjectM:(int)width height:(int)height {
    if (width < 128) width = 128;
    if (height < 128) height = 128;

    [[self openGLContext] makeCurrentContext];

    [self destroyProjectMState];

    if (!_didLogGLInfo) {
        CGLContextObj current = CGLGetCurrentContext();
        const GLubyte *glVersion = glGetString(GL_VERSION);
        const GLubyte *glRenderer = glGetString(GL_RENDERER);
        const GLubyte *glslVersion = glGetString(GL_SHADING_LANGUAGE_VERSION);
        PMLog("projectM: CGL context active=", current ? "yes" : "no");
        if (glVersion) {
            PMLog("projectM: OpenGL version=", (const char *)glVersion);
        } else {
            PMLogError("projectM: OpenGL version query returned null");
        }
        if (glslVersion) {
            PMLog("projectM: GLSL version=", (const char *)glslVersion);
        } else {
            PMLogError("projectM: GLSL version query returned null");
        }
        if (glRenderer) {
            PMLog("projectM: OpenGL renderer=", (const char *)glRenderer);
        } else {
            PMLogError("projectM: OpenGL renderer query returned null");
        }
        _didLogGLInfo = YES;
    }

    float heightWidthRatio = (float)height / (float)width;

    char *runtimeVersion = projectm_get_version_string();
    if (runtimeVersion) {
        PMLog("projectM: runtime library version=", runtimeVersion);
        projectm_free_string(runtimeVersion);
    }

    cfg_preset_duration = PMValidatedPresetDuration((int)cfg_preset_duration);

    _projectM = projectm_create();
    if (!_projectM) {
        PMLogError("projectM: projectm_create() failed. Verify OpenGL context is current and compatible.");
        return;
    }

    glViewport(0, 0, width, height);
    projectm_set_window_size(_projectM, width, height);
    _cachedWidth = width;
    _cachedHeight = height;
    int meshSize = PMMeshSizeForQuality(PMValidatedMeshQuality((int)cfg_mesh_quality));
    projectm_set_mesh_size(_projectM, meshSize, (size_t)(meshSize * heightWidthRatio));
    int fpsCap = PMValidatedFpsCap((int)cfg_fps_cap);
    projectm_set_fps(_projectM, fpsCap > 0 ? fpsCap : 60);
    projectm_set_soft_cut_duration(_projectM, (double)PMValidatedSoftCutDuration((int)cfg_soft_cut_duration));
    projectm_set_preset_duration(_projectM, (double)cfg_preset_duration);
    projectm_set_hard_cut_enabled(_projectM, (bool)cfg_hard_cuts);
    projectm_set_hard_cut_duration(_projectM, (double)PMValidatedHardCutInterval((int)cfg_hard_cut_interval));
    projectm_set_hard_cut_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_hard_cut_sensitivity));
    projectm_set_beat_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_beat_sensitivity));
    projectm_set_aspect_correction(_projectM, (bool)cfg_aspect_correction);
    projectm_set_easter_egg(_projectM, PMDurationRandomizationFloatValue((int)cfg_duration_randomization));

    _cachedFpsCap = fpsCap;
    _cachedIdleFps = PMValidatedIdleFps((int)cfg_idle_fps);
    _cachedMeshQuality = PMValidatedMeshQuality((int)cfg_mesh_quality);
    _cachedResolutionScale = PMValidatedResolutionScale((int)cfg_resolution_scale);
    if (_cachedResolutionScale == 0) {
        [self setupHalfResFBO:width height:height];
        glViewport(0, 0, _halfResWidth, _halfResHeight);
        projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
    }
    _lastSettingsGeneration = g_settingsGeneration.load(std::memory_order_relaxed);
    _lastCustomFolder = cfg_custom_presets_folder.get();
    _lastSortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);

    _playlist = projectm_playlist_create(_projectM);
    if (!_playlist) {
        PMLogError("projectM: projectm_playlist_create() failed.");
        [self destroyProjectMState];
        return;
    }

    _lastPresetSwitchTimestamp = 0.0;
    _shuffleEnableDeadline = 0.0;
    _remainingShuffleDurationOnPause = (double)cfg_preset_duration;
    _hasPausedShuffleProgress = NO;
    PMSyncMusicPlaybackState();
    _isAudioPlaybackActive = PMIsMusicPlaybackActive();
    _pendingShuffleEnable = cfg_preset_shuffle && _isAudioPlaybackActive;
    if (_pendingShuffleEnable) {
        _shuffleEnableDeadline = CFAbsoluteTimeGetCurrent() + (double)PMValidatedPresetDuration((int)cfg_preset_duration);
    }
    _shuffleResumeToken = 0;
    _playlistShuffleEnabled = NO;
    _pendingPresetRequest = PMPresetRequestTypeNone;
    _pendingPresetPath = nil;
    _cycleFavoritesActive = NO;
    _cycleFavoritesDeadline = 0.0;
    _resolvedCyclePaths = nil;
    _cycleFavoritesRandomOrder = nil;
    _cycleFavoritesRandomPosition = NSNotFound;
    _cycleFavoritesIndex = 0;

    projectm_playlist_set_shuffle(_playlist, false);

    [self loadPresetsFromCurrentSource];

    PMCycleFavoritesMode persistedCycleMode = PMValidatedCycleFavoritesMode((int)cfg_cycle_favorites_mode);
    if (persistedCycleMode != PMCycleFavoritesModeOff) {
        [self rebuildResolvedCyclePaths];
        NSArray<NSString *> *paths = _resolvedCyclePaths;
        if (paths.count == 0) {
            cfg_cycle_favorites_mode = PMCycleFavoritesModeOff;
        } else {
            if (persistedCycleMode == PMCycleFavoritesModeDescending) {
                _cycleFavoritesIndex = (NSInteger)(paths.count - 1);
            } else if (persistedCycleMode == PMCycleFavoritesModeRandom) {
                _cycleFavoritesRandomOrder = PMBuildRandomFavoritesOrder(paths.count);
                _cycleFavoritesRandomPosition = NSNotFound;
            }
        }
    }

    projectm_set_preset_locked(_projectM, PMShouldLockPreset(cfg_preset_shuffle, _isVisualizationPaused, _isAudioPlaybackActive) || _pendingShuffleEnable);

    _projectMInitialized = YES;
}

- (void)renderFrame {
    if (!_projectMInitialized || !_projectM)
        return;

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    if (!cglContext) {
        return;
    }

    BOOL contextLocked = NO;
    @try {
        CGLLockContext(cglContext);
        contextLocked = YES;

        [[self openGLContext] makeCurrentContext];

        uint64_t now_mach = mach_absolute_time();
        int effectiveFps = _isAudioPlaybackActive ? _cachedFpsCap : _cachedIdleFps;
        uint64_t minDuration = frameDurationInMachTicks(effectiveFps);
        if (minDuration > 0 && now_mach - _lastRenderTimestamp < minDuration) {
            CGLUnlockContext(cglContext);
            contextLocked = NO;
            return;
        }
        _lastRenderTimestamp = now_mach;

        _fpsFrameCount++;
        if (_fpsFrameCount >= 300) {
            if (_fpsCounterStart > 0) {
                static mach_timebase_info_data_t tbInfo = {0, 0};
                if (tbInfo.denom == 0) mach_timebase_info(&tbInfo);
                double elapsed = (double)(now_mach - _fpsCounterStart) * tbInfo.numer / tbInfo.denom / 1e9;
                int fps = (elapsed > 0) ? (int)(300.0 / elapsed) : 0;
                PMLog("projectM: fps=",
                    [[NSString stringWithFormat:@"%d viewport=%dx%d", fps, _cachedWidth, _cachedHeight] UTF8String]);
            }
            _fpsCounterStart = now_mach;
            _fpsFrameCount = 0;
        }

        uint32_t gen = g_settingsGeneration.load(std::memory_order_relaxed);
        if (gen != _lastSettingsGeneration) {
            [self applySettingsFromPreferences];
            _lastSettingsGeneration = gen;
        }

        [self addPCM];

        double now = CFAbsoluteTimeGetCurrent();
        BOOL canShuffle = cfg_preset_shuffle && !_isVisualizationPaused && _isAudioPlaybackActive;
        if (!canShuffle) {
            _pendingShuffleEnable = NO;
            _shuffleEnableDeadline = 0.0;
        }

        BOOL shouldShuffleNow = NO;
        if (canShuffle) {
            if (_pendingShuffleEnable) {
                if (now >= _shuffleEnableDeadline) {
                    _pendingShuffleEnable = NO;
                    shouldShuffleNow = YES;
                }
            } else {
                shouldShuffleNow = YES;
            }
        }

        if (_playlist && _playlistShuffleEnabled != shouldShuffleNow) {
            projectm_playlist_set_shuffle(_playlist, shouldShuffleNow);
            _playlistShuffleEnabled = shouldShuffleNow;
        }

        @synchronized (self) {
            PMCycleFavoritesMode cycleMode = PMValidatedCycleFavoritesMode((int)cfg_cycle_favorites_mode);
            BOOL canCycleFavorites = (cycleMode != PMCycleFavoritesModeOff)
                                     && !_isVisualizationPaused
                                     && _isAudioPlaybackActive;

            if (canCycleFavorites && _cycleFavoritesActive && now >= _cycleFavoritesDeadline) {
                NSArray<NSString *> *paths = _resolvedCyclePaths;
                if (paths.count > 0) {
                    if (cycleMode == PMCycleFavoritesModeRandom) {
                        if (_cycleFavoritesRandomPosition == NSNotFound) {
                            _cycleFavoritesRandomPosition = 0;
                        } else {
                            _cycleFavoritesRandomPosition++;
                            if (_cycleFavoritesRandomPosition >= _cycleFavoritesRandomOrder.count) {
                                _cycleFavoritesRandomOrder = PMBuildRandomFavoritesOrder(paths.count);
                                _cycleFavoritesRandomPosition = 0;
                            }
                        }
                        _cycleFavoritesIndex = [_cycleFavoritesRandomOrder[_cycleFavoritesRandomPosition] integerValue];
                    } else {
                        _cycleFavoritesIndex = PMNextCycleFavoritesIndex(_cycleFavoritesIndex, paths.count, cycleMode);
                    }
                    NSString *path = paths[(NSUInteger)_cycleFavoritesIndex];
                    [self enqueuePresetRequest:PMPresetRequestTypeSelectPath presetPath:path];
                }
                _cycleFavoritesDeadline = now + (double)PMValidatedPresetDuration((int)cfg_preset_duration);
            } else if (!canCycleFavorites && _cycleFavoritesActive) {
                _cycleFavoritesActive = NO;
                _cycleFavoritesDeadline = 0.0;
            } else if (canCycleFavorites && !_cycleFavoritesActive) {
                _cycleFavoritesActive = YES;
                _cycleFavoritesDeadline = now + (double)PMValidatedPresetDuration((int)cfg_preset_duration);
            }
        }

        [self processPendingPresetRequestInRenderLoop];

        projectm_set_preset_locked(_projectM, PMShouldLockPreset(cfg_preset_shuffle, _isVisualizationPaused, _isAudioPlaybackActive) || _pendingShuffleEnable);

        if (_cachedResolutionScale == 0 && _halfResFBO) {
            // Half-resolution: render to FBO, then blit to screen
            glBindFramebuffer(GL_FRAMEBUFFER, _halfResFBO);
            glViewport(0, 0, _halfResWidth, _halfResHeight);
            glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            projectm_opengl_render_frame(_projectM);

            // projectM may leave its own FBOs bound; rebind explicitly
            glBindFramebuffer(GL_READ_FRAMEBUFFER, _halfResFBO);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
            glViewport(0, 0, _cachedWidth, _cachedHeight);
            glBlitFramebuffer(0, 0, _halfResWidth, _halfResHeight,
                              0, 0, _cachedWidth, _cachedHeight,
                              GL_COLOR_BUFFER_BIT, GL_LINEAR);
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
        } else {
            // Standard or Retina: render directly
            glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            projectm_opengl_render_frame(_projectM);
        }

        [[self openGLContext] flushBuffer];

        CGLUnlockContext(cglContext);
        contextLocked = NO;

        // Auto-pause: stop display link after releasing CGL lock
        if (_isAutoPaused && _displayLink && CVDisplayLinkIsRunning(_displayLink)) {
            CVDisplayLinkStop(_displayLink);
            PMLog("projectM: auto-paused (no audio playback)");
        }
    }
    @catch (NSException *exception) {
        _projectMInitialized = NO;
        PMLogError("projectM: Objective-C exception in renderFrame: ", [[exception description] UTF8String]);
        if (contextLocked) {
            CGLUnlockContext(cglContext);
        }
    }
}

- (void)addPCM {
    if (!_visStream.is_valid() || !_projectM)
        return;

    @try {
        BOOL wasPlaybackActive = _isAudioPlaybackActive;
        _isAudioPlaybackActive = PMIsMusicPlaybackActive();

        if (wasPlaybackActive != _isAudioPlaybackActive) {
            PMLog("projectM: playback state changed to ", _isAudioPlaybackActive ? "active" : "inactive");
            if (PMShouldResetShuffleTimerOnPlaybackTransition(wasPlaybackActive, _isAudioPlaybackActive, cfg_preset_shuffle)) {
                _pendingShuffleEnable = YES;
                _shuffleEnableDeadline = CFAbsoluteTimeGetCurrent() + (double)PMValidatedPresetDuration((int)cfg_preset_duration);
            } else if (!_isAudioPlaybackActive) {
                _pendingShuffleEnable = NO;
                _shuffleEnableDeadline = 0.0;
            }
            // Auto-pause: mark for CVDisplayLink stop (actual stop happens after CGL unlock in renderFrame)
            if (cfg_auto_pause && !_isAudioPlaybackActive && !_isVisualizationPaused) {
                _isAutoPaused = YES;
            }
            // Note: auto-pause resume is handled by NSNotification (handlePlaybackStateChange:)
            // because once CVDisplayLink is stopped, addPCM is never called.
        }

        double time;
        if (!_visStream->get_absolute_time(time)) {
            return;
        }

        double dt = time - _lastTime;
        _lastTime = time;

        double min_time = 1.0 / 1000.0;
        double max_time = 1.0 / 10.0;
        bool use_fake = false;

        if (dt < min_time) {
            dt = min_time;
            use_fake = true;
        }
        if (dt > max_time) dt = max_time;

        audio_chunk_impl chunk;
        if (use_fake || !_visStream->get_chunk_absolute(chunk, time - dt, dt))
            _visStream->make_fake_chunk_absolute(chunk, time - dt, dt);

        t_size count = chunk.get_sample_count();
        auto channels = chunk.get_channel_count();
        t_size totalSamples = count * channels;

        t_int16 stackBuffer[32768];
        t_int16 *pcmData;
        std::vector<t_int16> heapFallback;

        if (totalSamples <= 32768) {
            pcmData = stackBuffer;
        } else {
            heapFallback.resize(totalSamples);
            pcmData = heapFallback.data();
        }

        audio_math::convert_to_int16(chunk.get_data(), totalSamples, pcmData, 1.0);

        if (channels == 2)
            projectm_pcm_add_int16(_projectM, pcmData, (unsigned int)count, PROJECTM_STEREO);
        else
            projectm_pcm_add_int16(_projectM, pcmData, (unsigned int)count, PROJECTM_MONO);
    }
    @catch (NSException *exception) {
        PMLogError("projectM: Objective-C exception in addPCM: ", [[exception description] UTF8String]);
    }
}

- (void)handlePlaybackStateChange:(NSNotification *)notification {
    if (!_isAutoPaused) return;
    if (!PMIsMusicPlaybackActive()) return;

    _isAutoPaused = NO;
    _lastRenderTimestamp = 0;

    if (_displayLink && !CVDisplayLinkIsRunning(_displayLink)) {
        CVReturn status = CVDisplayLinkStart(_displayLink);
        if (status != kCVReturnSuccess) {
            PMLogError("projectM: CVDisplayLinkStart() failed on auto-unpause.");
        } else {
            PMLog("projectM: auto-unpaused (playback resumed)");
        }
    }
}

- (void)applySettingsFromPreferences {
    if (!_projectM) return;

    // Immediate projectM API calls (cheap, safe to call even if unchanged)
    projectm_set_beat_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_beat_sensitivity));
    projectm_set_soft_cut_duration(_projectM, (double)PMValidatedSoftCutDuration((int)cfg_soft_cut_duration));
    projectm_set_hard_cut_enabled(_projectM, (bool)cfg_hard_cuts);
    projectm_set_hard_cut_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_hard_cut_sensitivity));
    projectm_set_hard_cut_duration(_projectM, (double)PMValidatedHardCutInterval((int)cfg_hard_cut_interval));
    projectm_set_aspect_correction(_projectM, (bool)cfg_aspect_correction);
    projectm_set_easter_egg(_projectM, PMDurationRandomizationFloatValue((int)cfg_duration_randomization));
    projectm_set_preset_duration(_projectM, (double)PMValidatedPresetDuration((int)cfg_preset_duration));

    int fpsCap = PMValidatedFpsCap((int)cfg_fps_cap);
    projectm_set_fps(_projectM, fpsCap > 0 ? fpsCap : 60);
    _cachedFpsCap = fpsCap;
    _cachedIdleFps = PMValidatedIdleFps((int)cfg_idle_fps);

    // Vsync (called from renderFrame which already holds the CGL lock)
    GLint swapInt = cfg_vsync ? 1 : 0;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLContextParameterSwapInterval];

    // Mesh quality (only if changed -- causes reallocation)
    int meshQuality = PMValidatedMeshQuality((int)cfg_mesh_quality);
    if (meshQuality != _cachedMeshQuality) {
        float heightWidthRatio = (_cachedHeight > 0 && _cachedWidth > 0) ? (float)_cachedHeight / (float)_cachedWidth : 1.0f;
        int meshSize = PMMeshSizeForQuality(meshQuality);
        projectm_set_mesh_size(_projectM, meshSize, (size_t)(meshSize * heightWidthRatio));
        _cachedMeshQuality = meshQuality;
    }

    // Auto-pause evaluation
    if (cfg_auto_pause && !_isAudioPlaybackActive && !_isVisualizationPaused && !_isAutoPaused) {
        _isAutoPaused = YES;
        // Note: don't stop CVDisplayLink here -- we're inside renderFrame on the CVDisplayLink thread.
        // The auto-pause logic in renderFrame handles the actual stop.
    } else if ((!cfg_auto_pause || _isAudioPlaybackActive) && _isAutoPaused) {
        _isAutoPaused = NO;
    }

    // Heavyweight updates: custom folder, sort require playlist reload
    // Detected by comparing current cfg values with cached ivars.
    auto currentFolder = cfg_custom_presets_folder.get();
    int currentSortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);

    if (strcmp(currentFolder.get_ptr(), _lastCustomFolder.get_ptr()) != 0 ||
        currentSortOrder != _lastSortOrder) {
        _lastCustomFolder = currentFolder;
        _lastSortOrder = currentSortOrder;
        PMLog("projectM: reloading presets due to settings change");
        // Dispatch to main thread to avoid blocking the CVDisplayLink thread with file I/O
        // (ZIP extraction and filesystem enumeration in loadPresetsFromCurrentSource).
        dispatch_async(dispatch_get_main_queue(), ^{
            CGLContextObj ctx = [[self openGLContext] CGLContextObj];
            if (ctx) CGLLockContext(ctx);
            [self loadPresetsFromCurrentSource];
            if (ctx) CGLUnlockContext(ctx);
        });
    }

    // Resolution scale
    int resScale = PMValidatedResolutionScale((int)cfg_resolution_scale);
    if (resScale != _cachedResolutionScale) {
        int oldScale = _cachedResolutionScale;

        if (resScale == 0) {
            // Switching to Half: set up FBO (already on CVDisplayLink thread, CGL lock held)
            _cachedResolutionScale = resScale;
            [self setupHalfResFBO:_cachedWidth height:_cachedHeight];
            projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
        } else if (oldScale == 0 && resScale != 0) {
            // Switching from Half to Standard or Retina: tear down FBO first
            [self teardownHalfResFBO];
            _cachedResolutionScale = resScale;
            if (resScale == 2) {
                // Half -> Retina: toggle wantsBestResolutionOpenGLSurface on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setWantsBestResolutionOpenGLSurface:YES];
                    [[self openGLContext] update];
                    int width = 0, height = 0;
                    [self getDrawableSizeWidth:&width height:&height];
                    CGLContextObj ctx = [[self openGLContext] CGLContextObj];
                    if (ctx) CGLLockContext(ctx);
                    glViewport(0, 0, width, height);
                    projectm_set_window_size(self->_projectM, width, height);
                    self->_cachedWidth = width;
                    self->_cachedHeight = height;
                    if (ctx) CGLUnlockContext(ctx);
                });
            } else {
                // Half -> Standard (1x): restore full viewport immediately (CGL lock held)
                glViewport(0, 0, _cachedWidth, _cachedHeight);
                projectm_set_window_size(_projectM, _cachedWidth, _cachedHeight);
            }
        } else {
            // Standard <-> Retina (no FBO involved)
            _cachedResolutionScale = resScale;
            BOOL wantsRetina = (resScale == 2);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setWantsBestResolutionOpenGLSurface:wantsRetina];
                [[self openGLContext] update];
                int width = 0, height = 0;
                [self getDrawableSizeWidth:&width height:&height];
                CGLContextObj ctx = [[self openGLContext] CGLContextObj];
                if (ctx) CGLLockContext(ctx);
                glViewport(0, 0, width, height);
                projectm_set_window_size(self->_projectM, width, height);
                self->_cachedWidth = width;
                self->_cachedHeight = height;
                if (ctx) CGLUnlockContext(ctx);
            });
        }
    }
}

- (void)setupHalfResFBO:(int)fullWidth height:(int)fullHeight {
    [self teardownHalfResFBO];

    _halfResWidth = fullWidth / 2;
    _halfResHeight = fullHeight / 2;
    if (_halfResWidth < 64) _halfResWidth = 64;
    if (_halfResHeight < 64) _halfResHeight = 64;

    glGenFramebuffers(1, &_halfResFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, _halfResFBO);

    glGenRenderbuffers(1, &_halfResColorRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _halfResColorRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, _halfResWidth, _halfResHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _halfResColorRB);

    glGenRenderbuffers(1, &_halfResDepthRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _halfResDepthRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, _halfResWidth, _halfResHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _halfResDepthRB);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        PMLogError("projectM: half-res FBO setup failed, status=",
            [[NSString stringWithFormat:@"0x%X", status] UTF8String]);
        [self teardownHalfResFBO];
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        return;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    PMLog("projectM: half-res FBO created ",
        [[NSString stringWithFormat:@"%dx%d", _halfResWidth, _halfResHeight] UTF8String]);
}

- (void)teardownHalfResFBO {
    if (_halfResFBO) { glDeleteFramebuffers(1, &_halfResFBO); _halfResFBO = 0; }
    if (_halfResColorRB) { glDeleteRenderbuffers(1, &_halfResColorRB); _halfResColorRB = 0; }
    if (_halfResDepthRB) { glDeleteRenderbuffers(1, &_halfResDepthRB); _halfResDepthRB = 0; }
    _halfResWidth = 0;
    _halfResHeight = 0;
}

- (void)reshape {
    [super reshape];
    if (!_projectMInitialized || !_projectM)
        return;

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    if (!cglContext) {
        return;
    }

    CGLLockContext(cglContext);
    [[self openGLContext] update];
    [[self openGLContext] makeCurrentContext];

    int width = 0;
    int height = 0;
    [self getDrawableSizeWidth:&width height:&height];

    _cachedWidth = width;
    _cachedHeight = height;
    if (_cachedResolutionScale == 0) {
        [self setupHalfResFBO:width height:height];
        glViewport(0, 0, _halfResWidth, _halfResHeight);
        projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
    } else {
        glViewport(0, 0, width, height);
        projectm_set_window_size(_projectM, width, height);
    }
    PMLog("projectM: viewport resized to ",
        [[NSString stringWithFormat:@"%dx%d", width, height] UTF8String]);

    CGLUnlockContext(cglContext);
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    if (!_projectMInitialized || !_projectM)
        return;

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    if (!cglContext)
        return;

    CGLLockContext(cglContext);
    [[self openGLContext] update];
    [[self openGLContext] makeCurrentContext];

    int width = 0;
    int height = 0;
    [self getDrawableSizeWidth:&width height:&height];

    if (width != _cachedWidth || height != _cachedHeight) {
        _cachedWidth = width;
        _cachedHeight = height;
        if (_cachedResolutionScale == 0) {
            [self setupHalfResFBO:width height:height];
            glViewport(0, 0, _halfResWidth, _halfResHeight);
            projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
        } else {
            glViewport(0, 0, width, height);
            projectm_set_window_size(_projectM, width, height);
        }
        PMLog("projectM: backing changed, viewport resized to ",
            [[NSString stringWithFormat:@"%dx%d", width, height] UTF8String]);
    }

    CGLUnlockContext(cglContext);

    if (_displayLink) {
        CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
        CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglContext, cglPixelFormat);
    }
}

- (void)getDrawableSizeWidth:(int *)width height:(int *)height {
    NSRect backingBounds = [self convertRectToBacking:[self bounds]];
    int w = (int)backingBounds.size.width;
    int h = (int)backingBounds.size.height;
    if (w < 128) w = 128;
    if (h < 128) h = 128;
    if (width) *width = w;
    if (height) *height = h;
}

@end

#pragma clang diagnostic pop

namespace {

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                     const CVTimeStamp *now,
                                     const CVTimeStamp *outputTime,
                                     CVOptionFlags flagsIn,
                                     CVOptionFlags *flagsOut,
                                     void *displayLinkContext) {
    @autoreleasepool {
        ProjectMView *view = (__bridge ProjectMView *)displayLinkContext;
        [view renderFrame];
    }
    return kCVReturnSuccess;
}

} // anonymous namespace
