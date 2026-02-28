# Favorites Menu Design

## Overview

Add a Favorites submenu to the context menu, allowing users to save, load, remove, export, and import favorite presets.

## Storage

- New `cfg_string cfg_preset_favorites` in `ProjectMRegistration.mm` with a dedicated GUID.
- Value: JSON array of objects: `[{"path":"/tmp/.../foo.milk","name":"foo.milk"}, ...]`
- `name` is the bare `.milk` filename (portable key for matching across ZIP re-extractions). `path` is the last-known full filesystem path (fast lookup hint).
- In-memory: `NSMutableArray<NSDictionary *>` loaded on first access, serialized back to `cfg_string` on every mutation.

## Menu Structure

```
Random Pick
───────────
Favorites >
  Save Current              (disabled + tooltip "Already in Favorites" if current is favorite)
  Manage >
    Save List               (NSSavePanel, .json)
    Load List               (NSOpenPanel, .json, validates + deduplicates)
  ───────────
  ★ Favorite 1 >            (★ checkmark if currently playing)
      Load
      Remove                (NSAlert confirmation)
  Favorite 2 >
      Load
      Remove
  ...
  -or-
  "No favorites yet"        (disabled)
───────────
Shuffle Presets
```

Placement: below "Random Pick", wrapped in separators.

## Behaviors

### Save Current

1. Read current `cfg_preset_name` to get filename.
2. Check if already in favorites by `name` field. If yes, item is disabled with tooltip "Already in Favorites".
3. Build entry: `{"path": <full path from playlist>, "name": <filename>}`.
4. Append to array, serialize to `cfg_string`.

### Load Favorite

1. Use `enqueuePresetRequest:PMPresetRequestTypeSelectPath` with the stored `path`.
2. `applyPresetSelectionPathInRenderLoop:` handles path-first, then filename-suffix fallback.
3. Disable shuffle (`cfg_preset_shuffle = false`) and clear pending shuffle timer, since deliberate selection implies the user wants to stay on that preset.

### Remove Favorite

1. Show `NSAlert`: "Remove [name] from Favorites?" with Remove / Cancel buttons.
2. On confirm: remove entry from array by `name`, serialize back to `cfg_string`.

### Save List (Export)

1. `NSSavePanel` with `.json` allowed content type.
2. Write the JSON array to the chosen file with pretty printing (`NSJSONWritingPrettyPrinted`).

### Load List (Import)

1. `NSOpenPanel` with `.json` allowed content type.
2. Parse JSON, validate: must be an array of objects, each with a `name` string field.
3. Skip entries where `name` already exists in current favorites.
4. Append valid new entries, serialize back to `cfg_string`.
5. Log to foobar2000 console: count of imported and skipped entries.

## Files to Modify

| File | Changes |
|------|---------|
| `ProjectMRegistration.mm` | Add `cfg_string cfg_preset_favorites` with new GUID |
| `ProjectMView.h` | Declare `cfg_preset_favorites` extern, declare Favorites category or extend Menu category |
| `ProjectMView+Menu.mm` | Build Favorites submenu in `buildContextMenu`, implement all favorite actions (save, load, remove, export, import) |
| `ProjectMMenuLogic.h/.mm` | Add pure helpers: favorite duplicate check, JSON validation, favorite display name |

## Testing

- Pure logic in `ProjectMMenuLogic` (duplicate detection, JSON validation/parsing, display name formatting) tested via XCTest.
- Menu integration and NSSavePanel/NSOpenPanel flows tested manually.
