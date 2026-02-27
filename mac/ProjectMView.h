#pragma once

#import "stdafx.h"
#import <CoreVideo/CVDisplayLink.h>
#import <projectM-4/projectM.h>
#import <projectM-4/playlist.h>

extern cfg_bool cfg_preset_shuffle;
extern cfg_string cfg_preset_name;
extern cfg_int cfg_preset_duration;

extern const void *kPresetMenuPathKey;

@interface ProjectMView : NSOpenGLView <NSMenuDelegate, NSWindowDelegate> {
@public
    projectm_handle _projectM;
    projectm_playlist_handle _playlist;
    CVDisplayLinkRef _displayLink;
    visualisation_stream_v2::ptr _visStream;
    double _lastTime;
    double _lastPresetSwitchTimestamp;
    double _remainingShuffleDurationOnPause;
    BOOL _projectMInitialized;
    BOOL _didLogGLInfo;
    BOOL _isVisualizationPaused;
    BOOL _hasPausedShuffleProgress;
    NSUInteger _shuffleResumeToken;
    NSTextField *_presetOverlayLabel;
    NSUInteger _presetOverlayToken;
    NSWindow *_helpWindow;
    NSTextView *_helpTextView;
    NSString *_activePresetsRootPath;
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
/// Persist and optionally display current preset name by playlist index.
- (void)refreshCurrentPresetName:(uint32_t)index showOverlay:(BOOL)showOverlay;
/// Handle runtime preset load failure and continue playback.
- (void)handlePresetLoadFailureForFilename:(NSString *)presetFilename message:(NSString *)message;
@end

@interface ProjectMView (Menu)

/// Apply title truncation and tooltip behavior to a menu item.
- (void)applyMenuTitleLimitToItem:(NSMenuItem *)item fullTitle:(NSString *)fullTitle;
/// Show center overlay with current preset name.
- (void)showPresetOverlayName:(NSString *)presetName;
/// Show centered overlay text, optionally keeping it visible.
- (void)showOverlayText:(NSString *)text persistent:(BOOL)persistent;
/// Hide overlay text immediately.
- (void)hideOverlayText;
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
/// Close help window safely during teardown.
- (void)cleanupHelpWindow;
@end
