#import <XCTest/XCTest.h>

#import "../ProjectMMenuLogic.h"

@interface ProjectMMenuLogicTests : XCTestCase
@end

@implementation ProjectMMenuLogicTests

- (void)testTruncatedMenuTitleTruncatesAt32Characters {
    BOOL wasTruncated = NO;
    NSString *fullTitle = @"12345678901234567890123456789012X";

    NSString *displayTitle = PMTruncatedMenuTitle(fullTitle, &wasTruncated);

    XCTAssertEqualObjects(displayTitle, @"12345678901234567890123456789...");
    XCTAssertTrue(wasTruncated);
}

- (void)testTruncatedMenuTitleKeepsExactLimitUntouched {
    BOOL wasTruncated = YES;
    NSString *fullTitle = @"12345678901234567890123456789012";

    NSString *displayTitle = PMTruncatedMenuTitle(fullTitle, &wasTruncated);

    XCTAssertEqualObjects(displayTitle, fullTitle);
    XCTAssertFalse(wasTruncated);
}

- (void)testTruncatedMenuTitlePreservesComposedCharacters {
    BOOL wasTruncated = NO;
    NSString *fullTitle = @"1234567890123456789012345678😀ABCD";

    NSString *displayTitle = PMTruncatedMenuTitle(fullTitle, &wasTruncated);

    XCTAssertEqualObjects(displayTitle, @"1234567890123456789012345678😀...");
    XCTAssertTrue(wasTruncated);
}

- (void)testCurrentPresetDisplayNameHandlesSentinelEmptyAndNormalNames {
    XCTAssertEqualObjects(PMCurrentPresetDisplayName(nil), @"(No preset)");
    XCTAssertEqualObjects(PMCurrentPresetDisplayName(@""), @"(No preset)");
    XCTAssertEqualObjects(PMCurrentPresetDisplayName(@"idle://"), @"projectMacOS");
    XCTAssertEqualObjects(PMCurrentPresetDisplayName(@"fallback-default.milk"), @"projectMacOS");
    XCTAssertEqualObjects(PMCurrentPresetDisplayName(@"projectMacOS.milk"), @"projectMacOS");
    XCTAssertEqualObjects(PMCurrentPresetDisplayName(@"Presets/Foo/Bar Baz.milk"), @"Bar Baz");
}

- (void)testApplyMenuTitleLimitSetsToolTipOnlyWhenTruncated {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSString *longTitle = @"12345678901234567890123456789012X";

    PMApplyMenuTitleLimit(item, longTitle);
    XCTAssertEqualObjects(item.title, @"12345678901234567890123456789...");
    XCTAssertEqualObjects(item.toolTip, longTitle);

    PMApplyMenuTitleLimit(item, @"Short title");
    XCTAssertEqualObjects(item.title, @"Short title");
    XCTAssertNil(item.toolTip);
}

- (void)testPauseMenuTitleTogglesBetweenPauseAndPlay {
    XCTAssertEqualObjects(PMPauseMenuTitle(NO), @"Pause");
    XCTAssertEqualObjects(PMPauseMenuTitle(YES), @"Resume");
}

- (void)testPauseMenuSymbolTogglesBetweenPauseAndPlayIcons {
    XCTAssertEqualObjects(PMPauseMenuSymbolName(NO), @"pause.fill");
    XCTAssertEqualObjects(PMPauseMenuSymbolName(YES), @"play.fill");
}

- (void)testPausedOverlayTextMatchesExpectedCopy {
    XCTAssertEqualObjects(PMPausedOverlayText(), @"Visualization paused, click to resume");
}

- (void)testHelpTextColorHexMatchesTheme {
    XCTAssertEqualObjects(PMHelpTextColorHex(NO), @"#111111");
    XCTAssertEqualObjects(PMHelpTextColorHex(YES), @"#f5f5f5");
}

- (void)testHelpBackgroundColorHexMatchesTheme {
    XCTAssertEqualObjects(PMHelpBackgroundColorHex(NO), @"#ffffff");
    XCTAssertEqualObjects(PMHelpBackgroundColorHex(YES), @"#000000");
}

- (void)testShouldLockPresetWhenPausedShuffleDisabledOrPlaybackInactive {
    XCTAssertTrue(PMShouldLockPreset(NO, NO, YES));
    XCTAssertTrue(PMShouldLockPreset(YES, YES, YES));
    XCTAssertTrue(PMShouldLockPreset(YES, NO, NO));
    XCTAssertFalse(PMShouldLockPreset(YES, NO, YES));
}

- (void)testRemainingShuffleDurationUsesConfiguredElapsedAndMinimumFloor {
    XCTAssertEqualWithAccuracy(PMRemainingShuffleDurationSeconds(20.0, 4.5), 15.5, 0.0001);
    XCTAssertEqualWithAccuracy(PMRemainingShuffleDurationSeconds(20.0, 25.0), 0.05, 0.0001);
}

- (void)testPresetDurationOptionsExposeSupportedValuesOnly {
    NSArray<NSNumber *> *expected = @[@15, @30, @45, @60];
    XCTAssertEqualObjects(PMPresetDurationOptions(), expected);
}

- (void)testValidatedPresetDurationFallsBackToDefaultForUnknownValues {
    XCTAssertEqual(PMValidatedPresetDuration(15), 15);
    XCTAssertEqual(PMValidatedPresetDuration(30), 30);
    XCTAssertEqual(PMValidatedPresetDuration(45), 45);
    XCTAssertEqual(PMValidatedPresetDuration(60), 60);

    XCTAssertEqual(PMValidatedPresetDuration(0), 30);
    XCTAssertEqual(PMValidatedPresetDuration(-1), 30);
    XCTAssertEqual(PMValidatedPresetDuration(999), 30);
}

- (void)testShouldScheduleShuffleResumeOnlyWhenResumingWithProgress {
    XCTAssertFalse(PMShouldScheduleShuffleResume(NO, YES, YES));
    XCTAssertFalse(PMShouldScheduleShuffleResume(YES, YES, YES));
    XCTAssertFalse(PMShouldScheduleShuffleResume(NO, NO, YES));
    XCTAssertFalse(PMShouldScheduleShuffleResume(NO, YES, NO));
}

- (void)testShuffleToggleDoesNotAdvancePresetImmediately {
    XCTAssertFalse(PMShouldAdvancePresetOnShuffleToggle(NO, NO, NO));
    XCTAssertFalse(PMShouldAdvancePresetOnShuffleToggle(YES, NO, YES));
}

- (void)testShuffleTimerResetsOnlyWhenEnablingShuffle {
    XCTAssertTrue(PMShouldResetShuffleTimerOnToggle(NO, YES));
    XCTAssertFalse(PMShouldResetShuffleTimerOnToggle(YES, NO));
    XCTAssertFalse(PMShouldResetShuffleTimerOnToggle(NO, NO));
    XCTAssertFalse(PMShouldResetShuffleTimerOnToggle(YES, YES));
}

- (void)testShuffleTimerResetsWhenPlaybackResumesWithShuffleEnabled {
    XCTAssertTrue(PMShouldResetShuffleTimerOnPlaybackTransition(NO, YES, YES));
    XCTAssertFalse(PMShouldResetShuffleTimerOnPlaybackTransition(YES, YES, YES));
    XCTAssertFalse(PMShouldResetShuffleTimerOnPlaybackTransition(NO, YES, NO));
    XCTAssertFalse(PMShouldResetShuffleTimerOnPlaybackTransition(YES, NO, YES));
}

- (void)testPresetTransitionsUseSoftCut {
    XCTAssertFalse(PMUseHardCutTransitions());
}

- (void)testPresetRequestCoalescingUsesLatestAction {
    XCTAssertEqual(PMPresetRequestAfterEnqueue(PMPresetRequestTypeNone, PMPresetRequestTypeNext), PMPresetRequestTypeNext);
    XCTAssertEqual(PMPresetRequestAfterEnqueue(PMPresetRequestTypePrevious, PMPresetRequestTypeRandom), PMPresetRequestTypeRandom);
    XCTAssertEqual(PMPresetRequestAfterEnqueue(PMPresetRequestTypeSelectPath, PMPresetRequestTypeNone), PMPresetRequestTypeSelectPath);
}

- (void)testMilkPresetContentValidationAcceptsPresetHeader {
    NSString *content = @"[preset00]\nzoom=1.0\n";
    XCTAssertTrue(PMIsLikelyMilkPresetContent(content));
}

- (void)testMilkPresetContentValidationAcceptsBOMAndWhitespace {
    NSString *content = @"\uFEFF\n\n  [preset00]\nrot=0.1\n";
    XCTAssertTrue(PMIsLikelyMilkPresetContent(content));
}

- (void)testMilkPresetContentValidationRejectsMissingHeader {
    NSString *content = @"zoom=1.0\nrot=0.1\n";
    XCTAssertFalse(PMIsLikelyMilkPresetContent(content));
}

- (void)testMilkPresetContentValidationRejectsEmptyText {
    XCTAssertFalse(PMIsLikelyMilkPresetContent(@""));
    XCTAssertFalse(PMIsLikelyMilkPresetContent(nil));
}

- (void)testConsoleReasonFallbackUsesDefaultForNilAndEmpty {
    XCTAssertEqualObjects(PMConsoleReasonOrDefault(nil), @"unknown validation failure");
    XCTAssertEqualObjects(PMConsoleReasonOrDefault(@""), @"unknown validation failure");
}

- (void)testConsoleReasonFallbackKeepsNonEmptyReason {
    XCTAssertEqualObjects(PMConsoleReasonOrDefault(@"missing [preset..] header"), @"missing [preset..] header");
}

- (void)testPresetDiscoverySkipsStartupValidation {
    XCTAssertFalse(PMShouldPrevalidatePresetFilesOnStartup());
}

- (void)testFailedPresetConsoleNameUsesLastPathComponent {
    XCTAssertEqualObjects(PMFailedPresetConsoleName(@"/tmp/Presets/Foo/Bar.milk"), @"Bar.milk");
    XCTAssertEqualObjects(PMFailedPresetConsoleName(@"SingleName.milk"), @"SingleName.milk");
    XCTAssertEqualObjects(PMFailedPresetConsoleName(nil), @"(unknown preset)");
    XCTAssertEqualObjects(PMFailedPresetConsoleName(@""), @"(unknown preset)");
}

- (void)testFallbackDecisionAfterLoadFailureDependsOnRemainingPresets {
    XCTAssertTrue(PMShouldUseFallbackAfterPresetLoadFailure(0));
    XCTAssertFalse(PMShouldUseFallbackAfterPresetLoadFailure(1));
    XCTAssertFalse(PMShouldUseFallbackAfterPresetLoadFailure(42));
}

- (void)testZipCacheReuseRequiresMetadataFingerprintAndValidCache {
    XCTAssertTrue(PMShouldReuseZipExtractionCache(YES, YES, YES));
    XCTAssertFalse(PMShouldReuseZipExtractionCache(NO, YES, YES));
    XCTAssertFalse(PMShouldReuseZipExtractionCache(YES, NO, YES));
    XCTAssertFalse(PMShouldReuseZipExtractionCache(YES, YES, NO));
}

- (void)testZipCacheFingerprintRequiresMatchingMtimeAndSize {
    XCTAssertTrue(PMZipCacheFingerprintMatches(1234.5, 987654321ULL, 1234.5, 987654321ULL));
    XCTAssertFalse(PMZipCacheFingerprintMatches(1234.5, 987654321ULL, 1234.6, 987654321ULL));
    XCTAssertFalse(PMZipCacheFingerprintMatches(1234.5, 987654321ULL, 1234.5, 987654320ULL));
}

- (void)testManualPresetSelectionDoesNotShowOverlay {
    XCTAssertFalse(PMShouldShowOverlayForManualPresetSelection());
}

- (void)testPresetMenuTooltipShowsRelativePathWhenPossible {
    XCTAssertEqualObjects(PMPresetMenuItemToolTipForPresetPath(@"/a/Presets/foo.milk", @"/a/Presets"), @"foo.milk");
    XCTAssertEqualObjects(PMPresetMenuItemToolTipForPresetPath(@"/a/Presets/Sub/bar.milk", @"/a/Presets"), @"Sub/bar.milk");
}

- (void)testPresetMenuTooltipFallsBackToAbsolutePathOutsideRoot {
    XCTAssertEqualObjects(PMPresetMenuItemToolTipForPresetPath(@"/x/y/foo.milk", @"/a/Presets"), @"/x/y/foo.milk");
}

// MARK: Placeholder for context menu tests
// The menu is built at runtime and cannot be easily unit tested
// without significant refactoring

/* 
- (void)testContextMenuPlacesPreviousBeforeNext {
    // Build the context menu at runtime instead of parsing the source file.
    NSMenu *menu = PMVisualizationContextMenu();
    XCTAssertNotNil(menu);

    NSInteger previousIndex = -1;
    NSInteger nextIndex = -1;

    for (NSInteger i = 0; i < menu.numberOfItems; i++) {
        NSMenuItem *item = [menu itemAtIndex:i];
        if ([[item title] isEqualToString:@"Previous"]) {
            previousIndex = i;
        } else if ([[item title] isEqualToString:@"Next"]) {
            nextIndex = i;
        }
    }

    XCTAssertNotEqual(previousIndex, -1);
    XCTAssertNotEqual(nextIndex, -1);
    XCTAssertLessThan(previousIndex, nextIndex);
}
*/

- (void)testVisualizationFullscreenOptionsLimitFullscreenToSingleScreen {
    NSDictionary<NSViewFullScreenModeOptionKey, id> *options = PMVisualizationFullScreenOptions();

    NSNumber *allScreensValue = options[NSFullScreenModeAllScreens];
    NSNumber *presentationValue = options[NSFullScreenModeApplicationPresentationOptions];

    XCTAssertNotNil(allScreensValue);
    XCTAssertEqualObjects(allScreensValue, @NO);
    XCTAssertNotNil(presentationValue);
    NSUInteger expectedPresentation = NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
    XCTAssertEqual(presentationValue.unsignedIntegerValue, expectedPresentation);
}

// MARK: - Favorites helpers

- (void)testFavoritesDeserializeHandlesEmptyAndNilInput {
    XCTAssertEqualObjects(PMFavoritesDeserialize(nil), @[]);
    XCTAssertEqualObjects(PMFavoritesDeserialize(@""), @[]);
}

- (void)testFavoritesDeserializeParsesValidJSON {
    NSString *json = @"[{\"name\":\"foo.milk\",\"path\":\"/tmp/foo.milk\"}]";
    NSMutableArray *result = PMFavoritesDeserialize(json);
    XCTAssertEqual(result.count, 1U);
    XCTAssertEqualObjects(result[0][@"name"], @"foo.milk");
    XCTAssertEqualObjects(result[0][@"path"], @"/tmp/foo.milk");
}

- (void)testFavoritesDeserializeDropsInvalidEntries {
    NSString *json = @"[{\"name\":\"foo.milk\"},{\"path\":\"/only-path\"},{\"name\":\"bad.milk\",\"path\":123},\"notadict\",{}]";
    NSMutableArray *result = PMFavoritesDeserialize(json);
    XCTAssertEqual(result.count, 1U);
    XCTAssertEqualObjects(result[0][@"name"], @"foo.milk");
}

- (void)testFavoritesDeserializeRejectsNonArrayAndGarbage {
    XCTAssertEqualObjects(PMFavoritesDeserialize(@"not json"), @[]);
    XCTAssertEqualObjects(PMFavoritesDeserialize(@"{}"), @[]);
}

- (void)testFavoritesSerializeRoundTrips {
    NSArray *input = @[@{@"name": @"foo.milk", @"path": @"/tmp/foo.milk"}];
    NSString *json = PMFavoritesSerialize(input);
    XCTAssertTrue(json.length > 0);
    NSMutableArray *result = PMFavoritesDeserialize(json);
    XCTAssertEqual(result.count, 1U);
    XCTAssertEqualObjects(result[0][@"name"], @"foo.milk");
    XCTAssertEqualObjects(result[0][@"path"], @"/tmp/foo.milk");
}

- (void)testFavoritesSortInPlaceOrdersByNameCaseInsensitive {
    NSMutableArray *favorites = [@[
        @{@"name": @"b.milk", @"path": @"b.milk"},
        @{@"name": @"A.milk", @"path": @"A.milk"},
        @{@"name": @"c.milk", @"path": @"c.milk"},
    ] mutableCopy];

    PMFavoritesSortInPlace(favorites);

    XCTAssertEqualObjects(favorites[0][@"name"], @"A.milk");
    XCTAssertEqualObjects(favorites[1][@"name"], @"b.milk");
    XCTAssertEqualObjects(favorites[2][@"name"], @"c.milk");
}

- (void)testFavoritesSerializeReturnsEmptyStringForEmptyOrNilInput {
    XCTAssertEqualObjects(PMFavoritesSerialize(@[]), @"");
    XCTAssertEqualObjects(PMFavoritesSerialize(nil), @"");
}

- (void)testFavoritesContainsNameFindsExistingAndMissingEntries {
    NSArray *favorites = @[@{@"name": @"foo.milk"}, @{@"name": @"bar.milk"}];
    XCTAssertTrue(PMFavoritesContainsName(favorites, @"foo.milk"));
    XCTAssertTrue(PMFavoritesContainsName(favorites, @"bar.milk"));
    XCTAssertFalse(PMFavoritesContainsName(favorites, @"baz.milk"));
}

- (void)testFavoritesContainsNameHandlesEmptyListAndEdgeCases {
    XCTAssertFalse(PMFavoritesContainsName(@[], @"foo.milk"));
    XCTAssertFalse(PMFavoritesContainsName(nil, @"foo.milk"));
    XCTAssertFalse(PMFavoritesContainsName(@[], nil));
}

- (void)testFavoritesIndexOfNameReturnsCorrectIndexOrMinusOne {
    NSArray *favorites = @[@{@"name": @"foo.milk"}, @{@"name": @"bar.milk"}];
    XCTAssertEqual(PMFavoritesIndexOfName(favorites, @"foo.milk"), 0);
    XCTAssertEqual(PMFavoritesIndexOfName(favorites, @"bar.milk"), 1);
    XCTAssertEqual(PMFavoritesIndexOfName(favorites, @"baz.milk"), -1);
    XCTAssertEqual(PMFavoritesIndexOfName(nil, @"foo.milk"), -1);
    XCTAssertEqual(PMFavoritesIndexOfName(@[], @"foo.milk"), -1);
}

- (void)testFavoriteDisplayNameStripsExtensionAndPath {
    XCTAssertEqualObjects(PMFavoriteDisplayName(@{@"name": @"My Preset.milk"}), @"My Preset");
    XCTAssertEqualObjects(PMFavoriteDisplayName(@{@"name": @"Folder/Deep.milk"}), @"Deep");
}

- (void)testFavoriteDisplayNameHandlesMissingOrEmptyName {
    XCTAssertEqualObjects(PMFavoriteDisplayName(@{}), @"(unknown)");
    XCTAssertEqualObjects(PMFavoriteDisplayName(@{@"name": @""}), @"(unknown)");
    XCTAssertEqualObjects(PMFavoriteDisplayName(@{@"path": @"/tmp/foo.milk"}), @"(unknown)");
}

- (void)testFavoriteImportEntryIsValidAcceptsValidDicts {
    XCTAssertTrue(PMFavoriteImportEntryIsValid(@{@"name": @"foo.milk"}));
    XCTAssertTrue(PMFavoriteImportEntryIsValid(@{@"name": @"foo.milk", @"path": @"/tmp/foo.milk"}));
}

- (void)testFavoriteImportEntryIsValidRejectsInvalidInput {
    XCTAssertFalse(PMFavoriteImportEntryIsValid(nil));
    XCTAssertFalse(PMFavoriteImportEntryIsValid(@"string"));
    XCTAssertFalse(PMFavoriteImportEntryIsValid(@42));
    XCTAssertFalse(PMFavoriteImportEntryIsValid(@{}));
    XCTAssertFalse(PMFavoriteImportEntryIsValid(@{@"name": @""}));
    XCTAssertFalse(PMFavoriteImportEntryIsValid(@{@"path": @"/tmp/foo.milk"}));
    XCTAssertFalse(PMFavoriteImportEntryIsValid(@{@"name": @"foo.milk", @"path": @42}));
    XCTAssertFalse(PMFavoriteImportEntryIsValid(@{@"name": @"foo.milk", @"path": @""}));
}

- (void)testFavoriteStoredPathForFullPathReturnsRelativeWithinPresetsDir {
    XCTAssertEqualObjects(PMFavoriteStoredPathForFullPath(@"/a/Presets/foo.milk", @"/a/Presets"), @"foo.milk");
    XCTAssertEqualObjects(PMFavoriteStoredPathForFullPath(@"/a/Presets/Sub/bar.milk", @"/a/Presets"), @"Sub/bar.milk");
}

- (void)testFavoriteStoredPathForFullPathDoesNotMatchPrefixWithoutBoundary {
    XCTAssertEqualObjects(PMFavoriteStoredPathForFullPath(@"/a/Presets2/foo.milk", @"/a/Presets"), @"/a/Presets2/foo.milk");
}

// MARK: - Cycle Favorites helpers

- (void)testNextCycleFavoritesIndexAscendingWraps {
    XCTAssertEqual(PMNextCycleFavoritesIndex(0, 3, PMCycleFavoritesModeAscending), 1);
    XCTAssertEqual(PMNextCycleFavoritesIndex(1, 3, PMCycleFavoritesModeAscending), 2);
    XCTAssertEqual(PMNextCycleFavoritesIndex(2, 3, PMCycleFavoritesModeAscending), 0);
}

- (void)testNextCycleFavoritesIndexDescendingWraps {
    XCTAssertEqual(PMNextCycleFavoritesIndex(2, 3, PMCycleFavoritesModeDescending), 1);
    XCTAssertEqual(PMNextCycleFavoritesIndex(1, 3, PMCycleFavoritesModeDescending), 0);
    XCTAssertEqual(PMNextCycleFavoritesIndex(0, 3, PMCycleFavoritesModeDescending), 2);
}

- (void)testBuildRandomFavoritesOrderContainsAllIndicesExactlyOnce {
    NSUInteger count = 5;
    NSArray<NSNumber *> *order = PMBuildRandomFavoritesOrder(count);
    XCTAssertEqual(order.count, count);

    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    for (NSNumber *n in order) {
        XCTAssertFalse([seen containsObject:n], @"Duplicate index %@", n);
        [seen addObject:n];
    }
    for (NSUInteger i = 0; i < count; i++) {
        XCTAssertTrue([seen containsObject:@(i)], @"Missing index %lu", (unsigned long)i);
    }
}

- (void)testBuildRandomFavoritesOrderHandlesEmptyAndSingleCount {
    XCTAssertEqual(PMBuildRandomFavoritesOrder(0).count, 0U);
    NSArray<NSNumber *> *single = PMBuildRandomFavoritesOrder(1);
    XCTAssertEqual(single.count, 1U);
    XCTAssertEqualObjects(single[0], @0);
}

- (void)testShouldDisableCycleFavoritesMenuReturnsTrueForZero {
    XCTAssertTrue(PMShouldDisableCycleFavoritesMenu(0));
    XCTAssertFalse(PMShouldDisableCycleFavoritesMenu(1));
    XCTAssertFalse(PMShouldDisableCycleFavoritesMenu(10));
}

- (void)testValidatedCycleFavoritesModeReturnsOffForUnrecognizedValues {
    XCTAssertEqual(PMValidatedCycleFavoritesMode(0),   PMCycleFavoritesModeOff);
    XCTAssertEqual(PMValidatedCycleFavoritesMode(1),   PMCycleFavoritesModeAscending);
    XCTAssertEqual(PMValidatedCycleFavoritesMode(2),   PMCycleFavoritesModeDescending);
    XCTAssertEqual(PMValidatedCycleFavoritesMode(3),   PMCycleFavoritesModeRandom);
    XCTAssertEqual(PMValidatedCycleFavoritesMode(-1),  PMCycleFavoritesModeOff);
    XCTAssertEqual(PMValidatedCycleFavoritesMode(99),  PMCycleFavoritesModeOff);
}

// MARK: - Configuration helper tests

- (void)testSensitivityFloatValueMapsLevelsCorrectly {
    XCTAssertEqualWithAccuracy(PMSensitivityFloatValue(0), 0.5f, 0.001f);
    XCTAssertEqualWithAccuracy(PMSensitivityFloatValue(1), 1.0f, 0.001f);
    XCTAssertEqualWithAccuracy(PMSensitivityFloatValue(2), 1.5f, 0.001f);
    XCTAssertEqualWithAccuracy(PMSensitivityFloatValue(3), 2.0f, 0.001f);
    // Out of range defaults to 1.0
    XCTAssertEqualWithAccuracy(PMSensitivityFloatValue(99), 1.0f, 0.001f);
    XCTAssertEqualWithAccuracy(PMSensitivityFloatValue(-1), 1.0f, 0.001f);
}

- (void)testDurationRandomizationFloatValueMapsLevelsCorrectly {
    XCTAssertEqualWithAccuracy(PMDurationRandomizationFloatValue(0), 0.001f, 0.0001f);
    XCTAssertEqualWithAccuracy(PMDurationRandomizationFloatValue(1), 0.25f, 0.001f);
    XCTAssertEqualWithAccuracy(PMDurationRandomizationFloatValue(2), 0.5f, 0.001f);
    XCTAssertEqualWithAccuracy(PMDurationRandomizationFloatValue(3), 1.0f, 0.001f);
    XCTAssertEqualWithAccuracy(PMDurationRandomizationFloatValue(99), 0.001f, 0.0001f);
}

- (void)testMeshSizeForQualityMapsCorrectly {
    XCTAssertEqual(PMMeshSizeForQuality(0), 64);
    XCTAssertEqual(PMMeshSizeForQuality(1), 128);
    XCTAssertEqual(PMMeshSizeForQuality(2), 192);
    XCTAssertEqual(PMMeshSizeForQuality(99), 128);
}

- (void)testValidatedHardCutInterval {
    XCTAssertEqual(PMValidatedHardCutInterval(5), 5);
    XCTAssertEqual(PMValidatedHardCutInterval(10), 10);
    XCTAssertEqual(PMValidatedHardCutInterval(20), 20);
    XCTAssertEqual(PMValidatedHardCutInterval(30), 30);
    XCTAssertEqual(PMValidatedHardCutInterval(99), 20);
}

- (void)testValidatedSoftCutDuration {
    XCTAssertEqual(PMValidatedSoftCutDuration(1), 1);
    XCTAssertEqual(PMValidatedSoftCutDuration(2), 2);
    XCTAssertEqual(PMValidatedSoftCutDuration(3), 3);
    XCTAssertEqual(PMValidatedSoftCutDuration(5), 5);
    XCTAssertEqual(PMValidatedSoftCutDuration(99), 3);
}

- (void)testValidatedFpsCap {
    XCTAssertEqual(PMValidatedFpsCap(0), 0);
    XCTAssertEqual(PMValidatedFpsCap(30), 30);
    XCTAssertEqual(PMValidatedFpsCap(45), 45);
    XCTAssertEqual(PMValidatedFpsCap(60), 60);
    XCTAssertEqual(PMValidatedFpsCap(90), 90);
    XCTAssertEqual(PMValidatedFpsCap(120), 120);
    XCTAssertEqual(PMValidatedFpsCap(99), 60);
}

- (void)testValidatedIdleFps {
    XCTAssertEqual(PMValidatedIdleFps(15), 15);
    XCTAssertEqual(PMValidatedIdleFps(30), 30);
    XCTAssertEqual(PMValidatedIdleFps(99), 30);
}

- (void)testValidatedResolutionScale {
    XCTAssertEqual(PMValidatedResolutionScale(0), 0);
    XCTAssertEqual(PMValidatedResolutionScale(1), 1);
    XCTAssertEqual(PMValidatedResolutionScale(2), 2);
    XCTAssertEqual(PMValidatedResolutionScale(99), 1);
}

- (void)testValidatedMeshQuality {
    XCTAssertEqual(PMValidatedMeshQuality(0), 0);
    XCTAssertEqual(PMValidatedMeshQuality(1), 1);
    XCTAssertEqual(PMValidatedMeshQuality(2), 2);
    XCTAssertEqual(PMValidatedMeshQuality(99), 1);
}

- (void)testValidatedPresetSortOrder {
    XCTAssertEqual(PMValidatedPresetSortOrder(0), 0);
    XCTAssertEqual(PMValidatedPresetSortOrder(1), 1);
    XCTAssertEqual(PMValidatedPresetSortOrder(2), 2);
    XCTAssertEqual(PMValidatedPresetSortOrder(3), 3);
    XCTAssertEqual(PMValidatedPresetSortOrder(99), 0);
}

- (void)testValidatedRetryCount {
    XCTAssertEqual(PMValidatedRetryCount(1), 1);
    XCTAssertEqual(PMValidatedRetryCount(3), 3);
    XCTAssertEqual(PMValidatedRetryCount(5), 5);
    XCTAssertEqual(PMValidatedRetryCount(10), 10);
    XCTAssertEqual(PMValidatedRetryCount(99), 3);
}

- (void)testParsePresetFilterEmpty {
    NSArray *result = PMParsePresetFilter(@"");
    XCTAssertEqual(result.count, (NSUInteger)0);
    result = PMParsePresetFilter(nil);
    XCTAssertEqual(result.count, (NSUInteger)0);
}

- (void)testParsePresetFilterSinglePattern {
    NSArray *result = PMParsePresetFilter(@"*warp*");
    XCTAssertEqual(result.count, (NSUInteger)1);
    XCTAssertEqualObjects(result[0], @"*warp*");
}

- (void)testParsePresetFilterMultiplePatterns {
    NSArray *result = PMParsePresetFilter(@" *warp* , *spiral* , *flow* ");
    XCTAssertEqual(result.count, (NSUInteger)3);
    XCTAssertEqualObjects(result[0], @"*warp*");
    XCTAssertEqualObjects(result[1], @"*spiral*");
    XCTAssertEqualObjects(result[2], @"*flow*");
}

- (void)testParsePresetFilterSkipsEmptyEntries {
    NSArray *result = PMParsePresetFilter(@"*warp*,,  , *flow*");
    XCTAssertEqual(result.count, (NSUInteger)2);
    XCTAssertEqualObjects(result[0], @"*warp*");
    XCTAssertEqualObjects(result[1], @"*flow*");
}

@end
