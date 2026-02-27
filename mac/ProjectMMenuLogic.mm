#import "ProjectMMenuLogic.h"

static const NSUInteger PMMenuTitleMaxLength = 32;
static const NSUInteger PMMenuTitleEllipsisLength = 3;
static const NSUInteger PMMenuTitlePrefixLength = PMMenuTitleMaxLength - PMMenuTitleEllipsisLength;
static const double PMShuffleDurationFloorSeconds = 0.05;

NSString *PMTruncatedMenuTitle(NSString *title, BOOL *wasTruncated) {
    NSString *safeTitle = title ?: @"";
    BOOL truncated = safeTitle.length > PMMenuTitleMaxLength;

    if (wasTruncated != nil) {
        *wasTruncated = truncated;
    }

    if (!truncated) {
        return safeTitle;
    }

    NSRange prefixRange = NSMakeRange(0, PMMenuTitlePrefixLength);
    NSRange safeRange = [safeTitle rangeOfComposedCharacterSequencesForRange:prefixRange];
    NSString *prefix = [safeTitle substringWithRange:safeRange];
    return [prefix stringByAppendingString:@"..."];
}

NSString *PMCurrentPresetDisplayName(NSString *savedPresetName) {
    if (savedPresetName == nil || savedPresetName.length == 0) {
        return @"(No preset)";
    }

    static NSSet<NSString *> *sentinelNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sentinelNames = [NSSet setWithArray:@[
            @"idle://",
            @"fallback-default.milk",
            @"projectMacOS.milk",
        ]];
    });

    if ([sentinelNames containsObject:savedPresetName]) {
        return @"projectMacOS";
    }

    NSString *displayName = [[savedPresetName lastPathComponent] stringByDeletingPathExtension];
    return displayName.length > 0 ? displayName : @"(No preset)";
}

void PMApplyMenuTitleLimit(NSMenuItem *item, NSString *fullTitle) {
    if (item == nil) {
        return;
    }

    BOOL wasTruncated = NO;
    NSString *displayTitle = PMTruncatedMenuTitle(fullTitle, &wasTruncated);
    item.title = displayTitle;
    item.toolTip = wasTruncated ? (fullTitle ?: @"") : nil;
}

NSString *PMPauseMenuTitle(BOOL isPaused) {
    return isPaused ? @"Resume" : @"Pause";
}

NSString *PMPauseMenuSymbolName(BOOL isPaused) {
    return isPaused ? @"play.fill" : @"pause.fill";
}

NSString *PMPausedOverlayText(void) {
    return @"Visualization paused, click to resume";
}

NSString *PMHelpTextColorHex(BOOL darkMode) {
    return darkMode ? @"#f5f5f5" : @"#111111";
}

NSString *PMHelpBackgroundColorHex(BOOL darkMode) {
    return darkMode ? @"#000000" : @"#ffffff";
}

BOOL PMShouldLockPreset(BOOL shuffleEnabled, BOOL isPaused) {
    return isPaused || !shuffleEnabled;
}

double PMRemainingShuffleDurationSeconds(double configuredDuration, double elapsedDuration) {
    double remaining = configuredDuration - elapsedDuration;
    return remaining > PMShuffleDurationFloorSeconds ? remaining : PMShuffleDurationFloorSeconds;
}

BOOL PMShouldScheduleShuffleResume(BOOL isPaused, BOOL shuffleEnabled, BOOL hasPausedProgress) {
    return !isPaused && shuffleEnabled && hasPausedProgress;
}

BOOL PMIsLikelyMilkPresetContent(NSString *content) {
    if (content == nil || content.length == 0) {
        return NO;
    }

    NSString *normalized = content;
    if ([normalized hasPrefix:@"\uFEFF"]) {
        normalized = [normalized substringFromIndex:1];
    }

    NSArray<NSString *> *lines = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }

        if (![trimmed hasPrefix:@"["] || ![trimmed hasSuffix:@"]"]) {
            return NO;
        }

        NSString *lowercased = [trimmed lowercaseString];
        return [lowercased hasPrefix:@"[preset"];
    }

    return NO;
}

NSString *PMConsoleReasonOrDefault(NSString *reason) {
    if (reason != nil && reason.length > 0) {
        return reason;
    }

    return @"unknown validation failure";
}

BOOL PMShouldPrevalidatePresetFilesOnStartup(void) {
    return NO;
}

NSString *PMFailedPresetConsoleName(NSString *presetPathOrName) {
    if (presetPathOrName == nil || presetPathOrName.length == 0) {
        return @"(unknown preset)";
    }

    NSString *filename = [presetPathOrName lastPathComponent];
    return filename.length > 0 ? filename : presetPathOrName;
}

BOOL PMShouldUseFallbackAfterPresetLoadFailure(NSUInteger remainingPresetCount) {
    return remainingPresetCount == 0;
}

BOOL PMShouldReuseZipExtractionCache(BOOL hasValidMetadata,
                                     BOOL fingerprintMatches,
                                     BOOL cacheLooksValid) {
    return hasValidMetadata && fingerprintMatches && cacheLooksValid;
}

BOOL PMZipCacheFingerprintMatches(NSTimeInterval cachedMTime,
                                  uint64_t cachedSizeBytes,
                                  NSTimeInterval currentMTime,
                                  uint64_t currentSizeBytes) {
    return cachedMTime == currentMTime && cachedSizeBytes == currentSizeBytes;
}
