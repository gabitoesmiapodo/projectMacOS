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
