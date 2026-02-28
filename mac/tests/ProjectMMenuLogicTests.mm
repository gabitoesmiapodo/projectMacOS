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

- (void)testContextMenuPlacesPreviousBeforeNext {
    NSString *testPath = @(__FILE__);
    NSString *macDir = [[testPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *menuPath = [macDir stringByAppendingPathComponent:@"ProjectMView+Menu.mm"];

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:menuPath encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNotNil(content);
    XCTAssertNil(error);

    NSRange prevRange = [content rangeOfString:@"addItemWithTitle:@\"Previous\""];
    NSRange nextRange = [content rangeOfString:@"addItemWithTitle:@\"Next\""];
    XCTAssertNotEqual(prevRange.location, NSNotFound);
    XCTAssertNotEqual(nextRange.location, NSNotFound);
    XCTAssertLessThan(prevRange.location, nextRange.location);
}

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

@end
