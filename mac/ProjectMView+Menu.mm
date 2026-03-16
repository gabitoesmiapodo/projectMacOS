#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"

#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UTCoreTypes.h>
#include <exception>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation ProjectMView (Menu)

- (void)enqueuePresetRequest:(PMPresetRequestType)request presetPath:(NSString *)presetPath {
    @synchronized (self) {
        _pendingPresetRequest = PMPresetRequestAfterEnqueue(_pendingPresetRequest, request);
        if (_pendingPresetRequest == PMPresetRequestTypeSelectPath) {
            _pendingPresetPath = [presetPath copy];
        } else {
            _pendingPresetPath = nil;
        }
    }
}

- (void)applyPresetSelectionPathInRenderLoop:(NSString *)presetPath {
    if (!_projectM || !_playlist) return;
    if (!presetPath || presetPath.length == 0) return;

    NSString *targetPath = [[presetPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
    uint32_t totalPresets = projectm_playlist_size(_playlist);
    uint32_t selectedIndex = 0;
    BOOL foundIndex = NO;

    if (totalPresets > 0) {
        char **items = projectm_playlist_items(_playlist, 0, totalPresets);
        for (uint32_t i = 0; items && items[i]; ++i) {
            NSString *candidatePath = @(items[i]);
            NSString *normalizedCandidate = [[candidatePath stringByStandardizingPath] stringByResolvingSymlinksInPath];
            if ([normalizedCandidate isEqualToString:targetPath]) {
                selectedIndex = i;
                foundIndex = YES;
                break;
            }
        }
        if (items) projectm_playlist_free_string_array(items);
    }

    if (foundIndex) {
        projectm_playlist_set_position(_playlist, selectedIndex, PMUseHardCutTransitions());
        [self refreshCurrentPresetName:selectedIndex];
        return;
    }

    bool inserted = false;
    try {
        inserted = projectm_playlist_add_preset(_playlist, [targetPath UTF8String], true);
    } catch (...) {
        inserted = false;
    }

    if (inserted) {
        uint32_t dynamicIndex = projectm_playlist_size(_playlist);
        if (dynamicIndex > 0) {
            dynamicIndex -= 1;
            projectm_playlist_set_position(_playlist, dynamicIndex, PMUseHardCutTransitions());
            [self refreshCurrentPresetName:dynamicIndex];
        }
    } else {
        [self loadDefaultPresetFallback];
    }
}

- (void)applyMenuTitleLimitToItem:(NSMenuItem *)item fullTitle:(NSString *)fullTitle {
    PMApplyMenuTitleLimit(item, fullTitle);
}

- (void)populatePresetMenu:(NSMenu *)menu atPath:(NSString *)directoryPath {
    [menu removeAllItems];

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:directoryPath isDirectory:&isDirectory] || !isDirectory) {
        NSMenuItem *missingItem = [menu addItemWithTitle:@"(Not found)" action:nil keyEquivalent:@""];
        missingItem.enabled = NO;
        return;
    }

    NSError *error = nil;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:directoryPath error:&error];
    if (!entries) {
        NSMenuItem *unavailableItem = [menu addItemWithTitle:@"(Unavailable)" action:nil keyEquivalent:@""];
        unavailableItem.enabled = NO;
        return;
    }

    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    NSMutableArray<NSString *> *presets = [NSMutableArray array];

    for (NSString *entry in entries) {
        if ([entry hasPrefix:@"."]) continue;

        NSString *fullPath = [directoryPath stringByAppendingPathComponent:entry];
        BOOL childIsDirectory = NO;
        if ([fm fileExistsAtPath:fullPath isDirectory:&childIsDirectory] && childIsDirectory) {
            [folders addObject:entry];
            continue;
        }

        if ([[[entry pathExtension] lowercaseString] isEqualToString:@"milk"]) {
            [presets addObject:entry];
        }
    }

    int sortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);
    if (sortOrder == 1) {
        [folders sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [b localizedCaseInsensitiveCompare:a];
        }];
        [presets sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [b localizedCaseInsensitiveCompare:a];
        }];
    } else {
        [folders sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        [presets sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    }

    for (NSString *folderName in folders) {
        NSString *folderPath = [directoryPath stringByAppendingPathComponent:folderName];
        NSMenuItem *folderItem = [menu addItemWithTitle:folderName action:nil keyEquivalent:@""];
        [self applyMenuTitleLimitToItem:folderItem fullTitle:folderName];
        NSMenu *submenu = [[NSMenu alloc] initWithTitle:folderName];
        submenu.delegate = self;
        objc_setAssociatedObject(submenu, kPresetMenuPathKey, folderPath, OBJC_ASSOCIATION_COPY_NONATOMIC);
        folderItem.submenu = submenu;
    }

    if (folders.count > 0 && presets.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
    }

    auto savedName = cfg_preset_name.get();
    NSString *currentPresetFilename = savedName.length() > 0 ? [[@(savedName.get_ptr()) lastPathComponent] lowercaseString] : nil;

    for (NSString *presetFilename in presets) {
        NSString *presetPath = [directoryPath stringByAppendingPathComponent:presetFilename];
        NSString *displayName = [presetFilename stringByDeletingPathExtension];
        NSMenuItem *presetItem = [menu addItemWithTitle:displayName
                                                  action:@selector(selectPresetFromMenuItem:)
                                           keyEquivalent:@""];
        presetItem.target = self;
        presetItem.representedObject = presetPath;
        [self applyMenuTitleLimitToItem:presetItem fullTitle:displayName];
        presetItem.toolTip = PMPresetMenuItemToolTipForPresetPath(presetPath, [self presetsDirectoryPath]);
        if (currentPresetFilename && [[presetFilename lowercaseString] isEqualToString:currentPresetFilename]) {
            presetItem.state = NSControlStateValueOn;
        }
    }

    if (folders.count == 0 && presets.count == 0) {
        NSMenuItem *emptyItem = [menu addItemWithTitle:@"(Empty)" action:nil keyEquivalent:@""];
        emptyItem.enabled = NO;
    }
}

- (void)selectPresetFromMenuItem:(id)sender {
    if (!_projectM || !_playlist) return;

    NSMenuItem *item = (NSMenuItem *)sender;
    NSString *presetPath = [item.representedObject isKindOfClass:[NSString class]] ? (NSString *)item.representedObject : nil;
    if (!presetPath || presetPath.length == 0) return;

    [self disableAutoplay];
    [self enqueuePresetRequest:PMPresetRequestTypeSelectPath presetPath:presetPath];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSString *menuPath = objc_getAssociatedObject(menu, kPresetMenuPathKey);
    if (![menuPath isKindOfClass:[NSString class]]) return;
    [self populatePresetMenu:menu atPath:menuPath];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (self->_isAutoPaused && !self->_isVisualizationPaused) {
        // Auto-paused but not manually paused: clear auto-pause directly without
        // toggling _isVisualizationPaused, which would leave the view stuck paused
        // after auto-unpause on playback resume.
        self->_isAutoPaused = NO;
        self->_lastRenderTimestamp = 0;
        if (self->_displayLink && !CVDisplayLinkIsRunning(self->_displayLink)) {
            CVDisplayLinkStart(self->_displayLink);
        }
        return;
    }

    if (self->_isVisualizationPaused) {
        [self togglePausePlayback:nil];
        return;
    }

    if (event.clickCount == 2) {
        [self toggleVisualizationFullScreen];
        return;
    }

    [super mouseDown:event];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53 && [self isInFullScreenMode]) {
        [self toggleVisualizationFullScreen];
        return;
    }
    [super keyDown:event];
}

- (void)cancelOperation:(id)sender {
    if ([self isInFullScreenMode]) {
        [self toggleVisualizationFullScreen];
        return;
    }
    [super cancelOperation:sender];
}

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [self buildContextMenu];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"projectMacOS"];

    NSMenuItem *currentPreset = [menu addItemWithTitle:[self currentPresetDisplayName]
                                                action:nil
                                         keyEquivalent:@""];
    currentPreset.enabled = NO;
    [self applyMenuTitleLimitToItem:currentPreset fullTitle:[self currentPresetDisplayName]];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fullscreen = [menu addItemWithTitle:@"Toggle Full-Screen Mode"
                                             action:@selector(toggleVisualizationFullScreen)
                                      keyEquivalent:@""];
    fullscreen.target = self;
    fullscreen.state = [self isInFullScreenMode] ? NSControlStateValueOn : NSControlStateValueOff;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *presetBrowser = [menu addItemWithTitle:@"Presets"
                                                action:nil
                                         keyEquivalent:@""];
    [self applySystemSymbol:@"music.note.list" toMenuItem:presetBrowser];
    NSMenu *presetMenu = [[NSMenu alloc] initWithTitle:@"Presets"];
    presetMenu.delegate = self;
    objc_setAssociatedObject(presetMenu, kPresetMenuPathKey, [self presetsDirectoryPath], OBJC_ASSOCIATION_COPY_NONATOMIC);
    presetBrowser.submenu = presetMenu;

    [menu addItem:[NSMenuItem separatorItem]];

NSMenuItem *pause = [menu addItemWithTitle:PMPauseMenuTitle(_isVisualizationPaused)
                                         action:@selector(togglePausePlayback:)
                                  keyEquivalent:@""];
    pause.target = self;
    [self applySystemSymbol:PMPauseMenuSymbolName(_isVisualizationPaused) toMenuItem:pause];

    NSMenuItem *prev = [menu addItemWithTitle:@"Previous"
                                       action:@selector(previousPreset:)
                                keyEquivalent:@""];
    prev.target = self;
    [self applySystemSymbol:@"backward.fill" toMenuItem:prev];

    NSMenuItem *next = [menu addItemWithTitle:@"Next"
                                       action:@selector(nextPreset:)
                                keyEquivalent:@""];
    next.target = self;
    [self applySystemSymbol:@"forward.fill" toMenuItem:next];

    NSMenuItem *random = [menu addItemWithTitle:@"Random Pick"
                                          action:@selector(randomPreset:)
                                   keyEquivalent:@""];
    random.target = self;
    [self applySystemSymbol:@"shuffle" toMenuItem:random];

    [menu addItem:[NSMenuItem separatorItem]];

    // MARK: Favorites submenu
    NSMenuItem *favoritesItem = [menu addItemWithTitle:@"Favorites" action:nil keyEquivalent:@""];
    NSMenu *favoritesMenu = [[NSMenu alloc] initWithTitle:@"Favorites"];

    // --- Save Current ---
    NSMenuItem *saveCurrentItem = [favoritesMenu addItemWithTitle:@"Add Current Preset"
                                                           action:@selector(saveCurrentToFavorites:)
                                                    keyEquivalent:@""];
    saveCurrentItem.target = self;

    NSString *currentPath = @(cfg_preset_name.get().get_ptr());
    NSString *currentName = [currentPath lastPathComponent];

    static NSSet<NSString *> *sentinelNames = nil;
    static dispatch_once_t sentinelToken;
    dispatch_once(&sentinelToken, ^{
        sentinelNames = [NSSet setWithArray:@[@"idle://", @"fallback-default.milk", @"projectMacOS.milk"]];
    });

    BOOL hasActivePreset = currentName.length > 0 && ![sentinelNames containsObject:currentPath];
    BOOL isAlreadyFavorite = hasActivePreset && PMFavoritesContainsName(self.loadedFavorites, currentName);

    if (!hasActivePreset || isAlreadyFavorite) {
        saveCurrentItem.enabled = NO;
        if (isAlreadyFavorite) {
            saveCurrentItem.toolTip = @"Already in Favorites";
        }
    }

    // --- Manage submenu ---
    NSMenuItem *manageItem = [favoritesMenu addItemWithTitle:@"Manage" action:nil keyEquivalent:@""];
    NSMenu *manageMenu = [[NSMenu alloc] initWithTitle:@"Manage"];

    NSMenuItem *saveListItem = [manageMenu addItemWithTitle:@"Save List"
                                                     action:@selector(saveFavoritesList:)
                                              keyEquivalent:@""];
    saveListItem.target = self;

    NSMenuItem *loadListItem = [manageMenu addItemWithTitle:@"Load List"
                                                     action:@selector(loadFavoritesList:)
                                              keyEquivalent:@""];
    loadListItem.target = self;
    manageItem.submenu = manageMenu;

    [favoritesMenu addItem:[NSMenuItem separatorItem]];

    // --- Favorites list ---
    NSMutableArray<NSDictionary *> *favorites = self.loadedFavorites;

    if (favorites.count == 0) {
        NSMenuItem *emptyItem = [favoritesMenu addItemWithTitle:@"No favorites yet"
                                                         action:nil
                                                  keyEquivalent:@""];
        emptyItem.enabled = NO;
    } else {
        for (NSDictionary *entry in favorites) {
            NSString *displayName = PMFavoriteDisplayName(entry);
            NSMenuItem *favItem = [favoritesMenu addItemWithTitle:displayName
                                                           action:nil
                                                    keyEquivalent:@""];
            [self applyMenuTitleLimitToItem:favItem fullTitle:displayName];

            if ([currentName isEqualToString:entry[@"name"]]) {
                favItem.state = NSControlStateValueOn;
            }

            NSMenu *favSubmenu = [[NSMenu alloc] initWithTitle:displayName];

            NSMenuItem *loadItem = [favSubmenu addItemWithTitle:@"Load"
                                                         action:@selector(loadFavoriteFromMenuItem:)
                                                  keyEquivalent:@""];
            loadItem.target = self;
            loadItem.representedObject = entry;

            NSMenuItem *removeItem = [favSubmenu addItemWithTitle:@"Remove"
                                                           action:@selector(removeFavoriteFromMenuItem:)
                                                    keyEquivalent:@""];
            removeItem.target = self;
            removeItem.representedObject = entry;

            favItem.submenu = favSubmenu;
        }
    }

    favoritesItem.submenu = favoritesMenu;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *shuffle = [menu addItemWithTitle:@"Shuffle Presets"
                                          action:@selector(toggleShuffle:)
                                   keyEquivalent:@""];
    shuffle.target = self;
    shuffle.state = cfg_preset_shuffle ? NSControlStateValueOn : NSControlStateValueOff;

    // MARK: Cycle Favorites submenu
    PMCycleFavoritesMode currentCycleMode = PMValidatedCycleFavoritesMode((int)cfg_cycle_favorites_mode);
    NSUInteger favCount = self.loadedFavorites.count;
    BOOL cycleFavsDisabled = PMShouldDisableCycleFavoritesMenu(favCount);

    NSMenuItem *cycleFavoritesItem = [menu addItemWithTitle:@"Cycle Favorites"
                                                     action:nil
                                              keyEquivalent:@""];
    if (cycleFavsDisabled) {
        cycleFavoritesItem.enabled = NO;
        cycleFavoritesItem.toolTip = @"No favorites added yet";
    }

    NSMenu *cycleMenu = [[NSMenu alloc] initWithTitle:@"Cycle Favorites"];

    NSMenuItem *disabledItem = [cycleMenu addItemWithTitle:@"Disabled"
                                                    action:@selector(setCycleFavoritesMode:)
                                             keyEquivalent:@""];
    disabledItem.target = self;
    disabledItem.tag = PMCycleFavoritesModeOff;
    disabledItem.state = (currentCycleMode == PMCycleFavoritesModeOff) ? NSControlStateValueOn : NSControlStateValueOff;

    [cycleMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *ascItem = [cycleMenu addItemWithTitle:@"Ascending"
                                               action:@selector(setCycleFavoritesMode:)
                                        keyEquivalent:@""];
    ascItem.target = self;
    ascItem.tag = PMCycleFavoritesModeAscending;
    ascItem.state = (currentCycleMode == PMCycleFavoritesModeAscending) ? NSControlStateValueOn : NSControlStateValueOff;

    NSMenuItem *descItem = [cycleMenu addItemWithTitle:@"Descending"
                                                action:@selector(setCycleFavoritesMode:)
                                         keyEquivalent:@""];
    descItem.target = self;
    descItem.tag = PMCycleFavoritesModeDescending;
    descItem.state = (currentCycleMode == PMCycleFavoritesModeDescending) ? NSControlStateValueOn : NSControlStateValueOff;

    NSMenuItem *randItem = [cycleMenu addItemWithTitle:@"Random"
                                                action:@selector(setCycleFavoritesMode:)
                                         keyEquivalent:@""];
    randItem.target = self;
    randItem.tag = PMCycleFavoritesModeRandom;
    randItem.state = (currentCycleMode == PMCycleFavoritesModeRandom) ? NSControlStateValueOn : NSControlStateValueOff;

    cycleFavoritesItem.submenu = cycleMenu;

    NSMenu *durationMenu = [[NSMenu alloc] initWithTitle:@"Delay"];
    int selectedDuration = PMValidatedPresetDuration((int)cfg_preset_duration);
    for (NSNumber *option in PMPresetDurationOptions()) {
        int d = option.intValue;
        NSString *title = (d == 60) ? @"1m" : [NSString stringWithFormat:@"%ds", d];
        NSMenuItem *item = [durationMenu addItemWithTitle:title
                                                   action:@selector(setDuration:)
                                            keyEquivalent:@""];
        item.target = self;
        item.tag = d;
        if (d == selectedDuration)
            item.state = NSControlStateValueOn;
    }
    NSMenuItem *durationItem = [menu addItemWithTitle:@"Delay"
                                               action:nil
                                        keyEquivalent:@""];
    durationItem.submenu = durationMenu;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *helpItem = [menu addItemWithTitle:@"Help"
                                           action:@selector(showHelp:)
                                    keyEquivalent:@""];
    helpItem.target = self;

    return menu;
}

- (void)applySystemSymbol:(NSString *)symbolName toMenuItem:(NSMenuItem *)item {
    if (!symbolName || !item) return;

    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    if (!image) return;

    [image setTemplate:YES];
    item.image = image;
}

- (void)togglePausePlayback:(id)sender {
    (void)sender;

    BOOL nowPaused;
    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    BOOL contextLocked = NO;
    @try {
        if (cglContext) {
            CGLLockContext(cglContext);
            contextLocked = YES;
        }

        _isVisualizationPaused = !_isVisualizationPaused;
        nowPaused = _isVisualizationPaused;
        if (!_isVisualizationPaused) {
            _isAutoPaused = NO;
        }

        if (!nowPaused) {
            _lastRenderTimestamp = 0;
        }

        if (_projectM) {
            projectm_set_preset_locked(_projectM, PMShouldLockPreset(cfg_preset_shuffle, _isVisualizationPaused, _isAudioPlaybackActive, cfg_hard_cuts));
        }

        if (contextLocked) {
            CGLUnlockContext(cglContext);
            contextLocked = NO;
        }
    }
    @catch (NSException *exception) {
        PMLogError("projectM: Objective-C exception in togglePausePlayback: ", [[exception description] UTF8String]);
        if (contextLocked) {
            CGLUnlockContext(cglContext);
        }
        return;
    }

    if (nowPaused) {
        if (_displayLink) {
            CVDisplayLinkStop(_displayLink);
        }
    } else {
        if (_displayLink) {
            CVReturn status = CVDisplayLinkStart(_displayLink);
            if (status != kCVReturnSuccess) {
                PMLogError("projectM: CVDisplayLinkStart() failed on unpause.");
            }
        }
    }
}

- (void)showHelp:(id)sender {
    (void)sender;
    BOOL darkMode = NO;
    if (@available(macOS 10.14, *)) {
        NSAppearance *appearance = self.effectiveAppearance ?: NSApp.effectiveAppearance;
        NSString *bestAppearance = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        darkMode = [bestAppearance isEqualToString:NSAppearanceNameDarkAqua];
    }

    NSString *textColor = PMHelpTextColorHex(darkMode);
    NSString *backgroundColor = PMHelpBackgroundColorHex(darkMode);
    NSString *preBackgroundColor = darkMode ? @"#1a1a1a" : @"#f5f5f5";
    NSString *preBorderColor = darkMode ? @"#3a3a3a" : @"#dddddd";
    NSString *separatorColor = darkMode ? @"#4a4a4a" : @"#cccccc";
    NSString *linkColor = darkMode ? @"#8ab4ff" : @"#0645ad";

    NSString *helpHTML = [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset='utf-8'><style>"
         "body{font-family:-apple-system,Helvetica,sans-serif;font-size:14px;line-height:1.45;color:%@;background:%@;margin:0;padding:0;}"
         "h1{font-size:28px;margin:0 0 14px 0;}"
         "h2{font-size:20px;margin:24px 0 10px 0;font-weight:700;}"
         "p{margin:0 0 12px 0;}"
         "strong{font-weight:700;}"
         "ul{margin:0 0 14px 20px;padding:0;}"
         "li{margin:0 0 6px 0;}"
         "pre{font-family:Menlo,Monaco,monospace;font-size:12px;color:%@;background:%@;border:1px solid %@;border-radius:6px;padding:10px;white-space:pre;overflow-x:auto;margin:8px 0 14px 0;}"
         "hr{border:0;border-top:1px solid %@;margin:16px 0;}"
         "a{color:%@;text-decoration:underline;}"
         "</style></head><body>"
         "<h1>projectMacOS</h1>"
         "<p>Open-source music visualizer for <a href='https://www.foobar2000.org'>foobar2000</a> on MacOS.</p>"
         "<p>Full instructions on how to install and use the plugin are available at <a href='https://github.com/gabitoesmiapodo/projectMacOS'>https://github.com/gabitoesmiapodo/projectMacOS</a></p>"
         "<h2>Layout</h2>"
         "<p>Add the <strong>projectMacOS</strong> component in your preferred location in the layout (View / Layout / Edit Layout)</p>"
         "<p><strong>You can use this template:</strong></p>"
         "<pre>splitter horizontal style=thin\n splitter vertical style=thin\n  splitter horizontal style=thin\n   albumlist\n   albumart type=\"front cover\"\n  splitter horizontal style=thin\n   playlist\n   projectMacOS\n playback-controls</pre>"
         "<br>"
         "<h2>How to use</h2>"
         "<p>Once added to the layout, these are the available controls:</p>"
         "<p>&bull; Right click / Presets to browse and load presets.</p>"
         "<p>&bull; Pause / Resume freezes or resumes the current visualization.</p>"
         "<p>&bull; Previous / Next buttons to switch between presets.</p>"
         "<p>&bull; Random Pick button to load a random preset.</p>"
         "<p>&bull; Right click / Favorites to save presets to your favorites list and quickly reload them.</p>"
         "<p>&bull; Shuffle Presets on / off to enable / disable random preset switching after a set amount of time (configurable via Delay).</p>"
         "<p>&bull; Cycle Favorites to automatically cycle through your saved favorites in Ascending, Descending, or Random order, using the same delay interval. Enabling this disables Shuffle, and vice versa. Any manual preset selection stops cycling.</p>"
         "<p>&bull; Double-click to toggle visualization's fullscreen mode.</p>"
         "<p>&bull; Press ESC to exit fullscreen.</p>"
         "<hr>"
         "<p><strong>This project is distributed under the GNU Lesser General Public License v2.1.</strong></p>"
         "</body></html>",
         textColor,
         backgroundColor,
         textColor,
         preBackgroundColor,
         preBorderColor,
         separatorColor,
         linkColor];

    if (!_helpWindow || !_helpTextView) {
        NSRect frame = NSMakeRect(0, 0, 980, 700);
        _helpWindow = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        [_helpWindow setReleasedWhenClosed:NO];
        _helpWindow.delegate = self;
        [_helpWindow setTitle:@"projectMacOS Help"];

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:[[_helpWindow contentView] bounds]];
        scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scrollView.hasVerticalScroller = YES;
        scrollView.hasHorizontalScroller = YES;

        NSTextView *textView = [[NSTextView alloc] initWithFrame:[scrollView bounds]];
        textView.editable = NO;
        textView.selectable = YES;
        textView.richText = YES;
        textView.drawsBackground = YES;
        textView.usesFindPanel = YES;
        textView.usesFontPanel = NO;
        textView.automaticQuoteSubstitutionEnabled = NO;
        textView.automaticDataDetectionEnabled = YES;
        textView.textContainerInset = NSMakeSize(8.0, 8.0);
        textView.minSize = NSMakeSize(0.0, 0.0);
        textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        textView.verticallyResizable = YES;
        textView.horizontallyResizable = YES;
        textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [[textView textContainer] setWidthTracksTextView:NO];

        scrollView.documentView = textView;
        _helpTextView = textView;
        [[_helpWindow contentView] addSubview:scrollView];
    }

    _helpTextView.drawsBackground = YES;
    _helpTextView.backgroundColor = darkMode ? [NSColor blackColor] : [NSColor whiteColor];

    if ([_helpTextView isKindOfClass:[NSTextView class]]) {
        NSAttributedString *renderedHelp = nil;
        NSData *htmlData = [helpHTML dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *options = @{
            NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
            NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding),
            NSBaseURLDocumentOption: [NSURL URLWithString:@"https://github.com/gabitoesmiapodo/projectMacOS"]
        };
        renderedHelp = [[NSAttributedString alloc] initWithData:htmlData
                                                         options:options
                                              documentAttributes:nil
                                                           error:&error];
        if (!renderedHelp && error) {
            PMLogError("projectM: help HTML parse failed: ", [[error localizedDescription] UTF8String]);
        }

        if (renderedHelp) {
            [[_helpTextView textStorage] setAttributedString:renderedHelp];
        }
    }

    [_helpWindow center];
    [_helpWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == _helpWindow) {
        _helpTextView = nil;
        _helpWindow = nil;
    }
}

- (void)cleanupHelpWindow {
    if (!_helpWindow) {
        _helpTextView = nil;
        return;
    }

    _helpWindow.delegate = nil;
    [_helpWindow orderOut:nil];
    [_helpWindow close];
    _helpTextView = nil;
    _helpWindow = nil;
}

- (void)toggleVisualizationFullScreen {
    if ([self isInFullScreenMode]) {
        [self exitFullScreenModeWithOptions:nil];
        return;
    }

    NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
    if (!screen) return;

    [self enterFullScreenMode:screen withOptions:PMVisualizationFullScreenOptions()];
    [self.window makeFirstResponder:self];
}

- (void)toggleShuffle:(id)sender {
    BOOL wasShuffleEnabled = cfg_preset_shuffle;
    cfg_preset_shuffle = !cfg_preset_shuffle;
    BOOL shouldResetShuffleTimer = PMShouldResetShuffleTimerOnToggle(wasShuffleEnabled, cfg_preset_shuffle);

    if (shouldResetShuffleTimer && _isAudioPlaybackActive) {
        _pendingShuffleEnable = YES;
        _shuffleEnableDeadline = CFAbsoluteTimeGetCurrent() + (double)PMValidatedPresetDuration((int)cfg_preset_duration);
    } else if (!cfg_preset_shuffle) {
        _pendingShuffleEnable = NO;
        _shuffleEnableDeadline = 0.0;
    }

    if (cfg_preset_shuffle && cfg_cycle_favorites_mode != PMCycleFavoritesModeOff) {
        @synchronized (self) {
            cfg_cycle_favorites_mode = PMCycleFavoritesModeOff;
            _cycleFavoritesActive = NO;
            _cycleFavoritesDeadline = 0.0;
        }
    }
}

- (void)nextPreset:(id)sender {
    (void)sender;
    if (!_projectM || !_playlist) return;
    [self disableAutoplay];
    [self enqueuePresetRequest:PMPresetRequestTypeNext presetPath:nil];
}

- (void)previousPreset:(id)sender {
    (void)sender;
    if (!_projectM || !_playlist) return;
    [self disableAutoplay];
    [self enqueuePresetRequest:PMPresetRequestTypePrevious presetPath:nil];
}

- (void)randomPreset:(id)sender {
    (void)sender;
    if (!_projectM || !_playlist) return;
    [self disableAutoplay];
    [self enqueuePresetRequest:PMPresetRequestTypeRandom presetPath:nil];
}

- (void)processPendingPresetRequestInRenderLoop {
    PMPresetRequestType request = PMPresetRequestTypeNone;
    NSString *presetPath = nil;

    @synchronized (self) {
        request = _pendingPresetRequest;
        if (request == PMPresetRequestTypeSelectPath) {
            presetPath = [_pendingPresetPath copy];
        }
        _pendingPresetRequest = PMPresetRequestTypeNone;
        _pendingPresetPath = nil;
    }

    if (request == PMPresetRequestTypeNone || !_projectM || !_playlist) return;
    if (projectm_playlist_size(_playlist) == 0) return;

    @try {
        switch (request) {
            case PMPresetRequestTypeNext:
                projectm_playlist_play_next(_playlist, PMUseHardCutTransitions());
                break;
            case PMPresetRequestTypePrevious:
                projectm_playlist_play_previous(_playlist, PMUseHardCutTransitions());
                break;
            case PMPresetRequestTypeRandom: {
                bool restoreShuffle = _playlistShuffleEnabled;
                projectm_playlist_set_shuffle(_playlist, true);
                projectm_playlist_play_next(_playlist, PMUseHardCutTransitions());
                projectm_playlist_set_shuffle(_playlist, restoreShuffle);
                break;
            }
            case PMPresetRequestTypeSelectPath:
                [self applyPresetSelectionPathInRenderLoop:presetPath];
                break;
            case PMPresetRequestTypeNone:
                break;
        }
    }
    @catch (NSException *exception) {
        PMLogError("projectM: Objective-C exception while processing preset request: ", [[exception description] UTF8String]);
    }
}

- (void)setDuration:(id)sender {
    NSMenuItem *item = (NSMenuItem *)sender;
    cfg_preset_duration = PMValidatedPresetDuration((int)item.tag);
    if (_pendingShuffleEnable) {
        _shuffleEnableDeadline = CFAbsoluteTimeGetCurrent() + (double)cfg_preset_duration;
    }
    if (!_projectM) return;

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    if (cglContext) {
        CGLLockContext(cglContext);
        [[self openGLContext] makeCurrentContext];
    }

    projectm_set_preset_duration(_projectM, (double)cfg_preset_duration);

    if (cglContext) {
        CGLUnlockContext(cglContext);
    }
}

- (NSMutableArray<NSDictionary *> *)loadedFavorites {
    if (!_favorites) {
        NSString *json = @(cfg_preset_favorites.get().get_ptr());
        _favorites = PMFavoritesDeserialize(json);
    }
    return _favorites;
}

- (void)persistFavorites {
    PMFavoritesSortInPlace(self.loadedFavorites);
    NSString *json = PMFavoritesSerialize(self.loadedFavorites);
    cfg_preset_favorites = json ? [json UTF8String] : "";

    PMCycleFavoritesMode cycleMode = PMValidatedCycleFavoritesMode((int)cfg_cycle_favorites_mode);
    if (cycleMode != PMCycleFavoritesModeOff) {
        [self rebuildResolvedCyclePaths];
        @synchronized (self) {
            NSArray<NSString *> *paths = _resolvedCyclePaths;
            if (paths.count == 0) {
                cfg_cycle_favorites_mode = PMCycleFavoritesModeOff;
                _cycleFavoritesActive = NO;
                _cycleFavoritesDeadline = 0.0;
            } else {
                if (cycleMode == PMCycleFavoritesModeRandom) {
                    _cycleFavoritesRandomOrder = PMBuildRandomFavoritesOrder(paths.count);
                    _cycleFavoritesRandomPosition = NSNotFound;
                } else if ((NSUInteger)_cycleFavoritesIndex >= paths.count) {
                    _cycleFavoritesIndex = (cycleMode == PMCycleFavoritesModeDescending)
                        ? (NSInteger)(paths.count - 1)
                        : 0;
                }
            }
        }
    }
}

- (BOOL)isCurrentPresetAFavorite {
    NSString *current = @(cfg_preset_name.get().get_ptr());
    NSString *name = [current lastPathComponent];
    if (name.length == 0) return NO;
    return PMFavoritesContainsName(self.loadedFavorites, name);
}

- (void)saveCurrentToFavorites:(id)sender {
    (void)sender;
    NSString *fullPath = _currentPresetPath ?: @(cfg_preset_name.get().get_ptr());
    NSString *name = [fullPath lastPathComponent];
    if (name.length == 0) return;
    if (PMFavoritesContainsName(self.loadedFavorites, name)) return;

    NSString *presetsDir = [self presetsDirectoryPath];
    NSString *storedPath = PMFavoriteStoredPathForFullPath(fullPath, presetsDir);
    if (storedPath.length == 0) storedPath = fullPath;

    [self.loadedFavorites addObject:@{@"name": name, @"path": storedPath}];
    [self persistFavorites];
}

- (void)loadFavoriteEntry:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) return;
    id rawPath = entry[@"path"];
    NSString *path = [rawPath isKindOfClass:[NSString class]] ? (NSString *)rawPath : @"";
    if (path.length == 0) return;

    if (![path hasPrefix:@"/"]) {
        path = [[self presetsDirectoryPath] stringByAppendingPathComponent:path];
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString *displayPath = entry[@"path"] ?: entry[@"name"] ?: @"(unknown)";
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Preset couldn't be found in \"%@\".", displayPath];
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    [self disableAutoplay];
    [self enqueuePresetRequest:PMPresetRequestTypeSelectPath presetPath:path];
}

- (void)loadFavoriteFromMenuItem:(id)sender {
    NSDictionary *entry = [(NSMenuItem *)sender representedObject];
    if (![entry isKindOfClass:[NSDictionary class]]) return;
    [self loadFavoriteEntry:entry];
}

- (void)removeFavoriteFromMenuItem:(id)sender {
    NSDictionary *entry = [(NSMenuItem *)sender representedObject];
    if (![entry isKindOfClass:[NSDictionary class]]) return;
    [self promptRemoveFavoriteEntry:entry];
}

- (void)promptRemoveFavoriteEntry:(NSDictionary *)entry {
    NSString *displayName = PMFavoriteDisplayName(entry);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Remove \"%@\" from Favorites?", displayName];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = entry[@"name"] ?: @"";
    NSInteger idx = PMFavoritesIndexOfName(self.loadedFavorites, name);
    if (idx >= 0) {
        [self.loadedFavorites removeObjectAtIndex:(NSUInteger)idx];
        [self persistFavorites];
    }
}

- (void)saveFavoritesList:(id)sender {
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.nameFieldStringValue = @"favorites.json";
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *json = PMFavoritesSerialize(self.loadedFavorites);
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSError *error = nil;
    if (![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
        PMLogError("projectM: favorites export failed: ",
                   [[error localizedDescription] UTF8String]);
    }
}

- (void)disableAutoplay {
    cfg_preset_shuffle = false;
    _pendingShuffleEnable = NO;
    _shuffleEnableDeadline = 0.0;
    @synchronized (self) {
        cfg_cycle_favorites_mode = PMCycleFavoritesModeOff;
        _cycleFavoritesActive = NO;
        _cycleFavoritesDeadline = 0.0;
    }
}

- (void)rebuildResolvedCyclePaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *presetsDir = [self presetsDirectoryPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSDictionary *entry in self.loadedFavorites) {
        id rawPath = entry[@"path"];
        if (![rawPath isKindOfClass:[NSString class]] || [(NSString *)rawPath length] == 0) continue;
        NSString *path = (NSString *)rawPath;
        if (![path hasPrefix:@"/"]) {
            path = [presetsDir stringByAppendingPathComponent:path];
        }
        if (![fm fileExistsAtPath:path]) continue;
        [paths addObject:path];
    }
    @synchronized (self) { _resolvedCyclePaths = [paths copy]; }
}

- (void)setCycleFavoritesMode:(id)sender {
    NSMenuItem *item = (NSMenuItem *)sender;
    if (item.tag < PMCycleFavoritesModeOff || item.tag > PMCycleFavoritesModeRandom) return;
    PMCycleFavoritesMode tappedMode = (PMCycleFavoritesMode)item.tag;
    PMCycleFavoritesMode currentMode = PMValidatedCycleFavoritesMode((int)cfg_cycle_favorites_mode);

    if (tappedMode == PMCycleFavoritesModeOff || tappedMode == currentMode) {
        @synchronized (self) {
            cfg_cycle_favorites_mode = PMCycleFavoritesModeOff;
            _cycleFavoritesActive = NO;
            _cycleFavoritesDeadline = 0.0;
        }
        return;
    }

    // Disable shuffle
    cfg_preset_shuffle = false;
    _pendingShuffleEnable = NO;
    _shuffleEnableDeadline = 0.0;

    [self rebuildResolvedCyclePaths];

    @synchronized (self) {
        NSArray<NSString *> *paths = _resolvedCyclePaths;
        if (paths.count == 0) {
            cfg_cycle_favorites_mode = PMCycleFavoritesModeOff;
            _cycleFavoritesActive = NO;
            _cycleFavoritesDeadline = 0.0;
            return;
        }

        cfg_cycle_favorites_mode = (int)tappedMode;

        if (tappedMode == PMCycleFavoritesModeAscending) {
            _cycleFavoritesIndex = 0;
            [self enqueuePresetRequest:PMPresetRequestTypeSelectPath presetPath:paths[0]];
        } else if (tappedMode == PMCycleFavoritesModeDescending) {
            _cycleFavoritesIndex = (NSInteger)(paths.count - 1);
            [self enqueuePresetRequest:PMPresetRequestTypeSelectPath presetPath:paths[paths.count - 1]];
        } else {
            // Random: build a random order, start at position 0, and immediately select the first randomized favorite
            _cycleFavoritesRandomOrder = PMBuildRandomFavoritesOrder(paths.count);
            _cycleFavoritesRandomPosition = 0;
            _cycleFavoritesIndex = [_cycleFavoritesRandomOrder[0] integerValue];
            [self enqueuePresetRequest:PMPresetRequestTypeSelectPath presetPath:paths[(NSUInteger)_cycleFavoritesIndex]];
        }

        _cycleFavoritesActive = YES;
        _cycleFavoritesDeadline = CFAbsoluteTimeGetCurrent() + (double)PMValidatedPresetDuration((int)cfg_preset_duration);
    }
}

- (void)loadFavoritesList:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return;

    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:panel.URL options:0 error:&error];
    if (!data) {
        PMLogError("projectM: favorites import read failed: ",
                   [[error localizedDescription] UTF8String]);
        return;
    }

    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSMutableArray *imported = PMFavoritesDeserialize(json);

    NSUInteger added = 0, skipped = 0;
    for (NSDictionary *entry in imported) {
        if (!PMFavoriteImportEntryIsValid(entry)) { skipped++; continue; }
        if (PMFavoritesContainsName(self.loadedFavorites, entry[@"name"])) { skipped++; continue; }
        [self.loadedFavorites addObject:entry];
        added++;
    }

    if (added > 0) [self persistFavorites];

    PMLog("projectM: favorites import: ",
          [[NSString stringWithFormat:@"%lu added, %lu skipped",
            (unsigned long)added, (unsigned long)skipped] UTF8String]);
}

@end

#pragma clang diagnostic pop
