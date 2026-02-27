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

- (void)testShouldLockPresetWhenPausedOrShuffleDisabled {
    XCTAssertTrue(PMShouldLockPreset(NO, NO));
    XCTAssertFalse(PMShouldLockPreset(YES, NO));
    XCTAssertTrue(PMShouldLockPreset(YES, YES));
}

- (void)testRemainingShuffleDurationUsesConfiguredElapsedAndMinimumFloor {
    XCTAssertEqualWithAccuracy(PMRemainingShuffleDurationSeconds(20.0, 4.5), 15.5, 0.0001);
    XCTAssertEqualWithAccuracy(PMRemainingShuffleDurationSeconds(20.0, 25.0), 0.05, 0.0001);
}

- (void)testShouldScheduleShuffleResumeOnlyWhenResumingWithProgress {
    XCTAssertTrue(PMShouldScheduleShuffleResume(NO, YES, YES));
    XCTAssertFalse(PMShouldScheduleShuffleResume(YES, YES, YES));
    XCTAssertFalse(PMShouldScheduleShuffleResume(NO, NO, YES));
    XCTAssertFalse(PMShouldScheduleShuffleResume(NO, YES, NO));
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

@end
