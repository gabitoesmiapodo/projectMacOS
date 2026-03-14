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
