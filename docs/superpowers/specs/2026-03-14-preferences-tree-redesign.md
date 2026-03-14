# Preferences Tree Redesign

## Goal

Split the single "projectMacOS" preferences page into a tree of section pages (one per section) and rework the layout to match the native foobar2000 style: left-aligned, natural-width labels, controls stretching to fill remaining width.

## Architecture

### File Structure

Replace `mac/ProjectMPreferences.mm` (currently one large file with all sections) with six focused files:

| File | Contents |
|------|----------|
| `mac/ProjectMPreferences.mm` | Parent page registration only — blank view, "projectMacOS" node under Tools |
| `mac/ProjectMPrefsPerformance.mm` | Performance section — 6 controls |
| `mac/ProjectMPrefsTransitions.mm` | Transitions section — 5 controls |
| `mac/ProjectMPrefsVisualization.mm` | Visualization section — 4 controls |
| `mac/ProjectMPrefsPresets.mm` | Presets section — 4 controls |
| `mac/ProjectMPrefsDiagnostics.mm` | Diagnostics section — 1 control |

A shared header `mac/ProjectMPrefsParent.h` declares the parent GUID as an `extern const GUID kPrefsParentGUID` so each section file can return it from `get_parent_guid()` without duplicating the value.

All five new `.mm` files are added to the Xcode target (`mac/projectMacOS.xcodeproj`).

### foobar2000 Registration

Each file registers exactly one `preferences_page` subclass via `FB2K_SERVICE_FACTORY`.

- **Parent page** (`ProjectMPreferences.mm`): `get_parent_guid()` returns `guid_tools`. GUID unchanged: `{ 0x2f8a5e17, 0x3c94, 0x4b61, { 0xa7, 0xd2, 0xe1, 0x9f, 0x0b, 0x84, 0xc5, 0x3a } }`. View is a blank `NSView`.
- **Section pages**: `get_parent_guid()` returns `kPrefsParentGUID`. Each gets a new unique GUID (generated at implementation time).
- Section page names: `"Performance"`, `"Transitions"`, `"Visualization"`, `"Presets"`, `"Diagnostics"`.

### Section Contents (unchanged from current implementation)

Each section keeps exactly the controls it currently has. No controls are moved, removed, or added.

**Performance**: FPS Cap, Idle FPS, Resolution, Mesh Quality, Vsync, Auto-pause

**Transitions**: Soft Cut Duration, Hard Cuts, Hard Cut Sensitivity, Hard Cut Min Interval, Duration Randomization

**Visualization**: Beat Sensitivity, Aspect Correction, Mouse Interaction, Mouse Effect

**Presets**: Presets Folder (text field + Browse button), Sort Order, Filter, Retry Count

**Diagnostics**: Debug Logging

## Layout Style

Each section page uses a plain `NSView` (no scroll view — all sections fit comfortably in the standard preferences panel height).

### Stack structure

```
NSView (self.view)
  NSStackView (vertical, leading, spacing 8, insets top:20 left:16 bottom:20 right:16)
    [rows and checkboxes for this section]
```

### Row types

**Label + control row** — horizontal NSStackView, spacing 8pt:
- Label: `[NSTextField labelWithString:]`, natural width, left-aligned
- Label hugging priority: `NSLayoutPriorityDefaultHigh` (751) — does not stretch
- Control (popup or text field): hugging priority `NSLayoutPriorityDefaultLow` (250) — stretches to fill remaining width

**Checkbox row** — `[NSButton checkboxWithTitle:target:action:]` added directly to the vertical stack; no wrapping row needed

**Help text** — `[NSTextField wrappingLabelWithString:]`, 11pt system font, `secondaryLabelColor`, placed directly below its associated row, flush with the left edge (no additional indent)

**Spacer** — fixed-height `NSView` (8pt) between logical groups within a section (e.g., between the Hard Cuts checkbox and its dependent controls)

### No section headers

Each page corresponds to exactly one section; the tree node name serves as the title. No bold header labels are added inside the views.

### Dependent control enable/disable

Behavior unchanged from current implementation:
- Hard Cut Sensitivity popup and Hard Cut Min Interval popup are disabled when Hard Cuts is unchecked
- Mouse Effect popup is disabled when Mouse Interaction is unchecked

## Xcode Project

Five new `.mm` files and one new `.h` file are added to the main target in `mac/projectMacOS.xcodeproj`. The existing `ProjectMPreferences.mm` is modified in place (not renamed).

## Testing

No new unit-testable logic is introduced. Verification is manual:
- All five section names appear as children of "projectMacOS" in Tools preferences tree
- Each section page shows its controls with left-aligned layout
- All controls read from and write to their `cfg_` variables correctly
- Dependent controls (Hard Cut Sensitivity/Interval, Mouse Effect) enable/disable correctly
- Build succeeds with `SKIP_DEPS_BUILD=1 bash scripts/deploy-component.sh --build`
