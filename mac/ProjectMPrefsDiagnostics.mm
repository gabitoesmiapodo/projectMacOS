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
