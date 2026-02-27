# Refactor Design: Modularize projectMacOS_mac.mm

Date: 2026-02-26

## Goal

Refactor the monolithic 1244-line `mac/projectMacOS_mac.mm` into responsibility-based modules, add crash logging, XCTest coverage for pure logic, fix the deploy script, and update gitignore/CLAUDE.md.

## Constraints

Do not modify: `deps/`, `mac/zipfs/`, images, `README.md`, `LICENSE.md`.

## Module Split

### ProjectMView.h (shared header, ~50 lines)

- `@interface ProjectMView : NSOpenGLView` with all public ivars
- Method declarations used across categories
- `extern` declarations for `cfg_preset_shuffle`, `cfg_preset_name`, `cfg_preset_duration`
- Constants (`kPresetMenuPathKey`)

### ProjectMView.mm (core rendering, ~200 lines)

- `initWithFrame:`, `dealloc`, `renderFrame`, `addPCM`, `reshape`, `getDrawableSizeWidth:height:`
- CVDisplayLink callback (static function, same file)

### ProjectMView+Presets.mm (preset lifecycle, ~250 lines)

- `projectMacOSDataDirectoryPath`, `projectMacOSZipPath`, `zipExtractionDirectoryPath`
- `isDirectoryPresetContainer:`, `normalizedSingleTopLevelDirectoryForRoot:`
- `prepareDataDirectoryFromZipAtPath:`, `resolvedDataDirectoryPathUsedZip:`
- `loadDefaultPresetFallback`, `loadPresetsFromCurrentSource`
- `presetsDirectoryPath`, `currentPresetDisplayName`, `refreshCurrentPresetName:showOverlay:`
- `callbackPresetSwitched` (static C callback)

### ProjectMView+Menu.mm (UI and interaction, ~450 lines)

- `buildContextMenu`, `populatePresetMenu:atPath:`, `selectPresetFromMenuItem:`
- `menuNeedsUpdate:`, `applyMenuTitleLimitToItem:fullTitle:`
- `showPresetOverlayName:`, `applySystemSymbol:toMenuItem:`
- `toggleVisualizationFullScreen`, `toggleShuffle:`, `nextPreset:`, `previousPreset:`, `randomPreset:`, `setDuration:`
- `mouseDown:`, `keyDown:`, `cancelOperation:`, `rightMouseDown:`
- `showHelp:`, `windowWillClose:`, `acceptsFirstResponder`

### ProjectMRegistration.mm (foobar2000 glue, ~60 lines)

- `DECLARE_COMPONENT_VERSION`
- `cfg_var` definitions (with GUIDs)
- `pfc::myassert` stub
- `ProjectMViewController` class
- `ui_element_projectMacOS_mac` class + `FB2K_SERVICE_FACTORY`

## Crash Logging

Wrap key entry points in `@try/@catch` logging to `FB2K_console_print`:

- `renderFrame` -- also sets `_projectMInitialized = NO` on crash to stop render loop
- `addPCM`
- `loadPresetsFromCurrentSource`
- `selectPresetFromMenuItem:`
- `prepareDataDirectoryFromZipAtPath:`

Pattern:
```objc
@try {
    // method body
} @catch (NSException *exception) {
    FB2K_console_print("projectM: exception in <method>: ",
                       [[exception description] UTF8String]);
}
```

## Tests (XCTest)

New test target: `projectMacOSTests`.

Three tests covering pure string/logic functions:

| Test | What it verifies |
|------|-----------------|
| `testTruncatedMenuTitle` | Titles <= 32 chars pass through; longer get `...` suffix at char 29 |
| `testCurrentPresetDisplayName` | Sentinel names (`idle://`, `fallback-default.milk`, `projectMacOS.milk`) map to `"projectMacOS"`, normal names get extension stripped, empty returns `"(No preset)"` |
| `testApplyMenuTitleLimit` | Tooltip set only when title was truncated; nil otherwise |

Mocking projectM/OpenGL/foobar2000 SDK was rejected -- cost exceeds value. Those paths are verified by running the component in foobar2000.

Test infrastructure:
- `scripts/run-tests.sh` -- runs `xcodebuild test` against test target
- `scripts/deploy-component.sh` -- calls `run-tests.sh` before deploying, aborts on failure

## Deploy Script Fix

Remove the `data.zip` copy block from `scripts/deploy-component.sh`. The user is expected to place preset data in the appropriate location manually.

## Gitignore

Review and add any missing patterns (e.g., `docs/plans/` is currently ignored by `/docs` rule -- needs adjustment if we want to track design docs).

## CLAUDE.md

Update after refactor to reflect new file layout, test commands, and deploy changes.

## Function Documentation

Add doc comments to all public and category methods in the new files. Brief, one-line descriptions of purpose, parameters, and return values where non-obvious.
