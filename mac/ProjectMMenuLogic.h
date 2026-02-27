#pragma once

#import <Cocoa/Cocoa.h>

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
/// Return whether projectM preset lock should be enabled.
FOUNDATION_EXPORT BOOL PMShouldLockPreset(BOOL shuffleEnabled, BOOL isPaused);
/// Compute remaining shuffle time in seconds with a minimum floor.
FOUNDATION_EXPORT double PMRemainingShuffleDurationSeconds(double configuredDuration, double elapsedDuration);
/// Return whether resume should defer the next shuffled preset switch.
FOUNDATION_EXPORT BOOL PMShouldScheduleShuffleResume(BOOL isPaused, BOOL shuffleEnabled, BOOL hasPausedProgress);
/// Return whether preset text matches a minimal MilkDrop preset structure.
FOUNDATION_EXPORT BOOL PMIsLikelyMilkPresetContent(NSString *content);
/// Return a non-empty console-safe reason string.
FOUNDATION_EXPORT NSString *PMConsoleReasonOrDefault(NSString *reason);
