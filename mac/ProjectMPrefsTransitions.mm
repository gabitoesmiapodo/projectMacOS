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
    _softCutDurationPopup.enabled = !cfg_hard_cuts;
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
    _softCutDurationPopup.enabled = !cfg_hard_cuts;
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

class preferences_page_transitions : public preferences_page_v2 {
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
