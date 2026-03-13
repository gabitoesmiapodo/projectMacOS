#pragma once

#import "stdafx.h"
#import <CoreVideo/CVDisplayLink.h>
#import <projectM-4/projectM.h>
#import <projectM-4/playlist.h>
#import "ProjectMMenuLogic.h"

extern cfg_bool cfg_preset_shuffle;
extern cfg_string cfg_preset_name;
extern cfg_int cfg_preset_duration;
extern cfg_string cfg_preset_favorites;
extern cfg_int cfg_cycle_favorites_mode;
extern cfg_bool cfg_debug_logging;

#define PMLog(...)      do { if (cfg_debug_logging) FB2K_console_print(__VA_ARGS__); } while(0)
#define PMLogError(...) FB2K_console_print(__VA_ARGS__)

bool PMIsMusicPlaybackActive(void);
void PMSyncMusicPlaybackState(void);

extern const void *kPresetMenuPathKey;

@interface ProjectMView : NSOpenGLView <NSMenuDelegate, NSWindowDelegate> {
@public
    projectm_handle _projectM;
    projectm_playlist_handle _playlist;
    CVDisplayLinkRef _displayLink;
    visualisation_stream_v2::ptr _visStream;
    double _lastTime;
    double _lastPresetSwitchTimestamp;
    double _shuffleEnableDeadline;
    double _remainingShuffleDurationOnPause;
    BOOL _projectMInitialized;
    BOOL _didLogGLInfo;
    BOOL _isVisualizationPaused;
    BOOL _isAudioPlaybackActive;
    BOOL _pendingShuffleEnable;
    BOOL _playlistShuffleEnabled;
    PMPresetRequestType _pendingPresetRequest;
    NSString *_pendingPresetPath;
    BOOL _hasPausedShuffleProgress;
    NSUInteger _shuffleResumeToken;
    NSWindow *_helpWindow;
    NSTextView *_helpTextView;
    NSString *_activePresetsRootPath;
    NSMutableArray *_favorites;
    NSString *_currentPresetPath;
    NSInteger _cycleFavoritesIndex;
    NSArray<NSNumber *> *_cycleFavoritesRandomOrder;
    NSUInteger _cycleFavoritesRandomPosition;
    double _cycleFavoritesDeadline;
    BOOL _cycleFavoritesActive;
    NSArray<NSString *> *_resolvedCyclePaths;
    uint64_t _lastRenderTimestamp;
    int _cachedWidth;
    int _cachedHeight;
    uint64_t _fpsCounterStart;
    uint32_t _fpsFrameCount;
}
/// Render one projectM frame.
- (void)renderFrame;
/// Feed PCM samples from foobar2000 into projectM.
- (void)addPCM;
/// Create and configure projectM/playlist objects.
- (void)createProjectM:(int)width height:(int)height;
/// Read drawable size clamped to minimum render dimensions.
- (void)getDrawableSizeWidth:(int *)width height:(int *)height;
@end

@interface ProjectMView (Presets)

/// Resolve default project data directory.
- (NSString *)projectMacOSDataDirectoryPath;
/// Resolve default ZIP path for preset data.
- (NSString *)projectMacOSZipPath;
/// Resolve cache extraction path used for ZIP sources.
- (NSString *)zipExtractionDirectoryPath;
/// Remove extracted ZIP cache directory.
- (void)cleanupExtractedPresetCache;
/// Add preset file paths from a path into the playlist.
- (uint32_t)addPresetsFromPath:(NSString *)path recursive:(BOOL)recursive;
/// Check whether a directory can be used as a preset container.
- (BOOL)isDirectoryPresetContainer:(NSString *)path;
/// Normalize roots that contain a single visible top-level directory.
- (NSString *)normalizedSingleTopLevelDirectoryForRoot:(NSString *)rootPath;
/// Extract preset data ZIP into cache and return resolved root.
- (NSString *)prepareDataDirectoryFromZipAtPath:(NSString *)zipPath;
/// Pick active data source path and report whether ZIP was used.
- (NSString *)resolvedDataDirectoryPathUsedZip:(BOOL *)usedZip;
/// Load built-in fallback preset when external data is unavailable.
- (void)loadDefaultPresetFallback;
/// Load presets from ZIP/folder source into the projectM playlist.
- (void)loadPresetsFromCurrentSource;
/// Return active directory used to populate the preset browser menu.
- (NSString *)presetsDirectoryPath;
/// Return display-ready name for current preset.
- (NSString *)currentPresetDisplayName;
/// Persist current preset name by playlist index.
- (void)refreshCurrentPresetName:(uint32_t)index;
/// Handle runtime preset load failure and continue playback.
- (void)handlePresetLoadFailureForFilename:(NSString *)presetFilename message:(NSString *)message;
@end

@interface ProjectMView (Menu)

/// Enqueue a preset request for processing in the render loop.
- (void)enqueuePresetRequest:(PMPresetRequestType)request presetPath:(NSString *)presetPath;
/// Apply title truncation and tooltip behavior to a menu item.
- (void)applyMenuTitleLimitToItem:(NSMenuItem *)item fullTitle:(NSString *)fullTitle;
/// Populate a preset submenu from a filesystem directory.
- (void)populatePresetMenu:(NSMenu *)menu atPath:(NSString *)directoryPath;
/// Handle preset selection from a menu item.
- (void)selectPresetFromMenuItem:(id)sender;
/// Toggle visualization fullscreen mode.
- (void)toggleVisualizationFullScreen;
/// Apply an SF Symbol image to a menu item.
- (void)applySystemSymbol:(NSString *)symbolName toMenuItem:(NSMenuItem *)item;
/// Pause or resume visualization updates.
- (void)togglePausePlayback:(id)sender;
/// Open the component help window.
- (void)showHelp:(id)sender;
/// Build the right-click context menu.
- (NSMenu *)buildContextMenu;
/// Consume queued preset action from render thread.
- (void)processPendingPresetRequestInRenderLoop;
/// Close help window safely during teardown.
- (void)cleanupHelpWindow;
/// Lazy-load favorites from cfg_preset_favorites. Returns _favorites, creating it if nil.
- (NSMutableArray<NSDictionary *> *)loadedFavorites;
/// Serialize _favorites back to cfg_preset_favorites.
- (void)persistFavorites;
/// Return YES if the currently active preset (cfg_preset_name) is in the favorites list.
- (BOOL)isCurrentPresetAFavorite;
/// Save the current preset to favorites if not already present.
- (void)saveCurrentToFavorites:(id)sender;
/// Load a favorite entry: enqueue select-path request and disable shuffle.
- (void)loadFavoriteEntry:(NSDictionary *)entry;
/// Action target for "Load" items in favorite submenus.
- (void)loadFavoriteFromMenuItem:(id)sender;
/// Action target for "Remove" items in favorite submenus; shows confirmation alert.
- (void)removeFavoriteFromMenuItem:(id)sender;
/// Show NSAlert asking for confirmation, then remove entry from favorites.
- (void)promptRemoveFavoriteEntry:(NSDictionary *)entry;
/// Export favorites list via NSSavePanel to a .json file.
- (void)saveFavoritesList:(id)sender;
/// Import favorites list via NSOpenPanel from a .json file (deduplicates, validates).
- (void)loadFavoritesList:(id)sender;
/// Set cycle favorites mode; toggles off if tapped mode matches current.
- (void)setCycleFavoritesMode:(id)sender;
/// Rebuild _resolvedCyclePaths from current loadedFavorites.
- (void)rebuildResolvedCyclePaths;
/// Disable shuffle and cycle favorites (called on any manual preset selection).
- (void)disableAutoplay;
@end
