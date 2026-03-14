#pragma once
#import <Cocoa/Cocoa.h>

// GUID is defined in pfc/pfc-lite.h (foobar2000 SDK). Mirror the definition here
// under the same guard so this header is self-contained for IDE analysis.
#ifndef GUID_DEFINED
#define GUID_DEFINED
struct GUID {
    uint32_t Data1;
    uint16_t Data2;
    uint16_t Data3;
    uint8_t  Data4[8];
} __attribute__((packed));
#endif

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
