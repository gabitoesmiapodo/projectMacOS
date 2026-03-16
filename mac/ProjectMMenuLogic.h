#pragma once

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, PMCycleFavoritesMode) {
    PMCycleFavoritesModeOff = 0,
    PMCycleFavoritesModeAscending,
    PMCycleFavoritesModeDescending,
    PMCycleFavoritesModeRandom,
};

typedef NS_ENUM(NSInteger, PMPresetRequestType) {
    PMPresetRequestTypeNone = 0,
    PMPresetRequestTypeNext,
    PMPresetRequestTypePrevious,
    PMPresetRequestTypeRandom,
    PMPresetRequestTypeSelectPath,
};

/// Truncate long menu titles and report whether truncation occurred.
FOUNDATION_EXPORT NSString *PMTruncatedMenuTitle(NSString *title, BOOL *wasTruncated);
/// Convert persisted preset filename/path into a user-facing display name.
FOUNDATION_EXPORT NSString *PMCurrentPresetDisplayName(NSString *savedPresetName);
/// Apply truncated title and tooltip rules to a menu item.
FOUNDATION_EXPORT void PMApplyMenuTitleLimit(NSMenuItem *item, NSString *fullTitle);
/// Return pause/play menu title based on paused state.
FOUNDATION_EXPORT NSString *PMPauseMenuTitle(BOOL isPaused);
/// Return pause/play SF Symbol name based on paused state.
FOUNDATION_EXPORT NSString *PMPauseMenuSymbolName(BOOL isPaused);
/// Return the persistent overlay text shown while paused.
FOUNDATION_EXPORT NSString *PMPausedOverlayText(void);
/// Return help text foreground color for light/dark theme.
FOUNDATION_EXPORT NSString *PMHelpTextColorHex(BOOL darkMode);
/// Return help text background color for light/dark theme.
FOUNDATION_EXPORT NSString *PMHelpBackgroundColorHex(BOOL darkMode);
/// Build fullscreen options that keep fullscreen on one display.
FOUNDATION_EXPORT NSDictionary<NSViewFullScreenModeOptionKey, id> *PMVisualizationFullScreenOptions(void);
/// Return whether projectM preset lock should be enabled.
FOUNDATION_EXPORT BOOL PMShouldLockPreset(BOOL shuffleEnabled, BOOL isPaused, BOOL hasActivePlayback);
/// Supported preset duration options in seconds.
FOUNDATION_EXPORT NSArray<NSNumber *> *PMPresetDurationOptions(void);
/// Validate configured duration and return a supported value.
FOUNDATION_EXPORT int PMValidatedPresetDuration(int requestedDuration);
/// Return whether shuffle toggle should advance to another preset immediately.
FOUNDATION_EXPORT BOOL PMShouldAdvancePresetOnShuffleToggle(BOOL shuffleEnabled, BOOL isPaused, BOOL hasActivePlayback);
/// Return whether shuffle timer should reset after toggle.
FOUNDATION_EXPORT BOOL PMShouldResetShuffleTimerOnToggle(BOOL wasShuffleEnabled, BOOL shuffleEnabled);
/// Return whether shuffle timer should reset when playback resumes.
FOUNDATION_EXPORT BOOL PMShouldResetShuffleTimerOnPlaybackTransition(BOOL wasPlaybackActive, BOOL playbackActive, BOOL shuffleEnabled);
/// Return whether preset changes should use projectM hard cuts.
FOUNDATION_EXPORT BOOL PMUseHardCutTransitions(void);
/// Coalesce preset requests; latest non-none request wins.
FOUNDATION_EXPORT PMPresetRequestType PMPresetRequestAfterEnqueue(PMPresetRequestType current,
                                                                  PMPresetRequestType incoming);
/// Compute remaining shuffle time in seconds with a minimum floor.
FOUNDATION_EXPORT double PMRemainingShuffleDurationSeconds(double configuredDuration, double elapsedDuration);
/// Return whether resume should defer the next shuffled preset switch.
FOUNDATION_EXPORT BOOL PMShouldScheduleShuffleResume(BOOL isPaused, BOOL shuffleEnabled, BOOL hasPausedProgress);
/// Return whether preset text matches a minimal MilkDrop preset structure.
FOUNDATION_EXPORT BOOL PMIsLikelyMilkPresetContent(NSString *content);
/// Return a non-empty console-safe reason string.
FOUNDATION_EXPORT NSString *PMConsoleReasonOrDefault(NSString *reason);
/// Return whether startup should pre-validate preset file content.
FOUNDATION_EXPORT BOOL PMShouldPrevalidatePresetFilesOnStartup(void);
/// Return a concise name for preset failure logs.
FOUNDATION_EXPORT NSString *PMFailedPresetConsoleName(NSString *presetPathOrName);
/// Return whether fallback should load after a failed preset switch.
FOUNDATION_EXPORT BOOL PMShouldUseFallbackAfterPresetLoadFailure(NSUInteger remainingPresetCount);
/// Return whether a cached ZIP extraction can be reused.
FOUNDATION_EXPORT BOOL PMShouldReuseZipExtractionCache(BOOL hasValidMetadata,
                                                       BOOL fingerprintMatches,
                                                       BOOL cacheLooksValid);
/// Return whether ZIP mtime and size fingerprints match.
FOUNDATION_EXPORT BOOL PMZipCacheFingerprintMatches(NSTimeInterval cachedMTime,
                                                    uint64_t cachedSizeBytes,
                                                    NSTimeInterval currentMTime,
                                                    uint64_t currentSizeBytes);

/// Return whether selecting a preset from the menu should show the overlay preset name.
FOUNDATION_EXPORT BOOL PMShouldShowOverlayForManualPresetSelection(void);

/// Tooltip string for a preset menu item.
/// Returns a relative path (including filename) when presetPath is under presetsRootDir.
/// Otherwise returns an absolute path (or presetPath unchanged if presetsRootDir is nil or empty).
FOUNDATION_EXPORT NSString *PMPresetMenuItemToolTipForPresetPath(NSString *presetPath, NSString *presetsRootDir);

/// Deserialize a JSON string into a mutable array of favorite entry dicts.
/// Returns an empty mutable array for nil, empty, or invalid input.
/// Silently drops any entries that fail PMFavoriteImportEntryIsValid.
FOUNDATION_EXPORT NSMutableArray<NSDictionary *> *PMFavoritesDeserialize(NSString *json);

/// Serialize favorites array to a pretty-printed JSON string.
/// Returns @"" for nil or empty input.
FOUNDATION_EXPORT NSString *PMFavoritesSerialize(NSArray<NSDictionary *> *favorites);

/// Sort favorites in-place by the "name" key (case-insensitive, localized).
/// No-op for nil or fewer than 2 entries.
FOUNDATION_EXPORT void PMFavoritesSortInPlace(NSMutableArray<NSDictionary *> *favorites);

/// Return YES if any entry in favorites has a "name" value equal to name.
FOUNDATION_EXPORT BOOL PMFavoritesContainsName(NSArray<NSDictionary *> *favorites, NSString *name);

/// Return the index of the first entry with "name" == name, or -1 if not found.
FOUNDATION_EXPORT NSInteger PMFavoritesIndexOfName(NSArray<NSDictionary *> *favorites, NSString *name);

/// Return user-facing display name for a favorite entry: lastPathComponent of "name", minus .milk extension.
/// Returns @"(unknown)" if "name" is missing or empty.
FOUNDATION_EXPORT NSString *PMFavoriteDisplayName(NSDictionary *entry);

/// Compute stored favorite path.
/// If fullPath is inside presetsDir, returns a relative path (no leading slash).
/// Otherwise returns fullPath unchanged.
FOUNDATION_EXPORT NSString *PMFavoriteStoredPathForFullPath(NSString *fullPath, NSString *presetsDir);

/// Return YES if candidate is a valid import entry:
/// - must be NSDictionary with a non-empty "name" NSString
/// - if "path" is present, it must be a non-empty NSString
FOUNDATION_EXPORT BOOL PMFavoriteImportEntryIsValid(id candidate);

/// Return next favorites index for ascending/descending cycling with wrap-around.
FOUNDATION_EXPORT NSInteger PMNextCycleFavoritesIndex(NSInteger currentIndex, NSUInteger count, PMCycleFavoritesMode mode);

/// Return a shuffled array of all indices 0..(count-1).
FOUNDATION_EXPORT NSArray<NSNumber *> *PMBuildRandomFavoritesOrder(NSUInteger count);

/// Return YES if the Cycle Favorites menu should be disabled (no favorites available).
FOUNDATION_EXPORT BOOL PMShouldDisableCycleFavoritesMenu(NSUInteger favoritesCount);

/// Return a valid PMCycleFavoritesMode for the raw int stored in cfg_cycle_favorites_mode.
/// Returns PMCycleFavoritesModeOff for any unrecognized value.
FOUNDATION_EXPORT PMCycleFavoritesMode PMValidatedCycleFavoritesMode(int rawValue);

/// Map sensitivity cfg_int (0-3) to float value: 0->0.5, 1->1.0, 2->1.5, 3->2.0.
FOUNDATION_EXPORT float PMSensitivityFloatValue(int level);

/// Map duration randomization cfg_int (0-3) to float: 0->0.001, 1->0.25, 2->0.5, 3->1.0.
FOUNDATION_EXPORT float PMDurationRandomizationFloatValue(int level);

/// Map mesh quality cfg_int (0-2) to mesh size: 0->64, 1->128, 2->192.
FOUNDATION_EXPORT int PMMeshSizeForQuality(int quality);

/// Map hard cut interval cfg_int to seconds. Valid: 5, 10, 20, 30. Default: 20.
FOUNDATION_EXPORT int PMValidatedHardCutInterval(int requested);

/// Map soft cut duration cfg_int to seconds. Valid: 1, 2, 3, 5. Default: 3.
FOUNDATION_EXPORT int PMValidatedSoftCutDuration(int requested);

/// Map FPS cap cfg_int. Valid: 0, 30, 45, 60, 90, 120. Default: 60.
FOUNDATION_EXPORT int PMValidatedFpsCap(int requested);

/// Map idle FPS cfg_int. Valid: 15, 30. Default: 30.
FOUNDATION_EXPORT int PMValidatedIdleFps(int requested);

/// Map resolution scale cfg_int. Valid: 0, 1, 2. Default: 1.
FOUNDATION_EXPORT int PMValidatedResolutionScale(int requested);

/// Map mesh quality cfg_int. Valid: 0, 1, 2. Default: 1.
FOUNDATION_EXPORT int PMValidatedMeshQuality(int requested);

/// Map preset sort order cfg_int. Valid: 0-3. Default: 0.
FOUNDATION_EXPORT int PMValidatedPresetSortOrder(int requested);

