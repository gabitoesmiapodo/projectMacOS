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

class preferences_page_performance : public preferences_page_v2 {
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
