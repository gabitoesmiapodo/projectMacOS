#pragma once
#import <Cocoa/Cocoa.h>

// kPrefsParentGUID: GUID for the "projectMacOS" parent preferences_page node.
// All five section pages return this from get_parent_guid().
// Defined in ProjectMPreferences.mm. GUID is from the foobar2000 SDK (stdafx.h).
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
