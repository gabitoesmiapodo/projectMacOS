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

NSDictionary<NSViewFullScreenModeOptionKey, id> *PMVisualizationFullScreenOptions(void) {
    return @{
        NSFullScreenModeAllScreens: @NO,
        NSFullScreenModeApplicationPresentationOptions: @(NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)
    };
}

BOOL PMShouldLockPreset(BOOL shuffleEnabled, BOOL isPaused, BOOL hasActivePlayback, BOOL hardCutsEnabled) {
    if (isPaused || !hasActivePlayback) return YES;
    return !shuffleEnabled && !hardCutsEnabled;
}

NSArray<NSNumber *> *PMPresetDurationOptions(void) {
    static NSArray<NSNumber *> *options;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        options = @[@15, @30, @45, @60];
    });
    return options;
}

int PMValidatedPresetDuration(int requestedDuration) {
    for (NSNumber *option in PMPresetDurationOptions()) {
        if (option.intValue == requestedDuration) {
            return requestedDuration;
        }
    }
    return 30;
}

BOOL PMShouldAdvancePresetOnShuffleToggle(BOOL shuffleEnabled, BOOL isPaused, BOOL hasActivePlayback) {
    (void)shuffleEnabled;
    (void)isPaused;
    (void)hasActivePlayback;
    return NO;
}

BOOL PMShouldResetShuffleTimerOnToggle(BOOL wasShuffleEnabled, BOOL shuffleEnabled) {
    return !wasShuffleEnabled && shuffleEnabled;
}

BOOL PMShouldResetShuffleTimerOnPlaybackTransition(BOOL wasPlaybackActive, BOOL playbackActive, BOOL shuffleEnabled) {
    return !wasPlaybackActive && playbackActive && shuffleEnabled;
}

BOOL PMUseHardCutTransitions(void) {
    return NO;
}

PMPresetRequestType PMPresetRequestAfterEnqueue(PMPresetRequestType current,
                                                PMPresetRequestType incoming) {
    return incoming == PMPresetRequestTypeNone ? current : incoming;
}

double PMRemainingShuffleDurationSeconds(double configuredDuration, double elapsedDuration) {
    double remaining = configuredDuration - elapsedDuration;
    return remaining > PMShuffleDurationFloorSeconds ? remaining : PMShuffleDurationFloorSeconds;
}

BOOL PMShouldScheduleShuffleResume(BOOL isPaused, BOOL shuffleEnabled, BOOL hasPausedProgress) {
    (void)isPaused;
    (void)shuffleEnabled;
    (void)hasPausedProgress;
    return NO;
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

BOOL PMShouldShowOverlayForManualPresetSelection(void) {
    return NO;
}

NSString *PMPresetMenuItemToolTipForPresetPath(NSString *presetPath, NSString *presetsRootDir) {
    if (presetPath.length == 0) return @"";
    return PMFavoriteStoredPathForFullPath(presetPath, presetsRootDir);
}

NSMutableArray<NSDictionary *> *PMFavoritesDeserialize(NSString *json) {
    if (json.length == 0) return [NSMutableArray array];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return [NSMutableArray array];
    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![parsed isKindOfClass:[NSArray class]]) return [NSMutableArray array];
    NSMutableArray *result = [NSMutableArray array];
    for (id entry in (NSArray *)parsed) {
        if (PMFavoriteImportEntryIsValid(entry)) {
            [result addObject:entry];
        }
    }
    return result;
}

NSString *PMFavoritesSerialize(NSArray<NSDictionary *> *favorites) {
    if (favorites.count == 0) return @"";
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:favorites
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (!data) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

void PMFavoritesSortInPlace(NSMutableArray<NSDictionary *> *favorites) {
    if (favorites.count < 2) return;
    [favorites sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSString *lhsName = [lhs[@"name"] isKindOfClass:[NSString class]] ? lhs[@"name"] : @"";
        NSString *rhsName = [rhs[@"name"] isKindOfClass:[NSString class]] ? rhs[@"name"] : @"";
        return [lhsName localizedCaseInsensitiveCompare:rhsName];
    }];
}

BOOL PMFavoritesContainsName(NSArray<NSDictionary *> *favorites, NSString *name) {
    return PMFavoritesIndexOfName(favorites, name) >= 0;
}

NSInteger PMFavoritesIndexOfName(NSArray<NSDictionary *> *favorites, NSString *name) {
    if (name.length == 0 || favorites.count == 0) return -1;
    for (NSUInteger i = 0; i < favorites.count; i++) {
        if ([favorites[i][@"name"] isEqualToString:name]) return (NSInteger)i;
    }
    return -1;
}

NSString *PMFavoriteDisplayName(NSDictionary *entry) {
    NSString *name = entry[@"name"];
    if (name.length == 0) return @"(unknown)";
    NSString *display = [[name lastPathComponent] stringByDeletingPathExtension];
    return display.length > 0 ? display : @"(unknown)";
}

NSString *PMFavoriteStoredPathForFullPath(NSString *fullPath, NSString *presetsDir) {
    if (fullPath.length == 0) return @"";
    if (presetsDir.length == 0) return fullPath;

    NSString *normalizedFull = [fullPath stringByStandardizingPath];
    NSString *normalizedDir = [presetsDir stringByStandardizingPath];
    if (normalizedDir.length == 0) return normalizedFull;

    NSString *dirPrefix = [normalizedDir hasSuffix:@"/"] ? normalizedDir : [normalizedDir stringByAppendingString:@"/"];
    if ([normalizedFull hasPrefix:dirPrefix]) {
        NSString *rel = [normalizedFull substringFromIndex:dirPrefix.length];
        if (rel.length > 0 && ![rel hasPrefix:@"/"]) {
            return rel;
        }
    }

    return normalizedFull;
}

BOOL PMFavoriteImportEntryIsValid(id candidate) {
    if (![candidate isKindOfClass:[NSDictionary class]]) return NO;
    id name = ((NSDictionary *)candidate)[@"name"];
    if (![name isKindOfClass:[NSString class]] || [(NSString *)name length] == 0) return NO;

    id path = ((NSDictionary *)candidate)[@"path"];
    if (path == nil) return YES;
    return [path isKindOfClass:[NSString class]] && [(NSString *)path length] > 0;
}

NSInteger PMNextCycleFavoritesIndex(NSInteger currentIndex, NSUInteger count, PMCycleFavoritesMode mode) {
    if (count == 0) return 0;
    if (mode == PMCycleFavoritesModeDescending) {
        if (currentIndex <= 0) return (NSInteger)(count - 1);
        return currentIndex - 1;
    }
    // Ascending (default)
    NSInteger next = currentIndex + 1;
    if ((NSUInteger)next >= count) return 0;
    return next;
}

NSArray<NSNumber *> *PMBuildRandomFavoritesOrder(NSUInteger count) {
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        [order addObject:@(i)];
    }
    for (NSUInteger i = count; i > 1; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)i);
        [order exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
    }
    return [order copy];
}

BOOL PMShouldDisableCycleFavoritesMenu(NSUInteger favoritesCount) {
    return favoritesCount == 0;
}

PMCycleFavoritesMode PMValidatedCycleFavoritesMode(int rawValue) {
    switch (rawValue) {
        case PMCycleFavoritesModeAscending:  return PMCycleFavoritesModeAscending;
        case PMCycleFavoritesModeDescending: return PMCycleFavoritesModeDescending;
        case PMCycleFavoritesModeRandom:     return PMCycleFavoritesModeRandom;
        default:                             return PMCycleFavoritesModeOff;
    }
}

float PMSensitivityFloatValue(int level) {
    switch (level) {
        case 0: return 0.2f;
        case 1: return 1.0f;
        case 2: return 3.0f;
        case 3: return 5.0f;
        default: return 1.0f;
    }
}

float PMDurationRandomizationFloatValue(int level) {
    switch (level) {
        case 0: return 0.001f;
        case 1: return 0.25f;
        case 2: return 0.5f;
        case 3: return 1.0f;
        default: return 0.001f;
    }
}

int PMMeshSizeForQuality(int quality) {
    switch (quality) {
        case 0: return 64;
        case 1: return 128;
        case 2: return 192;
        default: return 128;
    }
}

int PMValidatedSoftCutDuration(int requested) {
    static const int valid[] = {1, 2, 3, 5};
    for (int i = 0; i < (int)(sizeof(valid) / sizeof(valid[0])); i++) {
        if (valid[i] == requested) return requested;
    }
    return 3;
}

int PMValidatedFpsCap(int requested) {
    static const int valid[] = {0, 30, 45, 60, 90, 120};
    for (int i = 0; i < (int)(sizeof(valid) / sizeof(valid[0])); i++) {
        if (valid[i] == requested) return requested;
    }
    return 60;
}

int PMValidatedIdleFps(int requested) {
    static const int valid[] = {15, 30};
    for (int i = 0; i < (int)(sizeof(valid) / sizeof(valid[0])); i++) {
        if (valid[i] == requested) return requested;
    }
    return 30;
}

int PMValidatedResolutionScale(int requested) {
    if (requested >= 0 && requested <= 2) return requested;
    return 1;
}

int PMValidatedMeshQuality(int requested) {
    if (requested >= 0 && requested <= 2) return requested;
    return 1;
}

int PMValidatedPresetSortOrder(int requested) {
    if (requested == 0 || requested == 1) return requested;
    return 0;
}

NSString *PMNormalizePath(NSString *path) {
    if (path.length == 0) return @"";

    static NSMutableDictionary<NSString *, NSString *> *memo;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        memo = [NSMutableDictionary dictionary];
    });

    os_unfair_lock_lock(&lock);
    NSString *cached = memo[path];
    os_unfair_lock_unlock(&lock);
    if (cached) return cached;

    NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];

    os_unfair_lock_lock(&lock);
    if (!memo[path]) memo[path] = resolved;  // double-check to avoid redundant write
    os_unfair_lock_unlock(&lock);
    return resolved;
}

NSString *PMPresetIndexCachePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/projectMacOS/preset-index.json"];
}

NSString *PMPresetIndexFingerprint(NSString *sourceType, NSTimeInterval mtime, uint64_t sizeOrCount, int sortOrder) {
    if ([sourceType isEqualToString:@"zip"]) {
        return [NSString stringWithFormat:@"zip:%lld:%llu:%d", (long long)mtime, sizeOrCount, sortOrder];
    }
    if ([sourceType isEqualToString:@"folder"]) {
        return [NSString stringWithFormat:@"folder:%lld:%llu:%d", (long long)mtime, sizeOrCount, sortOrder];
    }
    return @"";
}

BOOL PMPresetIndexShouldReuseCache(NSString *cachedFingerprint,
                                   NSString *currentFingerprint,
                                   NSUInteger cachedCount,
                                   uint32_t playlistSize) {
    if (cachedFingerprint.length == 0) return NO;
    if (currentFingerprint.length == 0) return NO;
    if (![cachedFingerprint isEqualToString:currentFingerprint]) return NO;
    return cachedCount == (NSUInteger)playlistSize;
}

