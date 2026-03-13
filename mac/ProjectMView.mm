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
    }
    return self;
}

- (void)dealloc {
    [self destroyDisplayLink];
    [self cleanupHelpWindow];

    if (_visStream.is_valid()) {
        _visStream.release();
    }

    [self destroyProjectMState];
}

- (void)prepareOpenGL {
    [super prepareOpenGL];

    GLint swapInt = 1;
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
        FB2K_console_print("projectM: CVDisplayLinkCreateWithActiveCGDisplays() failed.");
        return;
    }

    CVReturn callbackStatus = CVDisplayLinkSetOutputCallback(_displayLink, &displayLinkCallback, (__bridge void *)self);
    if (callbackStatus != kCVReturnSuccess) {
        FB2K_console_print("projectM: CVDisplayLinkSetOutputCallback() failed.");
        [self destroyDisplayLink];
        return;
    }

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    CVReturn linkStatus = CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglContext, cglPixelFormat);
    if (linkStatus != kCVReturnSuccess) {
        FB2K_console_print("projectM: CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext() failed.");
        [self destroyDisplayLink];
        return;
    }

    CVReturn startStatus = CVDisplayLinkStart(_displayLink);
    if (startStatus != kCVReturnSuccess) {
        FB2K_console_print("projectM: CVDisplayLinkStart() failed.");
        [self destroyDisplayLink];
    }
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
        FB2K_console_print("projectM: CGL context active=", current ? "yes" : "no");
        if (glVersion) {
            FB2K_console_print("projectM: OpenGL version=", (const char *)glVersion);
        } else {
            FB2K_console_print("projectM: OpenGL version query returned null");
        }
        if (glslVersion) {
            FB2K_console_print("projectM: GLSL version=", (const char *)glslVersion);
        } else {
            FB2K_console_print("projectM: GLSL version query returned null");
        }
        if (glRenderer) {
            FB2K_console_print("projectM: OpenGL renderer=", (const char *)glRenderer);
        } else {
            FB2K_console_print("projectM: OpenGL renderer query returned null");
        }
        _didLogGLInfo = YES;
    }

    float heightWidthRatio = (float)height / (float)width;

    char *runtimeVersion = projectm_get_version_string();
    if (runtimeVersion) {
        FB2K_console_print("projectM: runtime library version=", runtimeVersion);
        projectm_free_string(runtimeVersion);
    }

    cfg_preset_duration = PMValidatedPresetDuration((int)cfg_preset_duration);

    _projectM = projectm_create();
    if (!_projectM) {
        FB2K_console_print("projectM: projectm_create() failed. Verify OpenGL context is current and compatible.");
        return;
    }

    glViewport(0, 0, width, height);
    projectm_set_window_size(_projectM, width, height);
    projectm_set_mesh_size(_projectM, 128, (size_t)(128 * heightWidthRatio));
    projectm_set_fps(_projectM, 60);
    projectm_set_soft_cut_duration(_projectM, 3.0);
    projectm_set_preset_duration(_projectM, (double)cfg_preset_duration);
    projectm_set_hard_cut_enabled(_projectM, PMUseHardCutTransitions());
    projectm_set_hard_cut_duration(_projectM, 20.0);
    projectm_set_hard_cut_sensitivity(_projectM, 1.0f);
    projectm_set_beat_sensitivity(_projectM, 1.0f);
    projectm_set_aspect_correction(_projectM, true);

    _playlist = projectm_playlist_create(_projectM);
    if (!_playlist) {
        FB2K_console_print("projectM: projectm_playlist_create() failed.");
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

        if (_isVisualizationPaused) {
            CGLUnlockContext(cglContext);
            contextLocked = NO;
            return;
        }

        uint64_t now_mach = mach_absolute_time();
        if (now_mach - _lastRenderTimestamp < frameDurationInMachTicks()) {
            CGLUnlockContext(cglContext);
            contextLocked = NO;
            return;
        }
        _lastRenderTimestamp = now_mach;

        int width = 0;
        int height = 0;
        [self getDrawableSizeWidth:&width height:&height];
        if (width != _cachedWidth || height != _cachedHeight) {
            glViewport(0, 0, width, height);
            projectm_set_window_size(_projectM, width, height);
            _cachedWidth = width;
            _cachedHeight = height;
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

        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        projectm_opengl_render_frame(_projectM);

        [[self openGLContext] flushBuffer];

        CGLUnlockContext(cglContext);
        contextLocked = NO;
    }
    @catch (NSException *exception) {
        _projectMInitialized = NO;
        FB2K_console_print("projectM: Objective-C exception in renderFrame: ", [[exception description] UTF8String]);
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
            if (PMShouldResetShuffleTimerOnPlaybackTransition(wasPlaybackActive, _isAudioPlaybackActive, cfg_preset_shuffle)) {
                _pendingShuffleEnable = YES;
                _shuffleEnableDeadline = CFAbsoluteTimeGetCurrent() + (double)PMValidatedPresetDuration((int)cfg_preset_duration);
            } else if (!_isAudioPlaybackActive) {
                _pendingShuffleEnable = NO;
                _shuffleEnableDeadline = 0.0;
            }
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
        std::vector<t_int16> data(count * channels, 0);
        audio_math::convert_to_int16(chunk.get_data(), count * channels, data.data(), 1.0);

        if (channels == 2)
            projectm_pcm_add_int16(_projectM, data.data(), (unsigned int)count, PROJECTM_STEREO);
        else
            projectm_pcm_add_int16(_projectM, data.data(), (unsigned int)count, PROJECTM_MONO);
    }
    @catch (NSException *exception) {
        FB2K_console_print("projectM: Objective-C exception in addPCM: ", [[exception description] UTF8String]);
    }
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

    glViewport(0, 0, width, height);
    projectm_set_window_size(_projectM, width, height);
    _cachedWidth = width;
    _cachedHeight = height;

    CGLUnlockContext(cglContext);
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
