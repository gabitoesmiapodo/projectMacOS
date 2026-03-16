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

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_visualization : public preferences_page_v2 {
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
