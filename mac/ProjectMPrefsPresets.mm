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
    NSTextField *folderLabel = [NSTextField labelWithString:@"Presets Source:"];
    [folderLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    _customPresetsFolderField = [[NSTextField alloc] init];
    _customPresetsFolderField.placeholderString = @"Default: /Documents/foobar2000/projectMacOS.zip";
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
    [stack addArrangedSubview:[self helpText:@"Override the default preset source with a folder of .milk files or a .zip archive. Leave empty to use the built-in collection."]];

    _sortOrderPopup = [self popupWithTitles:@[@"A-Z", @"Z-A"]
                                     values:@[@0, @1]
                               currentValue:(int)cfg_preset_sort_order
                                     action:@selector(sortOrderChanged:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Sort Order:" control:_sortOrderPopup]];
    [stack addArrangedSubview:[self helpText:@"Order of presets in the browser menu and initial playlist."]];

    [stack addArrangedSubview:[self spacer]];
    NSButton *reloadButton = [NSButton buttonWithTitle:@"Reload Presets"
                                                target:self
                                                action:@selector(reloadPresets:)];
    [stack addArrangedSubview:reloadButton];
    [stack addArrangedSubview:[self helpText:@"Force a full reload of presets from the current source. Also clears the extracted presets cache."]];

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
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select a folder containing .milk preset files, or a .zip archive";
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

- (void)reloadPresets:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:PMPresetIndexCachePath() error:nil];
    [fm removeItemAtPath:PMZipExtractionCachePath() error:nil];
    [fm removeItemAtPath:PMZipExtractionMetadataPath() error:nil];
    g_forcePresetReload = true;
    PMSettingsDidChange();
}

@end

#pragma clang diagnostic pop

namespace {

class preferences_page_presets : public preferences_page_v2 {
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
