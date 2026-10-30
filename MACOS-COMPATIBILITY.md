# macOS compatibility

The original 0.11.12 checkout uses per-item WindowServer windows and expanding
status items to discover and hide icons. macOS 27 draws the menu bar through
MenuBarAgent, so those techniques no longer provide item discovery or hiding.

## Implementation and attribution

The app, shared XPC service, project configuration, and compatibility tests were
ported from [jordanbaird/Ice PR #995](https://github.com/jordanbaird/Ice/pull/995),
revision `fa3f225f5967935459bcb68c637f863e62b2cbcd`, by RabenkoYevhenii and the
upstream contributors. This includes the prerequisite macOS 26 work and remains
under this project's GPL-3.0 license. The assessment-mode adapter preserves its
Thaw and Barometer attribution in its source.

- macOS 27 item discovery uses Accessibility rather than separate item windows.
- Sections persist per application and are physically arranged around Ice's arrow.
- The default hiding backend uses macOS's per-application menu bar switch and
  records changes so launch and normal termination can restore them.
- An assessment-mode fallback resolves private APIs at runtime. It can affect
  system controls and Ice's icon in locally signed builds; use the default
  backend when available.
- Icon previews use ScreenCaptureKit and a persistent glyph cache on macOS 27.
- macOS 14–26 paths remain availability-gated; they have not been live tested
  on this machine.

Local integration adds `Scripts/build-local.sh`, removes the obsolete automatic
copy-to-Applications build phase, and disables the upstream Sparkle updater for
builds made by that script. The local app has its own bundle identifier,
`com.jordanbaird.Ice.compatibility`, settings, and icon-image cache so it can be
identified separately from an installed Ice. Quit other menu bar managers while
testing. The script creates an ad-hoc signed app with the
hardened runtime disabled for local use, so it can load Sparkle's separately
signed framework. Distribution still requires appropriate signing and notarization.

## Build and test

```sh
./Scripts/build-local.sh
swift test
```

The output is `build/Ice Compatibility.app`. The build script verifies the full bundle's code
signature before copying it there. To make a Debug build, set
`ICE_CONFIGURATION=Debug`. `ICE_DERIVED_DATA` optionally selects a build cache.

The macOS 27 layout uses SwiftUI tiles with drag-and-drop and section context
menus. A section change also arranges the actual icons around Ice's arrow.
Tiles no longer depend on Accessibility frames, which can be zero or stale
for concealed items. If a glyph cannot be captured, the application's icon is
used so the item remains reachable.

General settings also offers **Show Hidden Items** and **Hide Hidden Items** on
macOS 27, so the user can reach the section when Ice's own icon is behind the
system overflow control.

If Advanced settings reports that the native hiding method cannot access the
menu bar settings, use **Allow Menu Bar Settings Access…** and select
`group.com.apple.controlcenter.plist` in the opened folder. This is a specific
user-selected file grant, saved as a security-scoped bookmark. Ice still writes
through the container-aware preferences API so MenuBarAgent receives changes.
Cancelling keeps the assessment-mode fallback. No privacy permission is edited
by the build script.

Local signatures can change after recompilation. If System Settings shows an old
Ice permission entry but the new app is denied access, remove the stale entry
and grant the new app access through System Settings. The build script does not
alter privacy permissions.

Private macOS behavior can change in future updates. Ice's sections apply to all
items belonging to an application. Assessment mode
has additional restrictions described above. These are platform limitations,
not features covered by the passing unit tests.

## Validation on October 30, 2026

- Host: macOS 27.2 (`26B123`), Apple silicon; Xcode 27.1 (`27A9275`).
- Native Debug port build and final Release build: passed.
- Release bundle: full strict code-signature verification passed.
- Compatibility core: 157 tests in 31 suites passed.
- Desktop test: launch, permission approval, item discovery and previews, section
  assignment through context menus, and section persistence across relaunch passed.
- Native hiding: assigned eqMac to Hidden, confirmed macOS changed `isAllowed`
  to false, used **Show Hidden Items** to restore true, then **Hide Hidden Items**
  to restore false. Ice's own menu bar entry remained allowed throughout.
- Normal quit restored eqMac's visibility. Relaunch retained the section layout
  and the authorized preferences-file bookmark.
- Ice Bar opening was confirmed by the runtime log. Clicking a tile in that
  separate panel was not verified by the available desktop controls.
- About displayed the local-build updater notice without upstream update controls.
- Restored eqMac to Visible, disabled the temporary Ice Bar setting, restored
  automatic rehiding, and cleared the temporary hotkey after testing.

At the initial port validation, physical status-icon and global-hotkey activation
on this crowded menu bar, drag-and-drop through desktop automation, external-display
transitions, and older macOS releases were not verified. Arrow activation and
physical ordering were subsequently verified below. The Settings controls and context menus were exercised
directly. This is a local compatibility build, not a notarized release.

Build and test logs are saved in `build/validation/` (ignored build output).

## Arrow boundary revision

The initial compatibility port saved visibility without maintaining a physical
boundary. This revision restores the two-group arrangement: hidden icons to the
left of the arrow and visible icons to its right. Normal clicks toggle visibility;
Command-drags change section membership instead of toggling the arrow.

- `SectionBoundaryController27` performs real Command-drags and checks the resulting
  Accessibility positions after each move. It does not restart MenuBarAgent.
- When an applet resists a direct move, Ice moves its own arrow past the hidden
  group and places visible items on the right instead.
- Command-dragging an icon across the arrow updates the saved section. Dragging
  the arrow adopts the visible boundary. New applications appearing on its left
  enter Hidden; additional icons of an already known app follow that app's section.
- Multiple processes from the same app receive distinct runtime item identifiers.
  The native macOS visibility switch still applies to the entire application, so
  all of an application's icons follow its section together.
- The mover is adapted from [fif7y/dimble](https://github.com/fif7y/dimble),
  revision `57d6ac1767a145efde5475a80bffd5d5cb20fefc`, under GPL-3.0.

Validation of the final arrow revision:

- Release build, strict signature verification, and 164 tests in 32 suites passed.
- Live Accessibility positions confirmed all six configured Hidden apps left of
  the arrow and visible apps right of it.
- The user clicked the arrow twice and confirmed that the hidden icons appeared
  on its left and then disappeared. Runtime logs independently recorded the arrow
  toggles and the corresponding native visibility changes for all six apps.
- Moving eqMac from Visible to Hidden through the layout context menu physically
  placed it left of the arrow. Restoring Visible placed it right; the original
  six Hidden assignments were preserved.
- Replaced `/Applications/Ice.app` with the exact tested executable, verified its
  signature and SHA-256 match, and launched it from that path. The installed app
  repeated the successful boundary check and concealed all six configured apps.
- Manual Command-drag adoption, global hotkeys, external-display transitions, and
  older macOS versions remain unverified in this revision.

Logs and the installation record are in `build/validation/arrow-boundary/`.
The previous installed app is backed up at
`build/backups/Ice-before-arrow-boundary-20261030-152819.zip`.
