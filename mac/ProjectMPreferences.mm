#import "stdafx.h"
#import "ProjectMView.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface ProjectMPreferencesViewController : NSViewController
@end

@implementation ProjectMPreferencesViewController {
    NSButton *_debugLoggingCheckbox;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    _debugLoggingCheckbox = [NSButton checkboxWithTitle:@"Enable debug logging"
                                                target:self
                                                action:@selector(toggleDebugLogging:)];
    _debugLoggingCheckbox.state = cfg_debug_logging ? NSControlStateValueOn : NSControlStateValueOff;
    _debugLoggingCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_debugLoggingCheckbox];

    [NSLayoutConstraint activateConstraints:@[
        [_debugLoggingCheckbox.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_debugLoggingCheckbox.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
    ]];
}

- (void)toggleDebugLogging:(id)sender {
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
