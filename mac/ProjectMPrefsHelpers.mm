#import "stdafx.h"
#import "ProjectMPrefsParent.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation NSViewController (PMPrefsHelpers)

- (NSStackView *)rowWithLabel:(NSString *)labelText control:(NSView *)control {
    NSTextField *label = [NSTextField labelWithString:labelText];
    label.alignment = NSTextAlignmentLeft;
    [label setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[label, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    return row;
}

- (NSTextField *)helpText:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSView *)spacer {
    NSView *view = [[NSView alloc] init];
    [view.heightAnchor constraintEqualToConstant:8].active = YES;
    return view;
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

@end

#pragma clang diagnostic pop
