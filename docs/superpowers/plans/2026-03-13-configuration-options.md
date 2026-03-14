# Configuration Options Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 18 user-facing configuration options to the foobar2000 preferences panel, organized into 5 sections, with live propagation to the running visualization.

**Architecture:** cfg_ variable infrastructure in ProjectMRegistration.mm, atomic generation counter for change propagation, preferences panel rebuilt programmatically with NSScrollView + NSStackView, settings applied in renderFrame via applySettingsFromPreferences. Pure helper functions in ProjectMMenuLogic for testable mapping logic. FBO pipeline for half-resolution mode, mouse event handlers for projectm_touch interaction.

**Tech Stack:** foobar2000 cfg_* system, projectM 4.1.6 C API, NSOpenGLView, CVDisplayLink, OpenGL FBO/glBlitFramebuffer, Objective-C++, XCTest

**Spec:** `docs/superpowers/specs/2026-03-13-configuration-options-design.md`

---

**Note on line numbers:** Line numbers reference files as they exist at commit `6929a7d` (before any modifications). As tasks are implemented sequentially, line numbers shift. Match by code content, not line number.

---

### Task 1: cfg_ infrastructure (GUIDs, externs, generation counter)

**Files:**
- Modify: `mac/ProjectMRegistration.mm:17-29` (add 17 new GUIDs + cfg_ definitions, g_settingsGeneration atomic, PMSettingsDidChange helper)
- Modify: `mac/ProjectMView.h:9-14` (add 17 new extern declarations, _isAutoPaused ivar, FBO ivars)

- [ ] **Step 1: Add 17 new GUID + cfg_ definitions to ProjectMRegistration.mm**

After line 22 (the existing `guid_cfg_debug_logging` GUID), add:

```objc
// Performance
static const GUID guid_cfg_fps_cap               = { 0x7a1b3c5d, 0xe2f4, 0x4a68, { 0x91, 0xb3, 0xc5, 0xd7, 0xe9, 0xf1, 0x23, 0x45 } };
static const GUID guid_cfg_idle_fps              = { 0x8b2c4d6e, 0xf3a5, 0x4b79, { 0xa2, 0xc4, 0xd6, 0xe8, 0xfa, 0x12, 0x34, 0x56 } };
static const GUID guid_cfg_resolution_scale      = { 0x9c3d5e7f, 0xa4b6, 0x4c8a, { 0xb3, 0xd5, 0xe7, 0xf9, 0x1b, 0x23, 0x45, 0x67 } };
static const GUID guid_cfg_vsync                 = { 0xad4e6f80, 0xb5c7, 0x4d9b, { 0xc4, 0xe6, 0xf8, 0x0a, 0x2c, 0x34, 0x56, 0x78 } };
static const GUID guid_cfg_mesh_quality          = { 0xbe5f7091, 0xc6d8, 0x4eac, { 0xd5, 0xf7, 0x09, 0x1b, 0x3d, 0x45, 0x67, 0x89 } };
static const GUID guid_cfg_auto_pause            = { 0xcf608102, 0xd7e9, 0x4fbd, { 0xe6, 0x08, 0x1a, 0x2c, 0x4e, 0x56, 0x78, 0x9a } };
// Transitions
static const GUID guid_cfg_soft_cut_duration     = { 0xd0719213, 0xe8fa, 0x40ce, { 0xf7, 0x19, 0x2b, 0x3d, 0x5f, 0x67, 0x89, 0xab } };
static const GUID guid_cfg_hard_cuts             = { 0xe1820324, 0xf90b, 0x41df, { 0x08, 0x2a, 0x3c, 0x4e, 0x60, 0x78, 0x9a, 0xbc } };
static const GUID guid_cfg_hard_cut_sensitivity  = { 0xf2931435, 0x0a1c, 0x42e0, { 0x19, 0x3b, 0x4d, 0x5f, 0x71, 0x89, 0xab, 0xcd } };
static const GUID guid_cfg_hard_cut_interval     = { 0x03a42546, 0x1b2d, 0x43f1, { 0x2a, 0x4c, 0x5e, 0x60, 0x82, 0x9a, 0xbc, 0xde } };
static const GUID guid_cfg_duration_randomization = { 0x14b53657, 0x2c3e, 0x4402, { 0x3b, 0x5d, 0x6f, 0x71, 0x93, 0xab, 0xcd, 0xef } };
// Visualization
static const GUID guid_cfg_beat_sensitivity      = { 0x25c64768, 0x3d4f, 0x4513, { 0x4c, 0x6e, 0x70, 0x82, 0xa4, 0xbc, 0xde, 0xf0 } };
static const GUID guid_cfg_aspect_correction     = { 0x36d75879, 0x4e50, 0x4624, { 0x5d, 0x7f, 0x81, 0x93, 0xb5, 0xcd, 0xef, 0x01 } };
static const GUID guid_cfg_mouse_interaction     = { 0x47e8698a, 0x5f61, 0x4735, { 0x6e, 0x80, 0x92, 0xa4, 0xc6, 0xde, 0xf0, 0x12 } };
static const GUID guid_cfg_mouse_effect          = { 0x58f97a9b, 0x6072, 0x4846, { 0x7f, 0x91, 0xa3, 0xb5, 0xd7, 0xef, 0x01, 0x23 } };
// Presets
static const GUID guid_cfg_custom_presets_folder = { 0x690a8bac, 0x7183, 0x4957, { 0x80, 0xa2, 0xb4, 0xc6, 0xe8, 0xf0, 0x12, 0x34 } };
static const GUID guid_cfg_preset_sort_order     = { 0x7a1b9cbd, 0x8294, 0x4a68, { 0x91, 0xb3, 0xc5, 0xd7, 0xf9, 0x01, 0x23, 0x45 } };
static const GUID guid_cfg_preset_filter         = { 0x8b2cadce, 0x93a5, 0x4b79, { 0xa2, 0xc4, 0xd6, 0xe8, 0x0a, 0x12, 0x34, 0x56 } };
static const GUID guid_cfg_preset_retry_count    = { 0x9c3dbedf, 0xa4b6, 0x4c8a, { 0xb3, 0xd5, 0xe7, 0xf9, 0x1b, 0x23, 0x45, 0x67 } };
```

After line 29 (the existing `cfg_debug_logging` definition), add:

```objc
// Performance
cfg_int cfg_fps_cap(guid_cfg_fps_cap, 60);
cfg_int cfg_idle_fps(guid_cfg_idle_fps, 30);
cfg_int cfg_resolution_scale(guid_cfg_resolution_scale, 1);
cfg_bool cfg_vsync(guid_cfg_vsync, true);
cfg_int cfg_mesh_quality(guid_cfg_mesh_quality, 1);
cfg_bool cfg_auto_pause(guid_cfg_auto_pause, false);
// Transitions
cfg_int cfg_soft_cut_duration(guid_cfg_soft_cut_duration, 3);
cfg_bool cfg_hard_cuts(guid_cfg_hard_cuts, false);
cfg_int cfg_hard_cut_sensitivity(guid_cfg_hard_cut_sensitivity, 1);
cfg_int cfg_hard_cut_interval(guid_cfg_hard_cut_interval, 20);
cfg_int cfg_duration_randomization(guid_cfg_duration_randomization, 0);
// Visualization
cfg_int cfg_beat_sensitivity(guid_cfg_beat_sensitivity, 1);
cfg_bool cfg_aspect_correction(guid_cfg_aspect_correction, true);
cfg_bool cfg_mouse_interaction(guid_cfg_mouse_interaction, false);
cfg_int cfg_mouse_effect(guid_cfg_mouse_effect, 0);
// Presets
cfg_string cfg_custom_presets_folder(guid_cfg_custom_presets_folder, "");
cfg_int cfg_preset_sort_order(guid_cfg_preset_sort_order, 0);
cfg_string cfg_preset_filter(guid_cfg_preset_filter, "");
cfg_int cfg_preset_retry_count(guid_cfg_preset_retry_count, 3);
```

- [ ] **Step 2: Add g_settingsGeneration atomic and PMSettingsDidChange helper**

In `mac/ProjectMRegistration.mm`, after the `g_musicPlaybackActive` atomic (line 35), add:

```objc
std::atomic<uint32_t> g_settingsGeneration(0);
```

After `PMSyncMusicPlaybackState` function (line 98), add:

```objc
void PMSettingsDidChange(void) {
    g_settingsGeneration.fetch_add(1, std::memory_order_relaxed);
}
```

- [ ] **Step 3: Add extern declarations to ProjectMView.h**

In `mac/ProjectMView.h`, after the existing externs (line 14), add:

```objc
// Performance
extern cfg_int cfg_fps_cap;
extern cfg_int cfg_idle_fps;
extern cfg_int cfg_resolution_scale;
extern cfg_bool cfg_vsync;
extern cfg_int cfg_mesh_quality;
extern cfg_bool cfg_auto_pause;
// Transitions
extern cfg_int cfg_soft_cut_duration;
extern cfg_bool cfg_hard_cuts;
extern cfg_int cfg_hard_cut_sensitivity;
extern cfg_int cfg_hard_cut_interval;
extern cfg_int cfg_duration_randomization;
// Visualization
extern cfg_int cfg_beat_sensitivity;
extern cfg_bool cfg_aspect_correction;
extern cfg_bool cfg_mouse_interaction;
extern cfg_int cfg_mouse_effect;
// Presets
extern cfg_string cfg_custom_presets_folder;
extern cfg_int cfg_preset_sort_order;
extern cfg_string cfg_preset_filter;
extern cfg_int cfg_preset_retry_count;

extern std::atomic<uint32_t> g_settingsGeneration;
void PMSettingsDidChange(void);
```

Add to the ivar block (after `_fpsFrameCount` at line 59):

```objc
    BOOL _isAutoPaused;
    uint32_t _lastSettingsGeneration;
    // FBO for half-resolution mode
    GLuint _halfResFBO;
    GLuint _halfResColorRB;
    GLuint _halfResDepthRB;
    int _halfResWidth;
    int _halfResHeight;
    int _cachedResolutionScale;
    int _cachedFpsCap;
    int _cachedIdleFps;
    int _cachedMeshQuality;
    pfc::string8 _lastCustomFolder;
    int _lastSortOrder;
    pfc::string8 _lastFilter;
```

Add method declarations after `getDrawableSizeWidth:height:`:

```objc
/// Apply all cfg_ settings to projectM state.
- (void)applySettingsFromPreferences;
/// Set up or tear down the half-resolution FBO.
- (void)setupHalfResFBO:(int)fullWidth height:(int)fullHeight;
- (void)teardownHalfResFBO;
```

- [ ] **Step 4: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. No behavior changes yet -- all new cfg_ variables use defaults that match current hardcoded values.

- [ ] **Step 5: Commit**

```
feat: add cfg_ infrastructure for 17 new configuration options
```

---

### Task 2: Pure helper functions + tests

**Files:**
- Modify: `mac/ProjectMMenuLogic.h` (add new function declarations)
- Modify: `mac/ProjectMMenuLogic.mm` (add new function implementations)
- Modify: `mac/tests/ProjectMMenuLogicTests.mm` (add tests)

- [ ] **Step 1: Add helper function declarations to ProjectMMenuLogic.h**

At the end of the file, before the closing include guard or final line, add:

```objc
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

/// Map retry count cfg_int. Valid: 1, 3, 5, 10. Default: 3.
FOUNDATION_EXPORT int PMValidatedRetryCount(int requested);

/// Parse comma-separated filter string into array of trimmed non-empty strings.
FOUNDATION_EXPORT NSArray<NSString *> *PMParsePresetFilter(NSString *filterString);
```

- [ ] **Step 2: Write failing tests**

In `mac/tests/ProjectMMenuLogicTests.mm`, add at the end before `@end`:

```objc
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bash scripts/run-tests.sh`
Expected: FAIL -- functions not defined.

- [ ] **Step 4: Implement helper functions in ProjectMMenuLogic.mm**

At the end of `mac/ProjectMMenuLogic.mm`, add:

```objc
float PMSensitivityFloatValue(int level) {
    switch (level) {
        case 0: return 0.5f;
        case 1: return 1.0f;
        case 2: return 1.5f;
        case 3: return 2.0f;
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

int PMValidatedHardCutInterval(int requested) {
    static const int valid[] = {5, 10, 20, 30};
    for (int i = 0; i < 4; i++) {
        if (valid[i] == requested) return requested;
    }
    return 20;
}

int PMValidatedSoftCutDuration(int requested) {
    static const int valid[] = {1, 2, 3, 5};
    for (int i = 0; i < 4; i++) {
        if (valid[i] == requested) return requested;
    }
    return 3;
}

int PMValidatedFpsCap(int requested) {
    static const int valid[] = {0, 30, 45, 60, 90, 120};
    for (int i = 0; i < 6; i++) {
        if (valid[i] == requested) return requested;
    }
    return 60;
}

int PMValidatedIdleFps(int requested) {
    static const int valid[] = {15, 30};
    for (int i = 0; i < 2; i++) {
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
    if (requested >= 0 && requested <= 3) return requested;
    return 0;
}

int PMValidatedRetryCount(int requested) {
    static const int valid[] = {1, 3, 5, 10};
    for (int i = 0; i < 4; i++) {
        if (valid[i] == requested) return requested;
    }
    return 3;
}

NSArray<NSString *> *PMParsePresetFilter(NSString *filterString) {
    if (filterString.length == 0) return @[];
    NSArray<NSString *> *components = [filterString componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *component in components) {
        NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [result addObject:trimmed];
        }
    }
    return [result copy];
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh`
Expected: All tests PASS.

- [ ] **Step 6: Build and deploy**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, all tests pass.

- [ ] **Step 7: Commit**

```
feat: add pure helper functions for configuration option validation
```

---

### Task 3: Preferences panel UI

**Files:**
- Modify: `mac/ProjectMPreferences.mm` (complete rewrite with NSScrollView + NSStackView, 5 sections, 18 controls)

- [ ] **Step 1: Rewrite ProjectMPreferences.mm with full preferences panel**

Replace the entire content of `mac/ProjectMPreferences.mm` with the new implementation. The preferences page uses:

- `NSScrollView` wrapping an `NSStackView` (vertical, top alignment)
- Section headers as bold `NSTextField` labels
- Each setting row: label + control + help text below
- Popup buttons for enum values, checkboxes for booleans, text fields for strings
- "Browse..." button with NSOpenPanel for custom presets folder
- Dependent controls (hard cut sensitivity/interval, mouse effect) disabled when parent checkbox is off
- All controls call PMSettingsDidChange() on value change

```objc
#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"

#import <atomic>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Flipped view to anchor content to top of scroll view
@interface PMFlippedView : NSView
@end

@implementation PMFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface ProjectMPreferencesViewController : NSViewController
@end

@implementation ProjectMPreferencesViewController {
    // Performance
    NSPopUpButton *_fpsCapPopup;
    NSPopUpButton *_idleFpsPopup;
    NSPopUpButton *_resolutionScalePopup;
    NSPopUpButton *_meshQualityPopup;
    NSButton *_vsyncCheckbox;
    NSButton *_autoPauseCheckbox;
    // Transitions
    NSPopUpButton *_softCutDurationPopup;
    NSButton *_hardCutsCheckbox;
    NSPopUpButton *_hardCutSensitivityPopup;
    NSPopUpButton *_hardCutIntervalPopup;
    NSPopUpButton *_durationRandomizationPopup;
    // Visualization
    NSPopUpButton *_beatSensitivityPopup;
    NSButton *_aspectCorrectionCheckbox;
    NSButton *_mouseInteractionCheckbox;
    NSPopUpButton *_mouseEffectPopup;
    // Presets
    NSTextField *_customPresetsFolderField;
    NSPopUpButton *_sortOrderPopup;
    NSTextField *_presetFilterField;
    NSPopUpButton *_retryCountPopup;
    // Diagnostics
    NSButton *_debugLoggingCheckbox;
}

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:container.bounds];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.drawsBackground = NO;

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(12, 16, 12, 16);

    // --- Performance ---
    [stack addArrangedSubview:[self sectionHeaderWithTitle:@"Performance"]];

    _fpsCapPopup = [self popupWithTitles:@[@"Unlimited", @"30", @"45", @"60", @"90", @"120"]
                                  values:@[@0, @30, @45, @60, @90, @120]
                            currentValue:(int)cfg_fps_cap
                                  action:@selector(fpsCapChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"FPS Cap:" control:_fpsCapPopup]];
    [stack addArrangedSubview:[self helpText:@"Maximum frame rate during music playback. Lower values reduce CPU usage."]];

    _idleFpsPopup = [self popupWithTitles:@[@"15", @"30"]
                                   values:@[@15, @30]
                             currentValue:(int)cfg_idle_fps
                                   action:@selector(idleFpsChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Idle FPS:" control:_idleFpsPopup]];
    [stack addArrangedSubview:[self helpText:@"Frame rate when no music is playing. Presets still animate but don't react to sound."]];

    _resolutionScalePopup = [self popupWithTitles:@[@"Half", @"Standard", @"Retina"]
                                           values:@[@0, @1, @2]
                                     currentValue:(int)cfg_resolution_scale
                                           action:@selector(resolutionScaleChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Resolution:" control:_resolutionScalePopup]];
    [stack addArrangedSubview:[self helpText:@"Rendering resolution relative to window size. Half uses less GPU power. Retina renders at native pixel density on high-DPI displays."]];

    _meshQualityPopup = [self popupWithTitles:@[@"Low", @"Medium", @"High"]
                                       values:@[@0, @1, @2]
                                 currentValue:(int)cfg_mesh_quality
                                       action:@selector(meshQualityChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Mesh Quality:" control:_meshQualityPopup]];
    [stack addArrangedSubview:[self helpText:@"Detail level of the warp mesh. Higher values produce smoother distortion effects but use more GPU."]];

    _vsyncCheckbox = [NSButton checkboxWithTitle:@"Vsync" target:self action:@selector(vsyncChanged:)];
    _vsyncCheckbox.state = cfg_vsync ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_vsyncCheckbox];
    [stack addArrangedSubview:[self helpText:@"Synchronize frame output with display refresh. Disable for lower latency at the cost of possible tearing."]];

    _autoPauseCheckbox = [NSButton checkboxWithTitle:@"Auto-pause" target:self action:@selector(autoPauseChanged:)];
    _autoPauseCheckbox.state = cfg_auto_pause ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_autoPauseCheckbox];
    [stack addArrangedSubview:[self helpText:@"Automatically pause the visualization when music is not playing. Reduces CPU usage to near zero."]];

    [stack addArrangedSubview:[self spacer]];

    // --- Transitions ---
    [stack addArrangedSubview:[self sectionHeaderWithTitle:@"Transitions"]];

    _softCutDurationPopup = [self popupWithTitles:@[@"1s", @"2s", @"3s", @"5s"]
                                           values:@[@1, @2, @3, @5]
                                     currentValue:(int)cfg_soft_cut_duration
                                           action:@selector(softCutDurationChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Soft Cut Duration:" control:_softCutDurationPopup]];
    [stack addArrangedSubview:[self helpText:@"Cross-fade time when transitioning between presets."]];

    _hardCutsCheckbox = [NSButton checkboxWithTitle:@"Hard Cuts" target:self action:@selector(hardCutsChanged:)];
    _hardCutsCheckbox.state = cfg_hard_cuts ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_hardCutsCheckbox];
    [stack addArrangedSubview:[self helpText:@"Allow instant beat-triggered transitions instead of always cross-fading."]];

    _hardCutSensitivityPopup = [self popupWithTitles:@[@"Low", @"Medium", @"High", @"Max"]
                                              values:@[@0, @1, @2, @3]
                                        currentValue:(int)cfg_hard_cut_sensitivity
                                              action:@selector(hardCutSensitivityChanged:)];
    _hardCutSensitivityPopup.enabled = cfg_hard_cuts;
    [stack addArrangedSubview:[self rowWithLabel:@"Hard Cut Sensitivity:" control:_hardCutSensitivityPopup]];
    [stack addArrangedSubview:[self helpText:@"How strong a beat must be to trigger a hard cut. Only applies when hard cuts are enabled."]];

    _hardCutIntervalPopup = [self popupWithTitles:@[@"5s", @"10s", @"20s", @"30s"]
                                           values:@[@5, @10, @20, @30]
                                     currentValue:(int)cfg_hard_cut_interval
                                           action:@selector(hardCutIntervalChanged:)];
    _hardCutIntervalPopup.enabled = cfg_hard_cuts;
    [stack addArrangedSubview:[self rowWithLabel:@"Hard Cut Min Interval:" control:_hardCutIntervalPopup]];
    [stack addArrangedSubview:[self helpText:@"Minimum time between hard cuts to prevent rapid flickering."]];

    _durationRandomizationPopup = [self popupWithTitles:@[@"None", @"Low", @"Medium", @"High"]
                                                 values:@[@0, @1, @2, @3]
                                           currentValue:(int)cfg_duration_randomization
                                                 action:@selector(durationRandomizationChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Duration Randomization:" control:_durationRandomizationPopup]];
    [stack addArrangedSubview:[self helpText:@"Add variation to preset switch timing. At None, presets switch at exactly the configured delay."]];

    [stack addArrangedSubview:[self spacer]];

    // --- Visualization ---
    [stack addArrangedSubview:[self sectionHeaderWithTitle:@"Visualization"]];

    _beatSensitivityPopup = [self popupWithTitles:@[@"Low", @"Medium", @"High", @"Max"]
                                           values:@[@0, @1, @2, @3]
                                     currentValue:(int)cfg_beat_sensitivity
                                           action:@selector(beatSensitivityChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Beat Sensitivity:" control:_beatSensitivityPopup]];
    [stack addArrangedSubview:[self helpText:@"How strongly the visualization reacts to beats in the music."]];

    _aspectCorrectionCheckbox = [NSButton checkboxWithTitle:@"Aspect Correction" target:self action:@selector(aspectCorrectionChanged:)];
    _aspectCorrectionCheckbox.state = cfg_aspect_correction ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_aspectCorrectionCheckbox];
    [stack addArrangedSubview:[self helpText:@"Preserve preset aspect ratio. When off, presets stretch to fill the window."]];

    _mouseInteractionCheckbox = [NSButton checkboxWithTitle:@"Mouse Interaction" target:self action:@selector(mouseInteractionChanged:)];
    _mouseInteractionCheckbox.state = cfg_mouse_interaction ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_mouseInteractionCheckbox];
    [stack addArrangedSubview:[self helpText:@"Click or drag on the visualization to create visual effects."]];

    _mouseEffectPopup = [self popupWithTitles:@[@"Random", @"Circle", @"Radial Blob", @"Line", @"Double Line"]
                                       values:@[@0, @1, @2, @7, @8]
                                 currentValue:(int)cfg_mouse_effect
                                       action:@selector(mouseEffectChanged:)];
    _mouseEffectPopup.enabled = cfg_mouse_interaction;
    [stack addArrangedSubview:[self rowWithLabel:@"Mouse Effect:" control:_mouseEffectPopup]];
    [stack addArrangedSubview:[self helpText:@"Type of visual effect created by mouse interaction. Only applies when mouse interaction is enabled."]];

    [stack addArrangedSubview:[self spacer]];

    // --- Presets ---
    [stack addArrangedSubview:[self sectionHeaderWithTitle:@"Presets"]];

    NSStackView *folderRow = [NSStackView stackViewWithViews:@[]];
    folderRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    folderRow.spacing = 6;
    NSTextField *folderLabel = [NSTextField labelWithString:@"Presets Folder:"];
    folderLabel.font = [NSFont systemFontOfSize:13];
    _customPresetsFolderField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 22)];
    _customPresetsFolderField.stringValue = @(cfg_custom_presets_folder.get().get_ptr());
    _customPresetsFolderField.placeholderString = @"Default (built-in collection)";
    _customPresetsFolderField.delegate = (id<NSTextFieldDelegate>)self;
    _customPresetsFolderField.target = self;
    _customPresetsFolderField.action = @selector(customPresetsFolderChanged:);
    NSButton *browseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browsePresetsFolder:)];
    [folderRow addArrangedSubview:folderLabel];
    [folderRow addArrangedSubview:_customPresetsFolderField];
    [folderRow addArrangedSubview:browseButton];
    [NSLayoutConstraint activateConstraints:@[
        [_customPresetsFolderField.widthAnchor constraintGreaterThanOrEqualToConstant:180],
    ]];
    [stack addArrangedSubview:folderRow];
    [stack addArrangedSubview:[self helpText:@"Override the default preset source with a folder of .milk files. Leave empty to use the built-in collection."]];

    _sortOrderPopup = [self popupWithTitles:@[@"Name A-Z", @"Name Z-A", @"Path A-Z", @"Path Z-A"]
                                     values:@[@0, @1, @2, @3]
                               currentValue:(int)cfg_preset_sort_order
                                     action:@selector(sortOrderChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Sort Order:" control:_sortOrderPopup]];
    [stack addArrangedSubview:[self helpText:@"Order of presets in the browser menu and initial playlist."]];

    NSStackView *filterRow = [NSStackView stackViewWithViews:@[]];
    filterRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    filterRow.spacing = 6;
    NSTextField *filterLabel = [NSTextField labelWithString:@"Filter:"];
    filterLabel.font = [NSFont systemFontOfSize:13];
    _presetFilterField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
    _presetFilterField.stringValue = @(cfg_preset_filter.get().get_ptr());
    _presetFilterField.placeholderString = @"e.g. *warp*, *spiral*";
    _presetFilterField.target = self;
    _presetFilterField.action = @selector(presetFilterChanged:);
    [filterRow addArrangedSubview:filterLabel];
    [filterRow addArrangedSubview:_presetFilterField];
    [NSLayoutConstraint activateConstraints:@[
        [_presetFilterField.widthAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];
    [stack addArrangedSubview:filterRow];
    [stack addArrangedSubview:[self helpText:@"Comma-separated glob patterns to include presets (e.g. *warp*, *spiral*). Leave empty to load all presets."]];

    _retryCountPopup = [self popupWithTitles:@[@"1", @"3", @"5", @"10"]
                                      values:@[@1, @3, @5, @10]
                                currentValue:(int)cfg_preset_retry_count
                                      action:@selector(retryCountChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Retry Count:" control:_retryCountPopup]];
    [stack addArrangedSubview:[self helpText:@"How many times to retry loading a broken preset before skipping it."]];

    [stack addArrangedSubview:[self spacer]];

    // --- Diagnostics ---
    [stack addArrangedSubview:[self sectionHeaderWithTitle:@"Diagnostics"]];

    _debugLoggingCheckbox = [NSButton checkboxWithTitle:@"Debug Logging" target:self action:@selector(debugLoggingChanged:)];
    _debugLoggingCheckbox.state = cfg_debug_logging ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_debugLoggingCheckbox];
    [stack addArrangedSubview:[self helpText:@"Log diagnostic messages to the foobar2000 console."]];

    // --- Set up scroll view ---
    NSView *documentView = [[PMFlippedView alloc] initWithFrame:NSZeroRect];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor],
    ]];

    scrollView.documentView = documentView;
    [NSLayoutConstraint activateConstraints:@[
        [documentView.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
    ]];

    [container addSubview:scrollView];
    self.view = container;
}

// MARK: - UI Helpers

- (NSTextField *)sectionHeaderWithTitle:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:14];
    return label;
}

- (NSTextField *)helpText:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    label.preferredMaxLayoutWidth = 340;
    return label;
}

- (NSView *)spacer {
    NSView *spacer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 8)];
    [spacer.heightAnchor constraintEqualToConstant:8].active = YES;
    return spacer;
}

- (NSStackView *)rowWithLabel:(NSString *)labelText control:(NSView *)control {
    NSTextField *label = [NSTextField labelWithString:labelText];
    label.font = [NSFont systemFontOfSize:13];
    label.alignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:150].active = YES;
    NSStackView *row = [NSStackView stackViewWithViews:@[label, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    return row;
}

- (NSPopUpButton *)popupWithTitles:(NSArray<NSString *> *)titles
                            values:(NSArray<NSNumber *> *)values
                      currentValue:(int)currentValue
                            action:(SEL)action {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 120, 25) pullsDown:NO];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [popup addItemWithTitle:titles[i]];
        popup.lastItem.tag = values[i].integerValue;
        if (values[i].intValue == currentValue) {
            [popup selectItem:popup.lastItem];
        }
    }
    popup.target = self;
    popup.action = action;
    return popup;
}

// MARK: - Actions (Performance)

- (void)fpsCapChanged:(id)sender {
    cfg_fps_cap = PMValidatedFpsCap((int)_fpsCapPopup.selectedItem.tag);
    PMSettingsDidChange();
}

- (void)idleFpsChanged:(id)sender {
    cfg_idle_fps = PMValidatedIdleFps((int)_idleFpsPopup.selectedItem.tag);
    PMSettingsDidChange();
}

- (void)resolutionScaleChanged:(id)sender {
    cfg_resolution_scale = PMValidatedResolutionScale((int)_resolutionScalePopup.selectedItem.tag);
    PMSettingsDidChange();
}

- (void)meshQualityChanged:(id)sender {
    cfg_mesh_quality = PMValidatedMeshQuality((int)_meshQualityPopup.selectedItem.tag);
    PMSettingsDidChange();
}

- (void)vsyncChanged:(id)sender {
    cfg_vsync = (_vsyncCheckbox.state == NSControlStateValueOn);
    PMSettingsDidChange();
}

- (void)autoPauseChanged:(id)sender {
    cfg_auto_pause = (_autoPauseCheckbox.state == NSControlStateValueOn);
    PMSettingsDidChange();
}

// MARK: - Actions (Transitions)

- (void)softCutDurationChanged:(id)sender {
    cfg_soft_cut_duration = PMValidatedSoftCutDuration((int)_softCutDurationPopup.selectedItem.tag);
    PMSettingsDidChange();
}

- (void)hardCutsChanged:(id)sender {
    cfg_hard_cuts = (_hardCutsCheckbox.state == NSControlStateValueOn);
    _hardCutSensitivityPopup.enabled = cfg_hard_cuts;
    _hardCutIntervalPopup.enabled = cfg_hard_cuts;
    PMSettingsDidChange();
}

- (void)hardCutSensitivityChanged:(id)sender {
    cfg_hard_cut_sensitivity = (int)_hardCutSensitivityPopup.selectedItem.tag;
    PMSettingsDidChange();
}

- (void)hardCutIntervalChanged:(id)sender {
    cfg_hard_cut_interval = PMValidatedHardCutInterval((int)_hardCutIntervalPopup.selectedItem.tag);
    PMSettingsDidChange();
}

- (void)durationRandomizationChanged:(id)sender {
    cfg_duration_randomization = (int)_durationRandomizationPopup.selectedItem.tag;
    PMSettingsDidChange();
}

// MARK: - Actions (Visualization)

- (void)beatSensitivityChanged:(id)sender {
    cfg_beat_sensitivity = (int)_beatSensitivityPopup.selectedItem.tag;
    PMSettingsDidChange();
}

- (void)aspectCorrectionChanged:(id)sender {
    cfg_aspect_correction = (_aspectCorrectionCheckbox.state == NSControlStateValueOn);
    PMSettingsDidChange();
}

- (void)mouseInteractionChanged:(id)sender {
    cfg_mouse_interaction = (_mouseInteractionCheckbox.state == NSControlStateValueOn);
    _mouseEffectPopup.enabled = cfg_mouse_interaction;
    PMSettingsDidChange();
}

- (void)mouseEffectChanged:(id)sender {
    cfg_mouse_effect = (int)_mouseEffectPopup.selectedItem.tag;
    PMSettingsDidChange();
}

// MARK: - Actions (Presets)

- (void)browsePresetsFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select a folder containing .milk preset files";
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *path = panel.URL.path;
    _customPresetsFolderField.stringValue = path ?: @"";
    cfg_custom_presets_folder = path ? [path UTF8String] : "";
    PMSettingsDidChange();
}

- (void)customPresetsFolderChanged:(id)sender {
    cfg_custom_presets_folder = [_customPresetsFolderField.stringValue UTF8String];
    PMSettingsDidChange();
}

- (void)sortOrderChanged:(id)sender {
    cfg_preset_sort_order = PMValidatedPresetSortOrder((int)_sortOrderPopup.selectedItem.tag);
    PMSettingsDidChange();
}

- (void)presetFilterChanged:(id)sender {
    cfg_preset_filter = [_presetFilterField.stringValue UTF8String];
    PMSettingsDidChange();
}

- (void)retryCountChanged:(id)sender {
    cfg_preset_retry_count = PMValidatedRetryCount((int)_retryCountPopup.selectedItem.tag);
    PMSettingsDidChange();
}

// MARK: - Actions (Diagnostics)

- (void)debugLoggingChanged:(id)sender {
    cfg_debug_logging = (_debugLoggingCheckbox.state == NSControlStateValueOn);
}

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_projectMacOS : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([ProjectMPreferencesViewController new]);
    }
    const char *get_name() override { return "projectMacOS"; }
    GUID get_guid() override {
        return { 0x2f8a5e17, 0x3c94, 0x4b61, { 0xa7, 0xd2, 0xe1, 0x9f, 0x0b, 0x84, 0xc5, 0x3a } };
    }
    GUID get_parent_guid() override { return guid_tools; }
};

FB2K_SERVICE_FACTORY(preferences_page_projectMacOS);

} // anonymous namespace
```

- [ ] **Step 2: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000: open Tools > projectMacOS in preferences. Verify all 5 sections render with correct controls, help text is visible, dependent controls dim correctly when parent checkbox is toggled.

- [ ] **Step 3: Commit**

```
feat: rebuild preferences panel with 18 configuration options
```

---

### Task 4: Settings propagation and simple projectM API calls

**Files:**
- Modify: `mac/ProjectMView.mm:176-289` (createProjectM: replace hardcoded values with cfg_ reads)
- Modify: `mac/ProjectMView.mm:291-412` (renderFrame: add generation counter check, call applySettingsFromPreferences)
- Modify: `mac/ProjectMView.mm` (add applySettingsFromPreferences method)

- [ ] **Step 1: Replace hardcoded values in createProjectM with cfg_ reads**

In `mac/ProjectMView.mm`, in `createProjectM:height:`, replace lines 228-236:

```objc
    projectm_set_mesh_size(_projectM, 128, (size_t)(128 * heightWidthRatio));
    projectm_set_fps(_projectM, 60);
    projectm_set_soft_cut_duration(_projectM, 3.0);
    projectm_set_preset_duration(_projectM, (double)cfg_preset_duration);
    projectm_set_hard_cut_enabled(_projectM, PMUseHardCutTransitions());
    projectm_set_hard_cut_duration(_projectM, 20.0);
    projectm_set_hard_cut_sensitivity(_projectM, 1.0f);
    projectm_set_beat_sensitivity(_projectM, 1.0f);
    projectm_set_aspect_correction(_projectM, true);
```

With:

```objc
    int meshSize = PMMeshSizeForQuality(PMValidatedMeshQuality((int)cfg_mesh_quality));
    projectm_set_mesh_size(_projectM, meshSize, (size_t)(meshSize * heightWidthRatio));
    int fpsCap = PMValidatedFpsCap((int)cfg_fps_cap);
    projectm_set_fps(_projectM, fpsCap > 0 ? fpsCap : 60);
    projectm_set_soft_cut_duration(_projectM, (double)PMValidatedSoftCutDuration((int)cfg_soft_cut_duration));
    projectm_set_preset_duration(_projectM, (double)cfg_preset_duration);
    projectm_set_hard_cut_enabled(_projectM, (bool)cfg_hard_cuts);
    projectm_set_hard_cut_duration(_projectM, (double)PMValidatedHardCutInterval((int)cfg_hard_cut_interval));
    projectm_set_hard_cut_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_hard_cut_sensitivity));
    projectm_set_beat_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_beat_sensitivity));
    projectm_set_aspect_correction(_projectM, (bool)cfg_aspect_correction);
    projectm_set_easter_egg(_projectM, PMDurationRandomizationFloatValue((int)cfg_duration_randomization));

    _cachedFpsCap = fpsCap;
    _cachedIdleFps = PMValidatedIdleFps((int)cfg_idle_fps);
    _cachedMeshQuality = PMValidatedMeshQuality((int)cfg_mesh_quality);
    _cachedResolutionScale = PMValidatedResolutionScale((int)cfg_resolution_scale);
    _lastSettingsGeneration = g_settingsGeneration.load(std::memory_order_relaxed);
    _lastCustomFolder = cfg_custom_presets_folder.get();
    _lastSortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);
    _lastFilter = cfg_preset_filter.get();
```

- [ ] **Step 2: Initialize new ivars in initWithFrame**

In `mac/ProjectMView.mm`, in `initWithFrame:`, after `_fpsFrameCount = 0;` (line 114), add:

```objc
        _isAutoPaused = NO;
        _lastSettingsGeneration = 0;
        _halfResFBO = 0;
        _halfResColorRB = 0;
        _halfResDepthRB = 0;
        _halfResWidth = 0;
        _halfResHeight = 0;
        _cachedResolutionScale = 1;
        _cachedFpsCap = 60;
        _cachedIdleFps = 30;
        _cachedMeshQuality = 1;
        _lastSortOrder = 0;
```

- [ ] **Step 3: Replace frameDurationInMachTicks with configurable version**

In `mac/ProjectMView.mm`, replace the existing `frameDurationInMachTicks` function (lines 15-26) with:

```cpp
static uint64_t frameDurationInMachTicks(int fpsCap) {
    if (fpsCap <= 0) return 0;  // Unlimited
    static mach_timebase_info_data_t info = {0, 0};
    if (info.denom == 0) mach_timebase_info(&info);
    double nsPerTick = (double)info.numer / info.denom;
    return (uint64_t)((1e9 / (double)fpsCap) / nsPerTick);
}
```

- [ ] **Step 4: Update frame cap check in renderFrame**

In `mac/ProjectMView.mm`, in `renderFrame`, replace the frame cap check (line 308):

```objc
        if (now_mach - _lastRenderTimestamp < frameDurationInMachTicks(!_isAudioPlaybackActive)) {
```

With:

```objc
        int effectiveFps = _isAudioPlaybackActive ? _cachedFpsCap : _cachedIdleFps;
        uint64_t minDuration = frameDurationInMachTicks(effectiveFps);
        if (minDuration > 0 && now_mach - _lastRenderTimestamp < minDuration) {
```

- [ ] **Step 5: Add generation counter check in renderFrame**

In `mac/ProjectMView.mm`, in `renderFrame`, after the FPS counter block (after `_fpsFrameCount = 0;`, around line 327) and before `[self addPCM]`, add:

```objc
        uint32_t gen = g_settingsGeneration.load(std::memory_order_relaxed);
        if (gen != _lastSettingsGeneration) {
            [self applySettingsFromPreferences];
            _lastSettingsGeneration = gen;
        }
```

- [ ] **Step 6: Add applySettingsFromPreferences method**

In `mac/ProjectMView.mm`, before the `@end` of `@implementation ProjectMView` (before `reshape`), add:

```objc
- (void)applySettingsFromPreferences {
    if (!_projectM) return;

    // Immediate projectM API calls (cheap, safe to call even if unchanged)
    projectm_set_beat_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_beat_sensitivity));
    projectm_set_soft_cut_duration(_projectM, (double)PMValidatedSoftCutDuration((int)cfg_soft_cut_duration));
    projectm_set_hard_cut_enabled(_projectM, (bool)cfg_hard_cuts);
    projectm_set_hard_cut_sensitivity(_projectM, PMSensitivityFloatValue((int)cfg_hard_cut_sensitivity));
    projectm_set_hard_cut_duration(_projectM, (double)PMValidatedHardCutInterval((int)cfg_hard_cut_interval));
    projectm_set_aspect_correction(_projectM, (bool)cfg_aspect_correction);
    projectm_set_easter_egg(_projectM, PMDurationRandomizationFloatValue((int)cfg_duration_randomization));

    int fpsCap = PMValidatedFpsCap((int)cfg_fps_cap);
    projectm_set_fps(_projectM, fpsCap > 0 ? fpsCap : 60);
    _cachedFpsCap = fpsCap;
    _cachedIdleFps = PMValidatedIdleFps((int)cfg_idle_fps);

    // Vsync (called from renderFrame which already holds the CGL lock)
    GLint swapInt = cfg_vsync ? 1 : 0;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLContextParameterSwapInterval];

    // Mesh quality (only if changed -- causes reallocation)
    int meshQuality = PMValidatedMeshQuality((int)cfg_mesh_quality);
    if (meshQuality != _cachedMeshQuality) {
        float heightWidthRatio = (_cachedHeight > 0 && _cachedWidth > 0) ? (float)_cachedHeight / (float)_cachedWidth : 1.0f;
        int meshSize = PMMeshSizeForQuality(meshQuality);
        projectm_set_mesh_size(_projectM, meshSize, (size_t)(meshSize * heightWidthRatio));
        _cachedMeshQuality = meshQuality;
    }

    // Retry count
    if (_playlist) {
        projectm_playlist_set_retry_count(_playlist, PMValidatedRetryCount((int)cfg_preset_retry_count));
    }

    // Auto-pause evaluation
    if (cfg_auto_pause && !_isAudioPlaybackActive && !_isVisualizationPaused && !_isAutoPaused) {
        _isAutoPaused = YES;
        // Note: don't stop CVDisplayLink here -- we're inside renderFrame on the CVDisplayLink thread.
        // The auto-pause logic in addPCM handles the actual stop.
    } else if ((!cfg_auto_pause || _isAudioPlaybackActive) && _isAutoPaused) {
        _isAutoPaused = NO;
    }

    // Resolution scale, FBO, and preset-related heavyweight changes are handled in Tasks 5-8.
}
```

- [ ] **Step 7: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000: change settings in preferences, verify they take effect on the running visualization without restart. Test: change beat sensitivity, soft cut duration, hard cuts toggle, aspect correction, vsync, mesh quality, FPS cap. All should apply live.

- [ ] **Step 8: Commit**

```
feat: wire settings propagation via generation counter
```

---

### Task 5: Configurable FPS + auto-pause

**Files:**
- Modify: `mac/ProjectMView.mm` (auto-pause logic in addPCM, CVDisplayLink stop/start)

- [ ] **Step 1: Add auto-pause logic to addPCM playback state change detection**

In `mac/ProjectMView.mm`, in `addPCM`, after the playback state change detection block (after `_pendingShuffleEnable = NO; _shuffleEnableDeadline = 0.0;` around line 430), add:

```objc
            // Auto-pause: mark for CVDisplayLink stop (actual stop happens after CGL unlock in renderFrame)
            if (cfg_auto_pause && !_isAudioPlaybackActive && !_isVisualizationPaused) {
                _isAutoPaused = YES;
            }
            // Note: auto-pause resume is handled by NSNotification (handlePlaybackStateChange:)
            // because once CVDisplayLink is stopped, addPCM is never called.
```

- [ ] **Step 2: Add auto-pause CVDisplayLink management after renderFrame**

The auto-pause stop/start needs to happen outside the CGL lock, similar to togglePausePlayback. In `renderFrame`, after `CGLUnlockContext(cglContext); contextLocked = NO;` at the end of the try block (around line 403), and before the `@catch`, add:

```objc
        // Auto-pause: stop display link after releasing CGL lock
        if (_isAutoPaused && _displayLink && CVDisplayLinkIsRunning(_displayLink)) {
            CVDisplayLinkStop(_displayLink);
            PMLog("projectM: auto-paused (no audio playback)");
        }
```

- [ ] **Step 3: Add auto-pause resume when music starts**

In `addPCM`, the auto-pause resume sets `_isAutoPaused = NO` but the CVDisplayLink is already stopped. The resume needs to happen from outside the CVDisplayLink callback. Add this logic by modifying the playback state callback in `ProjectMRegistration.mm`:

In `mac/ProjectMRegistration.mm`, the `on_playback_starting` and `on_playback_pause` callbacks already set `g_musicPlaybackActive`. The problem is that when auto-paused, the CVDisplayLink is stopped, so `addPCM` never runs to detect the state change.

Instead, handle auto-pause resume via a notification. In `ProjectMView.mm`, in `prepareOpenGL`, after the CVDisplayLink is started (end of method), add:

```objc
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePlaybackStateChange:)
                                                 name:@"PMPlaybackStateChanged"
                                               object:nil];
```

Add a new method to ProjectMView:

```objc
- (void)handlePlaybackStateChange:(NSNotification *)notification {
    if (!_isAutoPaused) return;
    if (!PMIsMusicPlaybackActive()) return;

    _isAutoPaused = NO;
    _lastRenderTimestamp = 0;

    if (_displayLink && !CVDisplayLinkIsRunning(_displayLink)) {
        CVReturn status = CVDisplayLinkStart(_displayLink);
        if (status != kCVReturnSuccess) {
            PMLogError("projectM: CVDisplayLinkStart() failed on auto-unpause.");
        } else {
            PMLog("projectM: auto-unpaused (playback resumed)");
        }
    }
}
```

In `ProjectMRegistration.mm`, in `on_playback_starting` and `on_playback_pause`, after `g_musicPlaybackActive.store(...)`, add:

```objc
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"PMPlaybackStateChanged" object:nil];
        });
```

In `on_playback_stop`, add the same notification post.

In `dealloc`, add:

```objc
    [[NSNotificationCenter defaultCenter] removeObserver:self];
```

- [ ] **Step 4: Ensure manual pause takes priority over auto-pause**

In `togglePausePlayback:`, when unpausing, also clear auto-pause:

After `_isVisualizationPaused = !_isVisualizationPaused;` add:

```objc
        if (!_isVisualizationPaused) {
            _isAutoPaused = NO;
        }
```

Add the method declaration to ProjectMView.h:

```objc
/// Handle playback state changes for auto-pause.
- (void)handlePlaybackStateChange:(NSNotification *)notification;
```

- [ ] **Step 5: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000: enable auto-pause in preferences, stop music -- visualization should stop rendering (CPU drops to ~0%). Start music -- visualization resumes. Manual pause should still work independently. Toggling auto-pause off while auto-paused should resume rendering.

- [ ] **Step 6: Commit**

```
feat: add configurable FPS caps and auto-pause on music stop
```

---

### Task 6: Resolution scale + FBO half-res pipeline

**Files:**
- Modify: `mac/ProjectMView.mm` (setupHalfResFBO, teardownHalfResFBO, renderFrame FBO binding, resolution scale switching)
- Modify: `mac/ProjectMView.mm:72-117` (initWithFrame: set wantsBestResolutionOpenGLSurface based on cfg)

- [ ] **Step 1: Set initial wantsBestResolutionOpenGLSurface from cfg_resolution_scale**

In `mac/ProjectMView.mm`, in `initWithFrame:`, replace line 84:

```objc
        [self setWantsBestResolutionOpenGLSurface:NO];
```

With:

```objc
        [self setWantsBestResolutionOpenGLSurface:(PMValidatedResolutionScale((int)cfg_resolution_scale) == 2)];
```

- [ ] **Step 2: Add FBO setup/teardown methods**

In `mac/ProjectMView.mm`, before `reshape`, add:

```objc
- (void)setupHalfResFBO:(int)fullWidth height:(int)fullHeight {
    [self teardownHalfResFBO];

    _halfResWidth = fullWidth / 2;
    _halfResHeight = fullHeight / 2;
    if (_halfResWidth < 64) _halfResWidth = 64;
    if (_halfResHeight < 64) _halfResHeight = 64;

    glGenFramebuffers(1, &_halfResFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, _halfResFBO);

    glGenRenderbuffers(1, &_halfResColorRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _halfResColorRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, _halfResWidth, _halfResHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _halfResColorRB);

    glGenRenderbuffers(1, &_halfResDepthRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _halfResDepthRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, _halfResWidth, _halfResHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _halfResDepthRB);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        PMLogError("projectM: half-res FBO setup failed, status=",
            [[NSString stringWithFormat:@"0x%X", status] UTF8String]);
        [self teardownHalfResFBO];
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    PMLog("projectM: half-res FBO created ",
        [[NSString stringWithFormat:@"%dx%d", _halfResWidth, _halfResHeight] UTF8String]);
}

- (void)teardownHalfResFBO {
    if (_halfResFBO) { glDeleteFramebuffers(1, &_halfResFBO); _halfResFBO = 0; }
    if (_halfResColorRB) { glDeleteRenderbuffers(1, &_halfResColorRB); _halfResColorRB = 0; }
    if (_halfResDepthRB) { glDeleteRenderbuffers(1, &_halfResDepthRB); _halfResDepthRB = 0; }
    _halfResWidth = 0;
    _halfResHeight = 0;
}
```

- [ ] **Step 3: Add FBO rendering path in renderFrame**

In `mac/ProjectMView.mm`, in `renderFrame`, replace the rendering block (lines 395-400):

```objc
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        projectm_opengl_render_frame(_projectM);

        [[self openGLContext] flushBuffer];
```

With:

```objc
        if (_cachedResolutionScale == 0 && _halfResFBO) {
            // Half-resolution: render to FBO, then blit to screen
            glBindFramebuffer(GL_FRAMEBUFFER, _halfResFBO);
            glViewport(0, 0, _halfResWidth, _halfResHeight);
            glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            projectm_opengl_render_frame(_projectM);

            // projectM may leave its own FBOs bound; rebind explicitly
            glBindFramebuffer(GL_READ_FRAMEBUFFER, _halfResFBO);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
            glViewport(0, 0, _cachedWidth, _cachedHeight);
            glBlitFramebuffer(0, 0, _halfResWidth, _halfResHeight,
                              0, 0, _cachedWidth, _cachedHeight,
                              GL_COLOR_BUFFER_BIT, GL_LINEAR);
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
        } else {
            // Standard or Retina: render directly
            glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            projectm_opengl_render_frame(_projectM);
        }

        [[self openGLContext] flushBuffer];
```

- [ ] **Step 4: Handle resolution scale changes in applySettingsFromPreferences**

In `mac/ProjectMView.mm`, in `applySettingsFromPreferences`, at the end of the method (replacing the placeholder comment about resolution scale), add:

```objc
    // Resolution scale
    int resScale = PMValidatedResolutionScale((int)cfg_resolution_scale);
    if (resScale != _cachedResolutionScale) {
        int oldScale = _cachedResolutionScale;

        if (resScale == 0) {
            // Switching to Half: set up FBO (already on CVDisplayLink thread, CGL lock held)
            _cachedResolutionScale = resScale;
            [self setupHalfResFBO:_cachedWidth height:_cachedHeight];
            projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
        } else if (oldScale == 0 && resScale != 0) {
            // Switching from Half to Standard or Retina: tear down FBO first
            [self teardownHalfResFBO];
            _cachedResolutionScale = resScale;
            // Standard <-> Retina requires main thread for wantsBestResolutionOpenGLSurface
            if (resScale == 2 || oldScale == 2) {
                BOOL wantsRetina = (resScale == 2);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setWantsBestResolutionOpenGLSurface:wantsRetina];
                    [[self openGLContext] update];
                    int width = 0, height = 0;
                    [self getDrawableSizeWidth:&width height:&height];
                    CGLContextObj ctx = [[self openGLContext] CGLContextObj];
                    if (ctx) CGLLockContext(ctx);
                    glViewport(0, 0, width, height);
                    projectm_set_window_size(self->_projectM, width, height);
                    self->_cachedWidth = width;
                    self->_cachedHeight = height;
                    if (ctx) CGLUnlockContext(ctx);
                });
            }
        } else {
            // Standard <-> Retina (no FBO involved)
            _cachedResolutionScale = resScale;
            BOOL wantsRetina = (resScale == 2);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setWantsBestResolutionOpenGLSurface:wantsRetina];
                [[self openGLContext] update];
                int width = 0, height = 0;
                [self getDrawableSizeWidth:&width height:&height];
                CGLContextObj ctx = [[self openGLContext] CGLContextObj];
                if (ctx) CGLLockContext(ctx);
                glViewport(0, 0, width, height);
                projectm_set_window_size(self->_projectM, width, height);
                self->_cachedWidth = width;
                self->_cachedHeight = height;
                if (ctx) CGLUnlockContext(ctx);
            });
        }
    }
```

- [ ] **Step 5: Update reshape and viewDidChangeBackingProperties to handle FBO**

In `mac/ProjectMView.mm`, in `reshape`, after `_cachedHeight = height;` (line 503), add:

```objc
    if (_cachedResolutionScale == 0) {
        [self setupHalfResFBO:width height:height];
        projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
    }
```

Wrap the existing `projectm_set_window_size` call in an else:

```objc
    if (_cachedResolutionScale == 0) {
        [self setupHalfResFBO:width height:height];
        projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
    } else {
        projectm_set_window_size(_projectM, width, height);
    }
```

Do the same in `viewDidChangeBackingProperties` where `projectm_set_window_size` is called.

- [ ] **Step 6: Clean up FBO in destroyProjectMState and dealloc**

In `mac/ProjectMView.mm`, in `destroyProjectMState`, after `[[self openGLContext] makeCurrentContext];` (line 56), add:

```objc
    [self teardownHalfResFBO];
```

- [ ] **Step 7: Set half-res FBO projectM window size in createProjectM**

In `createProjectM`, after the existing `_cachedWidth = width; _cachedHeight = height;` and the new `_cachedResolutionScale = ...` line, add:

```objc
    if (_cachedResolutionScale == 0) {
        [self setupHalfResFBO:width height:height];
        projectm_set_window_size(_projectM, _halfResWidth, _halfResHeight);
    }
```

- [ ] **Step 8: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000: switch between Half/Standard/Retina in preferences. Half mode should render at lower resolution with visible upscaling. Retina should be sharper (on Retina display). Standard is the default. Resize window while in Half mode -- FBO should adapt. No crashes or visual glitches.

- [ ] **Step 9: Commit**

```
feat: add resolution scale with FBO half-resolution pipeline
```

---

### Task 7: Mouse interaction

**Files:**
- Modify: `mac/ProjectMView+Menu.mm:176-186` (mouseDown: add projectm_touch call)
- Modify: `mac/ProjectMView+Menu.mm` (add mouseDragged: and mouseUp: methods)

- [ ] **Step 1: Modify mouseDown: to support projectm_touch**

In `mac/ProjectMView+Menu.mm`, replace the `mouseDown:` method (lines 176-186):

```objc
- (void)mouseDown:(NSEvent *)event {
    if (self->_isVisualizationPaused) {
        [self togglePausePlayback:nil];
        return;
    }

    if (event.clickCount == 2) {
        [self toggleVisualizationFullScreen];
    }
    [super mouseDown:event];
}
```

With:

```objc
- (void)mouseDown:(NSEvent *)event {
    if (self->_isVisualizationPaused || self->_isAutoPaused) {
        [self togglePausePlayback:nil];
        return;
    }

    if (event.clickCount == 2) {
        [self toggleVisualizationFullScreen];
        return;
    }

    if (cfg_mouse_interaction && _projectM) {
        NSPoint viewPoint = [self convertPoint:event.locationInWindow fromView:nil];
        NSPoint pixelPoint = [self convertPointToBacking:viewPoint];
        // Scale coordinates to projectM's window size (differs from backing in half-res mode)
        float touchX = (float)pixelPoint.x;
        float touchY = (float)pixelPoint.y;
        if (_cachedResolutionScale == 0 && _cachedWidth > 0 && _halfResWidth > 0) {
            touchX *= (float)_halfResWidth / (float)_cachedWidth;
            touchY *= (float)_halfResHeight / (float)_cachedHeight;
        }
        projectm_touch(_projectM, touchX, touchY, 1,
                        (projectm_touch_type)(int)cfg_mouse_effect);
        return;
    }

    [super mouseDown:event];
}
```

- [ ] **Step 2: Add mouseDragged: and mouseUp: methods**

After `mouseDown:`, add:

```objc
- (void)mouseDragged:(NSEvent *)event {
    if (!cfg_mouse_interaction || !_projectM) {
        [super mouseDragged:event];
        return;
    }
    NSPoint viewPoint = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pixelPoint = [self convertPointToBacking:viewPoint];
    float touchX = (float)pixelPoint.x;
    float touchY = (float)pixelPoint.y;
    if (_cachedResolutionScale == 0 && _cachedWidth > 0 && _halfResWidth > 0) {
        touchX *= (float)_halfResWidth / (float)_cachedWidth;
        touchY *= (float)_halfResHeight / (float)_cachedHeight;
    }
    projectm_touch_drag(_projectM, touchX, touchY, 1);
}

- (void)mouseUp:(NSEvent *)event {
    if (!cfg_mouse_interaction || !_projectM) {
        [super mouseUp:event];
        return;
    }
    NSPoint viewPoint = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pixelPoint = [self convertPointToBacking:viewPoint];
    float touchX = (float)pixelPoint.x;
    float touchY = (float)pixelPoint.y;
    if (_cachedResolutionScale == 0 && _cachedWidth > 0 && _halfResWidth > 0) {
        touchX *= (float)_halfResWidth / (float)_cachedWidth;
        touchY *= (float)_halfResHeight / (float)_cachedHeight;
    }
    projectm_touch_destroy(_projectM, touchX, touchY);
}
```

- [ ] **Step 3: Add #include for projectm_touch API**

Verify that `<projectM-4/projectM.h>` already includes `projectm_touch`, `projectm_touch_drag`, `projectm_touch_destroy`, `projectm_touch_type`. If not, add the necessary include. The projectM 4.1.6 header should include these in the main header.

- [ ] **Step 4: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000: enable mouse interaction in preferences, click on the visualization -- a visual effect should appear at the clicked position. Drag to create a trail effect. Different mouse effect types should produce different visual results. When disabled, clicks resume default behavior (double-click fullscreen, right-click menu).

- [ ] **Step 5: Commit**

```
feat: add mouse interaction with configurable effect types
```

---

### Task 8: Preset management (custom folder, sort, filter, retry)

**Files:**
- Modify: `mac/ProjectMView+Presets.mm:451-467` (resolvedDataDirectoryPathUsedZip: check cfg_custom_presets_folder)
- Modify: `mac/ProjectMView+Presets.mm:529-620` (loadPresetsFromCurrentSource: apply sort/filter)
- Modify: `mac/ProjectMView.mm` (applySettingsFromPreferences: add heavyweight preset reload)

- [ ] **Step 1: Modify resolvedDataDirectoryPathUsedZip to check custom presets folder**

In `mac/ProjectMView+Presets.mm`, in `resolvedDataDirectoryPathUsedZip:`, at the start of the method (after `if (usedZip) *usedZip = NO;`), add:

```objc
    // Check custom presets folder first
    auto customFolder = cfg_custom_presets_folder.get();
    NSString *customPath = customFolder.length() > 0 ? @(customFolder.get_ptr()) : nil;
    if (customPath.length > 0) {
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:customPath isDirectory:&isDir] && isDir) {
            // Verify it has at least one .milk file
            NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:customPath];
            for (NSString *entry in enumerator) {
                if ([[[entry pathExtension] lowercaseString] isEqualToString:@"milk"]) {
                    PMLog("projectM: using custom presets folder: ", [customPath UTF8String]);
                    return [customPath stringByStandardizingPath];
                }
            }
            PMLogError("projectM: custom presets folder contains no .milk files: ", [customPath UTF8String]);
        } else {
            PMLogError("projectM: custom presets folder not found: ", [customPath UTF8String]);
        }
    }
```

- [ ] **Step 2: Apply sort order after loading presets**

In `mac/ProjectMView+Presets.mm`, in `loadPresetsFromCurrentSource`, after `projectm_playlist_set_retry_count(_playlist, 0);` (line 573), add:

```objc
            // Apply configured retry count
            projectm_playlist_set_retry_count(_playlist, PMValidatedRetryCount((int)cfg_preset_retry_count));
```

And replace the existing `projectm_playlist_set_retry_count(_playlist, 0);` line.

After setting up callbacks and before the preset selection logic (before `uint32_t totalPresets = projectm_playlist_size(_playlist);`), add sort and filter:

```objc
            // Apply sort order
            int sortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);
            projectm_playlist_sort_predicate sortPredicate = (sortOrder <= 1)
                ? SORT_PREDICATE_FILENAME_ONLY
                : SORT_PREDICATE_FULL_PATH;
            projectm_playlist_sort_order sortDirection = (sortOrder == 0 || sortOrder == 2)
                ? SORT_ORDER_ASCENDING
                : SORT_ORDER_DESCENDING;
            projectm_playlist_sort(_playlist, 0, projectm_playlist_size(_playlist), sortPredicate, sortDirection);

            // Apply filter
            NSArray<NSString *> *filterPatterns = PMParsePresetFilter(@(cfg_preset_filter.get().get_ptr()));
            if (filterPatterns.count > 0) {
                NSMutableArray<NSData *> *cStrings = [NSMutableArray array];
                const char **patterns = (const char **)malloc(sizeof(const char *) * filterPatterns.count);
                for (NSUInteger i = 0; i < filterPatterns.count; i++) {
                    NSData *utf8 = [filterPatterns[i] dataUsingEncoding:NSUTF8StringEncoding];
                    [cStrings addObject:utf8];
                    patterns[i] = (const char *)utf8.bytes;
                }
                projectm_playlist_set_filter(_playlist, patterns, (size_t)filterPatterns.count);
                projectm_playlist_apply_filter(_playlist);
                free(patterns);
            } else {
                projectm_playlist_set_filter(_playlist, NULL, 0);
                projectm_playlist_apply_filter(_playlist);
            }
```

- [ ] **Step 3: Remove the localizedCaseInsensitiveCompare sort from addPresetsFromPath**

In `mac/ProjectMView+Presets.mm`, in `addPresetsFromPath:recursive:`, remove line 240:

```objc
    [candidatePaths sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
```

The sorting is now handled by `projectm_playlist_sort` after all presets are added. The order presets are added doesn't matter since we sort the playlist afterwards.

- [ ] **Step 4: Add heavyweight preset reload to applySettingsFromPreferences**

In `mac/ProjectMView.mm`, in `applySettingsFromPreferences`, at the end (after the resolution scale block), add:

```objc
    // Heavyweight updates: custom folder, sort, filter require playlist reload
    // Detected by comparing current cfg values with cached ivars.
    auto currentFolder = cfg_custom_presets_folder.get();
    int currentSortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);
    auto currentFilter = cfg_preset_filter.get();

    if (strcmp(currentFolder.get_ptr(), _lastCustomFolder.get_ptr()) != 0 ||
        currentSortOrder != _lastSortOrder ||
        strcmp(currentFilter.get_ptr(), _lastFilter.get_ptr()) != 0) {
        _lastCustomFolder = currentFolder;
        _lastSortOrder = currentSortOrder;
        _lastFilter = currentFilter;
        PMLog("projectM: reloading presets due to settings change");
        [self loadPresetsFromCurrentSource];
    }
```

- [ ] **Step 5: Build and test**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, tests pass. In foobar2000:
- Set a custom presets folder -- preset browser should show presets from that folder
- Clear the folder -- presets revert to built-in ZIP collection
- Change sort order -- preset browser order changes
- Enter a filter pattern -- only matching presets appear
- Change retry count -- affects how the component handles broken presets

- [ ] **Step 6: Commit**

```
feat: add custom presets folder, sort order, filter, and retry count
```

---

### Task 9: Final integration and cleanup

**Files:**
- Modify: `mac/ProjectMView.mm` (verify all settings wire up end-to-end)

- [ ] **Step 1: Verify PMUseHardCutTransitions uses cfg_hard_cuts**

In `mac/ProjectMMenuLogic.mm`, the existing `PMUseHardCutTransitions` function returns `NO` unconditionally. Since hard cuts are now configurable via `cfg_hard_cuts`, this function should read from the cfg. However, `PMUseHardCutTransitions` is used in multiple places for preset switching (not the automatic hard cut during playback). The projectM API's `projectm_set_hard_cut_enabled` already controls automatic hard cuts. `PMUseHardCutTransitions` controls whether *manual* preset switches (next/prev/select) use hard cuts -- we want those to always soft-cut regardless of the hard cuts setting. So keep it returning `NO`.

No code change needed here -- just verification.

- [ ] **Step 2: Verify prepareOpenGL reads vsync from cfg**

In `mac/ProjectMView.mm`, in `prepareOpenGL`, replace line 133:

```objc
    GLint swapInt = 1;
```

With:

```objc
    GLint swapInt = cfg_vsync ? 1 : 0;
```

- [ ] **Step 3: Build and deploy**

Run: `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
Expected: Build succeeds, all tests pass. Full end-to-end verification: all 18 settings persist across foobar2000 restarts, all take effect live, dependent controls dim/enable correctly, no visual glitches during setting changes.

- [ ] **Step 4: Commit**

```
feat: wire initial vsync from preferences and final integration
```
