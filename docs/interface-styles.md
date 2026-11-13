---
review_status: unreviewed
approval_status: not_approved
---

# Interface Styles

Every Upshot screen builds its controls from the shared interface styles in `Upshot/`. A screen never defines its own button, row, panel, field, sidebar, toolbar, flyout, card, or toast style, and never sets its own colors, corner radii, spacing, or font sizes. When a screen needs something these files lack, the new style goes into the shared files and the `design-gallery` render state first, and the screen uses it from there.

## Files

- `Upshot/InterfaceTokens.swift`: colors (`Palette`), corner radii (`Radius`), spacing (`Space`), component sizes (`InterfaceMetrics`), symbol sizes (`IconSize`), and type (`Font.ds*`).
- `Upshot/InterfaceWindowComponents.swift`: components for windows, which are Settings, Library, the annotation editor, the Studio editor, export panels, and sheets.
- `Upshot/InterfaceFloatingComponents.swift`: components for floating UI, which is everything drawn in a panel over other apps.
- `Upshot/InterfaceControlState.swift`: `InterfacePresentedControlState`, which the gallery uses to draw hover, pressed, focused, and disabled states without a pointer. Screens never set it.
- `Upshot/InterfaceStyleGallery.swift`: the `design-gallery` render state.
- `Upshot/Motion.swift`: the shared springs and transitions.

## Gallery

The `design-gallery` render state draws every component in every state in light and dark:

```bash
xcodebuild build -project Upshot.xcodeproj -scheme "Upshot Dev" -configuration "Debug Dev" -destination "platform=macOS" -derivedDataPath .local/build
".local/build/Build/Products/Debug Dev/Upshot Dev.app/Contents/MacOS/Upshot Dev" --render-states .local/render-states --state design-gallery
```

The run writes `design-gallery-light.png`, `design-gallery-dark.png`, and `contact_sheet.png`. The floating section sits over a generated screenshot so glass legibility is tested over real content. Compare a redesigned screen against the gallery before committing it.

## Tokens

### Color

- Text: `Palette.label`, `Palette.secondaryLabel`, `Palette.tertiaryLabel`, and `Palette.disabledLabel`. Detail text uses `secondaryLabel`.
- Accent: `Palette.accent` is the system accent color. It marks toggles that are on, focus rings, the selected card, and text being recorded into a shortcut field. It never fills a button or a selected mode.
- Destructive: `Palette.destructiveLabel` for destructive button text and failure text, with `Palette.destructiveFill`, `destructiveHoverFill`, and `destructivePressedFill` behind destructive buttons. `Palette.record` marks recording only.
- Window controls: `controlFill`, `controlHoverFill`, and `controlPressedFill` for action buttons and window mode switch tracks; `fieldFill` and `fieldStroke` for text fields and shortcut fields.
- Sidebar rows: `sidebarHoverFill`, `sidebarSelectionFill`, and `sidebarPressedFill`.
- Floating UI: `floatingPanelBase` under the glass, `floatingStroke` around it, `floatingDivider` between groups, and `floatingHoverFill`, `floatingSelectionFill`, and `floatingPressedFill` for toolbar buttons, flyout rows, and floating mode switches.
- Every color above is defined separately for light and dark in `InterfaceTokens.swift`.

### Spacing and Size

- Spacing scale in points: `Space.xxs` 2, `xs` 4, `s` 6, `m` 8, `ml` 10, `l` 12, `xl` 16, `xxl` 20, `xxxl` 28. Spacing never adds or subtracts points from a token.
- Control height: 22 points for action buttons, text fields, value fields, and shortcut fields.
- Sidebar: 200 points wide, 28-point rows, 18-point icon tiles, 2.5 points between a tile and its label.
- Floating: 6-point panel padding, toolbar buttons at least 62 by 52 points, 36-point flyout rows, 30-point size fields, 28-point mode switches.

### Corner Radius

- `Radius.control` 6: action buttons, text fields, value fields, and shortcut fields.
- `Radius.sidebarRow` 8 and `Radius.sidebarIconTile` 5.
- `Radius.field` 8: size fields in floating UI.
- `Radius.toolbarButton` 10 inside `Radius.panel` 16, because a 6-point panel padding plus a 10-point inner radius gives 16.
- `Radius.flyout` 14: flyout menus and toasts. Flyout rows use 14 minus the 5-point flyout padding.
- `Radius.card` 16 and `Radius.pill` for capsules.
- A shape inside another shape uses `Radius.nested(inner:padding:)`.

### Type

- `Font.dsBody` 13 regular: row titles, button labels, field text, and sidebar labels.
- `Font.dsBodyEmphasis` 13 medium: flyout row titles and toast titles.
- `Font.dsHeadline` 13 semibold: section headers.
- `Font.dsCaption` 11: row detail and section footers.
- `Font.dsGroupLabel` 11 semibold: sidebar group headers.
- `Font.dsToolbarLabel` 11 medium: labels under toolbar icons.
- `Font.dsSegment` 12 medium and `Font.dsSegmentSelected` 12 semibold: mode switch segments.
- `Font.dsKeyHint` 12: key hints in flyout rows.
- `Font.dsFieldNumeric` 13 with monospaced digits: value fields. `Font.dsSizeField` 14 medium with monospaced digits: size fields.
- Symbol sizes come from `IconSize`.

## Window Components

### Page

- `InterfaceFormPage`: the page of a settings pane or any form-style panel. It is a grouped `Form` with a transparent background. It applies the switch toggle style and the action button style to everything inside it, so a plain `Button("Choose…")` inside the page is already the shared action button.

### Sidebar

- `InterfaceSidebar`: the sidebar column, with an optional search field above scrolling rows. The screen handles arrow keys with `onMoveCommand`.
- `InterfaceSidebarSearchField`: the capsule search field at the top of a sidebar. Escape clears it.
- `InterfaceSidebarRow`: one sidebar row with an 18-point icon tile, a label, an optional trailing count, and normal, hover, pressed, selected, and disabled states.
- `InterfaceSidebarIcon`: a symbol on a tile tinted with one `InterfaceSidebarTint` color, or an image such as an app icon. Every row in a sidebar uses a tile, so every label starts at the same edge and every gap is the same.
- `InterfaceSidebarGroupHeader`: the small heading above a group of sidebar rows, such as Library, Categories, or Apps.
- The visible gap between a tile and its label measures 3 to 3.5 points in the gallery. The old Settings sidebar gap measured 8.5 to 9 points and the old Library sidebar gap measured 7.5 to 8.5 points, both measured from glyph edge to text edge in renders at 2 pixels per point.

### Sections and Rows

- `InterfaceSection`: the grouped section container, with an optional header, header detail, and footer. Use a footer only when one sentence explains the whole section.
- `InterfaceSectionHeader`: the section title, used by `InterfaceSection`.
- `InterfaceRowLabel`: a row title with optional detail. Leave detail out unless the title alone would mislead; most rows need none.
- `InterfaceRow`: a title on the leading edge and any trailing content. Give it a symbol only when every row in the same section has one.
- `InterfaceToggleRow`: a title and a switch.
- `InterfacePickerRow`: a title and a pop-up menu.
- `InterfaceTextFieldRow`: a title and a text field with a focus ring.
- `InterfaceFolderRow`: a title, the folder icon and folder name, the full path in a tooltip, an optional reset button before the folder name, and a `Choose…` button. Use it for every folder setting instead of showing a path.
- `InterfaceShortcutRow`: a title and a shortcut field. Click the field to record, use the clear button to remove the shortcut, and use the reset button to restore the default when the shortcut was changed. A registration failure replaces the detail in red.
- `InterfaceShortcutField`: the 120-point shortcut field used by the shortcut row, with assigned, unassigned, recording, hover, and disabled states.

### Buttons and Values

- `InterfaceActionButtonStyle`, written `.buttonStyle(.interfaceAction)`, and `InterfaceActionButton`: the one action button style. A `Button(role: .destructive)` with the same style is the destructive variant, with red text on a red fill. There is no prominent, bordered, borderless, capsule, or glass variant in windows. A screen marks its main action by position and wording, not by a filled accent button, so a full-width or accent-filled button such as the current Deploy to Cloudflare capsule in the Cloud pane is replaced with this style.
- `InterfaceResetButton`: the small circular arrow that restores a default, placed before the control it resets.
- `InterfaceValueWithUnitField`: an editable number followed by its unit inside one field, such as 30 days. Use `unitSpacing: .none` for units written without a space, such as 80%.
- `InterfaceValueWithUnitLabel`: the same layout for a value that is not editable, such as the value beside a slider.
- `interfaceFieldChrome()`: the field background, stroke, and focus ring, for a field that no row component covers.
- `InterfaceModeSwitch` with `surface: .window`: a segmented choice between two to four options inside a window, with a neutral selected segment.

## Floating Components

- `InterfacePanel` and `interfacePanelSurface`: the glass panel that holds floating UI. `.panel` is the 16-point toolbar shape, `.flyout` is the 14-point menu and toast shape, and `.pill` is a capsule.
- `InterfaceToolbarButton`: a toolbar button with its label under the icon, as in the All-In-One toolbar, with normal, hover, pressed, selected, and disabled states. `labelPlacement: .hidden` makes an icon-only button for compact bars such as the recording control bar; its title becomes the tooltip. `tint` colors the icon, such as `Palette.record` for stop.
- `InterfaceToolbarDivider`: the vertical line between toolbar groups.
- `InterfaceFloatingButtonStyle`: the fill behavior behind toolbar buttons and flyout rows, for a floating control that no other component covers.
- `InterfaceModeSwitch` with `surface: .floating`: the segmented mode switch in its own glass capsule, used for filters such as All, Screenshots, and Videos.
- `InterfaceSizeFieldsPill`: the width and height fields with an aspect ratio menu, in their own panel.
- `InterfaceFlyoutMenu`, `InterfaceFlyoutRow`, and `InterfaceFlyoutDivider`: the menu that opens from a toolbar button, with an icon, a title, and a trailing key hint on each row. `isHighlighted` marks the row the keyboard has selected.
- `InterfaceCard`: a floating card such as a Quick Access card, with normal, hover, pressed, selected, and disabled states.
- `InterfaceToast`: a short message with an icon, an optional detail line, an optional action button, and a neutral, success, or failure tone.

## Older Controls

The following shared controls predate these styles and remain only because existing editor and floating screens call them. Each screen agent replaces the uses in its own screen with the components above, and the control is deleted when its last use is gone.

- `GlassCapsuleButton`, `GlassMenuButton`, `GlassConfirmButton`, and `GlassActionCapsule` in `GlassControls.swift`: replace with `InterfaceActionButton` in windows and `InterfaceToolbarButton` in floating UI.
- `GlassIconButton` in `GlassControls.swift`: replace with `InterfaceToolbarButton` using `labelPlacement: .hidden`.
- `KeyCap` and `KeyCaps` in `GlassControls.swift`: replace with `InterfaceShortcutField` in rows and `InterfaceFlyoutRow` key hints in menus.
- `SettingsPage`, `SettingsControlLabel`, `SettingsButton`, and `glassHUD` were already removed in favor of `InterfaceFormPage`, `InterfaceRowLabel`, `InterfaceActionButton`, and `interfacePanelSurface`.
- The inspector controls in `AnnotationInspectorStyle.swift` belong to the editor inspectors and stay until the annotation editor and Studio editor redesigns decide their replacements.
