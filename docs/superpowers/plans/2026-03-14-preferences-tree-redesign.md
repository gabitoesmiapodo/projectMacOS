# Preferences Tree Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the single "projectMacOS" preferences page into a tree of five section pages, with a native foobar2000 layout style (left-aligned labels, stretching controls).

**Architecture:** A shared `PMPrefsHelpers` category on `NSViewController` (declared in `ProjectMPrefsParent.h`, implemented in `ProjectMPrefsHelpers.mm`) provides layout utilities used by all five section view controllers. `ProjectMPreferences.mm` is rewritten as a blank parent page; five new `.mm` files each register one `preferences_page` child with `get_parent_guid()` returning `kPrefsParentGUID`. All new files are added to the main Xcode target in `projectMacOS.xcodeproj`.

**Tech Stack:** Objective-C++, foobar2000 SDK (preferences_page, FB2K_SERVICE_FACTORY), AppKit (NSStackView, NSViewController, NSPopUpButton, NSButton, NSTextField)

---

## Chunk 1: Shared infrastructure and parent page

### Task 1: Shared helpers header and implementation

**Files:**
- Create: `mac/ProjectMPrefsParent.h`
- Create: `mac/ProjectMPrefsHelpers.mm`

No unit tests — no new logic. Verification: the files compile when included (confirmed in Task 4 build).

- [ ] **Step 1: Create `mac/ProjectMPrefsParent.h`**

```objc
#pragma once

// kPrefsParentGUID: GUID for the "projectMacOS" parent preferences_page node.
// All five section pages return this from get_parent_guid().
// Defined in ProjectMPreferences.mm.
extern const GUID kPrefsParentGUID;

// PMPrefsHelpers: layout utilities shared across all five section view controllers.
// Implemented in ProjectMPrefsHelpers.mm.
@interface NSViewController (PMPrefsHelpers)

/// Horizontal row: left-aligned label (natural width, high hugging) + control (stretches).
- (NSStackView *)rowWithLabel:(NSString *)labelText control:(NSView *)control;

/// Secondary help text: 11pt, secondaryLabelColor, wrapping.
- (NSTextField *)helpText:(NSString *)text;

/// Fixed-height (8pt) invisible spacer view.
- (NSView *)spacer;

/// NSPopUpButton pre-populated with titles and integer tags.
/// The item whose tag matches currentValue is pre-selected.
/// target is self; action is wired to the concrete subclass.
- (NSPopUpButton *)popupWithTitles:(NSArray<NSString *> *)titles
                            values:(NSArray<NSNumber *> *)values
                      currentValue:(int)currentValue
                            action:(SEL)action;

@end
```

- [ ] **Step 2: Create `mac/ProjectMPrefsHelpers.mm`**

```objc
#import "stdafx.h"
#import "ProjectMPrefsParent.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation NSViewController (PMPrefsHelpers)

- (NSStackView *)rowWithLabel:(NSString *)labelText control:(NSView *)control {
    NSTextField *label = [NSTextField labelWithString:labelText];
    label.alignment = NSTextAlignmentLeft;
    [label setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[label, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    return row;
}

- (NSTextField *)helpText:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSView *)spacer {
    NSView *view = [[NSView alloc] init];
    [view.heightAnchor constraintEqualToConstant:8].active = YES;
    return view;
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

@end

#pragma clang diagnostic pop
```

- [ ] **Step 3: Commit**

```bash
git add mac/ProjectMPrefsParent.h mac/ProjectMPrefsHelpers.mm
git commit -m "feat: add shared PMPrefsHelpers category for section prefs pages"
```

---

### Task 2: Rewrite parent preferences page

**Files:**
- Modify: `mac/ProjectMPreferences.mm`

The existing file registers a single page with all controls. Replace its entire content with a blank-view parent page. The GUID is unchanged so foobar2000 persists the user's tree expansion state. `kPrefsParentGUID` is defined here since this is the canonical source for the parent GUID.

- [ ] **Step 1: Replace `mac/ProjectMPreferences.mm` with the following**

```objc
#import "stdafx.h"
#import "ProjectMPrefsParent.h"

// kPrefsParentGUID is declared in ProjectMPrefsParent.h and used by all section pages.
const GUID kPrefsParentGUID = { 0x2f8a5e17, 0x3c94, 0x4b61, { 0xa7, 0xd2, 0xe1, 0x9f, 0x0b, 0x84, 0xc5, 0x3a } };

namespace {

class preferences_page_projectMacOS : public preferences_page {
public:
    service_ptr instantiate() override {
        NSViewController *vc = [[NSViewController alloc] init];
        vc.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        return fb2k::wrapNSObject(vc);
    }
    const char *get_name() override { return "projectMacOS"; }
    GUID get_guid() override { return kPrefsParentGUID; }
    GUID get_parent_guid() override { return guid_tools; }
    double get_sort_priority() override { return 0.0; }
};

FB2K_SERVICE_FACTORY(preferences_page_projectMacOS);

} // anonymous namespace
```

- [ ] **Step 2: Commit**

```bash
git add mac/ProjectMPreferences.mm
git commit -m "refactor: replace monolithic prefs page with blank parent node"
```

---

## Chunk 2: Section pages, Xcode project, and build

### Task 3: Performance and Transitions section pages

**Files:**
- Create: `mac/ProjectMPrefsPerformance.mm`
- Create: `mac/ProjectMPrefsTransitions.mm`

Each file imports `stdafx.h`, `ProjectMView.h` (cfg_ externs + PMSettingsDidChange), `ProjectMMenuLogic.h` (PMValidated* functions), and `ProjectMPrefsParent.h` (kPrefsParentGUID + PMPrefsHelpers).

- [ ] **Step 1: Create `mac/ProjectMPrefsPerformance.mm`**

```objc
#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"
#import "ProjectMPrefsParent.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface ProjectMPrefsPerformanceViewController : NSViewController
@end

@implementation ProjectMPrefsPerformanceViewController {
    NSPopUpButton *_fpsCapPopup;
    NSPopUpButton *_idleFpsPopup;
    NSPopUpButton *_resolutionScalePopup;
    NSPopUpButton *_meshQualityPopup;
    NSButton *_vsyncCheckbox;
    NSButton *_autoPauseCheckbox;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(20, 16, 20, 16);

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

    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];
    self.view = root;
}

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

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_performance : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([ProjectMPrefsPerformanceViewController new]);
    }
    const char *get_name() override { return "Performance"; }
    GUID get_guid() override {
        return { 0xb1c2d3e4, 0xf5a6, 0x4789, { 0x8a, 0xbc, 0xde, 0xf0, 0x12, 0x34, 0x56, 0x78 } };
    }
    GUID get_parent_guid() override { return kPrefsParentGUID; }
    double get_sort_priority() override { return 0.0; }
};

FB2K_SERVICE_FACTORY(preferences_page_performance);

} // anonymous namespace
```

- [ ] **Step 2: Create `mac/ProjectMPrefsTransitions.mm`**

```objc
#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"
#import "ProjectMPrefsParent.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface ProjectMPrefsTransitionsViewController : NSViewController
@end

@implementation ProjectMPrefsTransitionsViewController {
    NSPopUpButton *_softCutDurationPopup;
    NSButton *_hardCutsCheckbox;
    NSPopUpButton *_hardCutSensitivityPopup;
    NSPopUpButton *_hardCutIntervalPopup;
    NSPopUpButton *_durationRandomizationPopup;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(20, 16, 20, 16);

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

    [stack addArrangedSubview:[self spacer]];

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

    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];
    self.view = root;
}

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

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_transitions : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([ProjectMPrefsTransitionsViewController new]);
    }
    const char *get_name() override { return "Transitions"; }
    GUID get_guid() override {
        return { 0xc2d3e4f5, 0xa6b7, 0x4890, { 0x9b, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89 } };
    }
    GUID get_parent_guid() override { return kPrefsParentGUID; }
    double get_sort_priority() override { return 1.0; }
};

FB2K_SERVICE_FACTORY(preferences_page_transitions);

} // anonymous namespace
```

- [ ] **Step 3: Commit**

```bash
git add mac/ProjectMPrefsPerformance.mm mac/ProjectMPrefsTransitions.mm
git commit -m "feat: add Performance and Transitions section prefs pages"
```

---

### Task 4: Visualization, Presets, and Diagnostics section pages

**Files:**
- Create: `mac/ProjectMPrefsVisualization.mm`
- Create: `mac/ProjectMPrefsPresets.mm`
- Create: `mac/ProjectMPrefsDiagnostics.mm`

The Presets page has a three-part folder row (label + stretching text field + Browse button) built manually instead of using `rowWithLabel:control:`. The Filter control uses `rowWithLabel:control:` directly.

- [ ] **Step 1: Create `mac/ProjectMPrefsVisualization.mm`**

```objc
#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"
#import "ProjectMPrefsParent.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface ProjectMPrefsVisualizationViewController : NSViewController
@end

@implementation ProjectMPrefsVisualizationViewController {
    NSPopUpButton *_beatSensitivityPopup;
    NSButton *_aspectCorrectionCheckbox;
    NSButton *_mouseInteractionCheckbox;
    NSPopUpButton *_mouseEffectPopup;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(20, 16, 20, 16);

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

    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];
    self.view = root;
}

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

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_visualization : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([ProjectMPrefsVisualizationViewController new]);
    }
    const char *get_name() override { return "Visualization"; }
    GUID get_guid() override {
        return { 0xd3e4f5a6, 0xb7c8, 0x4901, { 0xac, 0xde, 0xf0, 0x12, 0x34, 0x56, 0x78, 0x9a } };
    }
    GUID get_parent_guid() override { return kPrefsParentGUID; }
    double get_sort_priority() override { return 2.0; }
};

FB2K_SERVICE_FACTORY(preferences_page_visualization);

} // anonymous namespace
```

- [ ] **Step 2: Create `mac/ProjectMPrefsPresets.mm`**

```objc
#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"
#import "ProjectMPrefsParent.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface ProjectMPrefsPresetsViewController : NSViewController
@end

@implementation ProjectMPrefsPresetsViewController {
    NSTextField *_customPresetsFolderField;
    NSPopUpButton *_sortOrderPopup;
    NSTextField *_presetFilterField;
    NSPopUpButton *_retryCountPopup;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(20, 16, 20, 16);

    // Three-part folder row: label (natural width) + text field (stretches) + Browse button (natural width)
    NSTextField *folderLabel = [NSTextField labelWithString:@"Presets Folder:"];
    [folderLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    _customPresetsFolderField = [[NSTextField alloc] init];
    _customPresetsFolderField.placeholderString = @"Default (built-in collection)";
    _customPresetsFolderField.stringValue = @(cfg_custom_presets_folder.get().get_ptr());
    _customPresetsFolderField.target = self;
    _customPresetsFolderField.action = @selector(customPresetsFolderChanged:);
    [_customPresetsFolderField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *browseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browsePresetsFolder:)];
    [browseButton setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *folderRow = [NSStackView stackViewWithViews:@[folderLabel, _customPresetsFolderField, browseButton]];
    folderRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    folderRow.spacing = 6;
    [stack addArrangedSubview:folderRow];
    [stack addArrangedSubview:[self helpText:@"Override the default preset source with a folder of .milk files. Leave empty to use the built-in collection."]];

    _sortOrderPopup = [self popupWithTitles:@[@"Name A-Z", @"Name Z-A", @"Path A-Z", @"Path Z-A"]
                                     values:@[@0, @1, @2, @3]
                               currentValue:(int)cfg_preset_sort_order
                                     action:@selector(sortOrderChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Sort Order:" control:_sortOrderPopup]];
    [stack addArrangedSubview:[self helpText:@"Order of presets in the browser menu and initial playlist."]];

    _presetFilterField = [[NSTextField alloc] init];
    _presetFilterField.placeholderString = @"e.g. *warp*, *spiral*";
    _presetFilterField.stringValue = @(cfg_preset_filter.get().get_ptr());
    _presetFilterField.target = self;
    _presetFilterField.action = @selector(presetFilterChanged:);
    [stack addArrangedSubview:[self rowWithLabel:@"Filter:" control:_presetFilterField]];
    [stack addArrangedSubview:[self helpText:@"Comma-separated glob patterns to include presets (e.g. *warp*, *spiral*). Leave empty to load all presets."]];

    _retryCountPopup = [self popupWithTitles:@[@"1", @"3", @"5", @"10"]
                                      values:@[@1, @3, @5, @10]
                                currentValue:(int)cfg_preset_retry_count
                                      action:@selector(retryCountChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Retry Count:" control:_retryCountPopup]];
    [stack addArrangedSubview:[self helpText:@"How many times to retry loading a broken preset before skipping it."]];

    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];
    self.view = root;
}

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

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_presets : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([ProjectMPrefsPresetsViewController new]);
    }
    const char *get_name() override { return "Presets"; }
    GUID get_guid() override {
        return { 0xe4f5a6b7, 0xc8d9, 0x4012, { 0xbd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab } };
    }
    GUID get_parent_guid() override { return kPrefsParentGUID; }
    double get_sort_priority() override { return 3.0; }
};

FB2K_SERVICE_FACTORY(preferences_page_presets);

} // anonymous namespace
```

- [ ] **Step 3: Create `mac/ProjectMPrefsDiagnostics.mm`**

```objc
#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"
#import "ProjectMPrefsParent.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface ProjectMPrefsDiagnosticsViewController : NSViewController
@end

@implementation ProjectMPrefsDiagnosticsViewController {
    NSButton *_debugLoggingCheckbox;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(20, 16, 20, 16);

    _debugLoggingCheckbox = [NSButton checkboxWithTitle:@"Debug Logging" target:self action:@selector(debugLoggingChanged:)];
    _debugLoggingCheckbox.state = cfg_debug_logging ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_debugLoggingCheckbox];
    [stack addArrangedSubview:[self helpText:@"Log diagnostic messages to the foobar2000 console."]];

    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];
    self.view = root;
}

- (void)debugLoggingChanged:(id)sender {
    cfg_debug_logging = (_debugLoggingCheckbox.state == NSControlStateValueOn);
}

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_diagnostics : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([ProjectMPrefsDiagnosticsViewController new]);
    }
    const char *get_name() override { return "Diagnostics"; }
    GUID get_guid() override {
        return { 0xf5a6b7c8, 0xd9ea, 0x4123, { 0xce, 0xf0, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc } };
    }
    GUID get_parent_guid() override { return kPrefsParentGUID; }
    double get_sort_priority() override { return 4.0; }
};

FB2K_SERVICE_FACTORY(preferences_page_diagnostics);

} // anonymous namespace
```

- [ ] **Step 4: Commit**

```bash
git add mac/ProjectMPrefsVisualization.mm mac/ProjectMPrefsPresets.mm mac/ProjectMPrefsDiagnostics.mm
git commit -m "feat: add Visualization, Presets, and Diagnostics section prefs pages"
```

---

### Task 5: Wire new files into Xcode project, build, and deploy

**Files:**
- Modify: `mac/projectMacOS.xcodeproj/project.pbxproj`

The pbxproj uses a manually-maintained ID scheme. Each new source file needs:
1. A `PBXFileReference` entry (unique 24-char hex ID)
2. A `PBXBuildFile` entry (different unique ID pointing to the file reference)
3. An entry in the `Sources` PBXGroup's `children` array
4. An entry in the main target's `PBXSourcesBuildPhase` `files` array

The header (`ProjectMPrefsParent.h`) needs only a PBXFileReference + PBXGroup entry (no build file — headers are not compiled directly).

IDs to use (these IDs are unique and not present in the current pbxproj):
| File | FileRef ID | BuildFile ID |
|------|-----------|-------------|
| `ProjectMPrefsParent.h` | `AF100001AF100001AF100001` | (none) |
| `ProjectMPrefsHelpers.mm` | `AF100002AF100002AF100002` | `AF100003AF100003AF100003` |
| `ProjectMPrefsPerformance.mm` | `AF100004AF100004AF100004` | `AF100005AF100005AF100005` |
| `ProjectMPrefsTransitions.mm` | `AF100006AF100006AF100006` | `AF100007AF100007AF100007` |
| `ProjectMPrefsVisualization.mm` | `AF100008AF100008AF100008` | `AF100009AF100009AF100009` |
| `ProjectMPrefsPresets.mm` | `AF10000AAF10000AAF10000A` | `AF10000BAF10000BAF10000B` |
| `ProjectMPrefsDiagnostics.mm` | `AF10000CAF10000CAF10000C` | `AF10000DAF10000DAF10000D` |

- [ ] **Step 1: Add PBXBuildFile entries**

In `mac/projectMacOS.xcodeproj/project.pbxproj`, find the line:
```
		AA000014AA000014AA000014 /* unzip.c in Sources */ = {isa = PBXBuildFile; fileRef = AA000004AA000004AA000004 /* unzip.c */; };
```
Insert immediately after it (before `/* End PBXBuildFile section */`):
```
		AF100003AF100003AF100003 /* ProjectMPrefsHelpers.mm in Sources */ = {isa = PBXBuildFile; fileRef = AF100002AF100002AF100002 /* ProjectMPrefsHelpers.mm */; };
		AF100005AF100005AF100005 /* ProjectMPrefsPerformance.mm in Sources */ = {isa = PBXBuildFile; fileRef = AF100004AF100004AF100004 /* ProjectMPrefsPerformance.mm */; };
		AF100007AF100007AF100007 /* ProjectMPrefsTransitions.mm in Sources */ = {isa = PBXBuildFile; fileRef = AF100006AF100006AF100006 /* ProjectMPrefsTransitions.mm */; };
		AF100009AF100009AF100009 /* ProjectMPrefsVisualization.mm in Sources */ = {isa = PBXBuildFile; fileRef = AF100008AF100008AF100008 /* ProjectMPrefsVisualization.mm */; };
		AF10000BAF10000BAF10000B /* ProjectMPrefsPresets.mm in Sources */ = {isa = PBXBuildFile; fileRef = AF10000AAF10000AAF10000A /* ProjectMPrefsPresets.mm */; };
		AF10000DAF10000DAF10000D /* ProjectMPrefsDiagnostics.mm in Sources */ = {isa = PBXBuildFile; fileRef = AF10000CAF10000CAF10000C /* ProjectMPrefsDiagnostics.mm */; };
```

- [ ] **Step 2: Add PBXFileReference entries**

Find the line:
```
		AA000004AA000004AA000004 /* unzip.c */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.c; name = unzip.c; path = zipfs/unzip.c; sourceTree = "<group>"; };
```
Insert immediately after it (before `/* End PBXFileReference section */`):
```
		AF100001AF100001AF100001 /* ProjectMPrefsParent.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; name = ProjectMPrefsParent.h; path = ProjectMPrefsParent.h; sourceTree = "<group>"; };
		AF100002AF100002AF100002 /* ProjectMPrefsHelpers.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; name = ProjectMPrefsHelpers.mm; path = ProjectMPrefsHelpers.mm; sourceTree = "<group>"; };
		AF100004AF100004AF100004 /* ProjectMPrefsPerformance.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; name = ProjectMPrefsPerformance.mm; path = ProjectMPrefsPerformance.mm; sourceTree = "<group>"; };
		AF100006AF100006AF100006 /* ProjectMPrefsTransitions.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; name = ProjectMPrefsTransitions.mm; path = ProjectMPrefsTransitions.mm; sourceTree = "<group>"; };
		AF100008AF100008AF100008 /* ProjectMPrefsVisualization.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; name = ProjectMPrefsVisualization.mm; path = ProjectMPrefsVisualization.mm; sourceTree = "<group>"; };
		AF10000AAF10000AAF10000A /* ProjectMPrefsPresets.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; name = ProjectMPrefsPresets.mm; path = ProjectMPrefsPresets.mm; sourceTree = "<group>"; };
		AF10000CAF10000CAF10000C /* ProjectMPrefsDiagnostics.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; name = ProjectMPrefsDiagnostics.mm; path = ProjectMPrefsDiagnostics.mm; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add entries to Sources PBXGroup children**

Find the line:
```
				AE100001AE100001AE100001 /* ProjectMPreferences.mm */,
```
Insert immediately after it:
```
				AF100001AF100001AF100001 /* ProjectMPrefsParent.h */,
				AF100002AF100002AF100002 /* ProjectMPrefsHelpers.mm */,
				AF100004AF100004AF100004 /* ProjectMPrefsPerformance.mm */,
				AF100006AF100006AF100006 /* ProjectMPrefsTransitions.mm */,
				AF100008AF100008AF100008 /* ProjectMPrefsVisualization.mm */,
				AF10000AAF10000AAF10000A /* ProjectMPrefsPresets.mm */,
				AF10000CAF10000CAF10000C /* ProjectMPrefsDiagnostics.mm */,
```

- [ ] **Step 4: Add entries to main target PBXSourcesBuildPhase**

Find the line:
```
				AE200001AE200001AE200001 /* ProjectMPreferences.mm in Sources */,
```
Insert immediately after it:
```
				AF100003AF100003AF100003 /* ProjectMPrefsHelpers.mm in Sources */,
				AF100005AF100005AF100005 /* ProjectMPrefsPerformance.mm in Sources */,
				AF100007AF100007AF100007 /* ProjectMPrefsTransitions.mm in Sources */,
				AF100009AF100009AF100009 /* ProjectMPrefsVisualization.mm in Sources */,
				AF10000BAF10000BAF10000B /* ProjectMPrefsPresets.mm in Sources */,
				AF10000DAF10000DAF10000D /* ProjectMPrefsDiagnostics.mm in Sources */,
```

- [ ] **Step 5: Build and deploy**

Run:
```bash
SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build
```

Expected: Build succeeds, foobar2000 launches. Open Preferences → Tools → projectMacOS and verify the five section nodes (Performance, Transitions, Visualization, Presets, Diagnostics) appear in the tree. Verify each page shows left-aligned labels and stretching controls.

- [ ] **Step 6: Commit**

```bash
git add mac/projectMacOS.xcodeproj/project.pbxproj
git commit -m "chore: add prefs section pages to Xcode target"
```
