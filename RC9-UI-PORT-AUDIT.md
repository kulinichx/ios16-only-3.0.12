# RC9 UI migration audit

Date: 2026-11-04

This document preserves the pre-implementation audit. For the subsequent
first-batch implementation, RC9 icon replacement, independent theme storage
and outstanding native/device validation, see `RC9-UI-PORT-STATUS.md`.

## Scope and state

Reference checkout: `G:\RootHide\runtime-rc9-audit`.
Target checkout: `G:\RootHide\ZQBB IOS16\Dopamine-roothide-ios16`.
Known-working target source: `1754adf69c60b88fb034928e1cf8949e3dd8391d`.

This is a source comparison and port checklist, not a completed UI port.
No runtime sources, assets, app identity, authorization policy or jailbreak
components were changed by this audit. The RC9 checkout was read only,
including its existing uncommitted changes. Backup files ending in
`.bak-20261003` were not treated as active sources.

The user reports that the target package retains and successfully loads their
existing tweaks. Preserve that package as the rollback reference; this feedback
does not establish UI portability or comprehensive migration compatibility.

## Features found in active RC9 sources

| Area | Implementation | Port decision |
| --- | --- | --- |
| Glass material | `UI/DOMainViewController.m`: `DOCustomLiquidGlassView` | Extract the active material implementation, keeping its fallback path and calibrated material roles. |
| Appearance controls | Same file: `DOCustomGlassThemeSettingsViewController` | Preserve Light/Dark Glass, wallpaper blur, glass blur, transparency, highlight and recommended-value reset. |
| Wallpaper | `UI/DONavigationController.m` | Keep one shared background below navigation transitions, asynchronous static-image blur, readability scrim and immediate refresh after successful import. |
| Video and Live Photo | Theme picker in `DOMainViewController.m`; playback in `DONavigationController.m` | Preserve local import, poster generation, muted looping, playback speed and lifecycle cleanup. Do not ship bundled videos merely to implement this feature. |
| Profile | `DOMainViewController.m`: avatar picker, username/motto editors and focus methods | Preserve custom avatar, editable username/motto and draggable edge-docked focus mode. |
| Home actions | `setupCustomGlassHome` | Preserve settings/about/theme cards, respring/userspace reboot/device reboot actions, confirmation and existing jailbreak-state restrictions. |
| Settings/about styling | `UI/Settings/DOSettingsController.m`, `DOCreditsViewController.m` | Port appearance and navigation methods only, keeping current target specifiers and functionality. |
| Media persistence | `UI/DOCustomGlassMediaStore.h` | Preserve explicit app-container resolution, filename checks and write/decode/commit-before-delete ordering. |
| Theme persistence | `UI/DOCustomGlassThemeSync.h`, `main.m` | Preserve the theme-only snapshot and authoritative-removal behavior, after resolving cross-app storage ownership. |
| Uptime display | `UI/DOHeaderView.m` | Port the day/hour/minute presentation, not the older timer implementation. |
| Single theme | `UI/Themes/Themes.plist` and `Assets.xcassets` | Keep a single glass theme with a bundled fallback and the main app icon; remove unused themes and alternate icons together. |

The active theme page defaults are wallpaper blur `0.10`, glass blur `0.85`,
transparency `0.70`, highlight `0.05`, Light Glass and playback rate `0.65`.
The playback selector offers `0.50`, `0.65`, `0.80` and `1.00`.
These are values observed in RC9, not newly chosen tuning.

The active foreground helper intentionally keeps light-colored text/icons.
Wallpaper luminance adjusts the background scrim; it does not freely switch
all labels between black and white. Preserve this distinction.

## Important: active glass is not the old Metal overlay

RC9 still includes `DOCustomGlassRefractionView.h/.m` and links Metal/MetalKit,
but the inspected active UI does not instantiate that class.
`setupCustomGlassHome` explicitly assigns:

```objc
self.customGlassJailbreakRefractionView = nil;
```

The visible surfaces are `DOCustomLiquidGlassView`, using dynamically resolved
`CABackdropLayer`/`CAFilter`, tint and directional perimeter layers, with a
`UIVisualEffectView` fallback.

Do not revive the unused shader overlay simply because it has "Glass" in its
filename. First port the renderer actually used by RC9. Only omit the old
class and Metal links after removing its remaining declarations/references
and checking the complete target link requirements.

## Uptime: keep target improvements

RC9's `DOHeaderView`:

- Reads `CLOCK_MONOTONIC_RAW`.
- Formats days, hours and minutes with `NSDateComponentsFormatter` using full
  localized units and dropped zero units.
- Displays a localized less-than-one-minute message.
- Schedules a repeating 60-second target-selector timer inside initialization;
  no corresponding invalidation is present in the inspected file.

The target instead owns uptime in `DOMainViewController`:

- Uses `mach_continuous_time` and the Mach timebase.
- Formats seconds as `Uptime_Format`, for example
  `%llu天 %02llu:%02llu:%02llu` in Simplified Chinese.
- Uses a weak block timer and explicit visible/active-state checks.
- Stops the timer when the page disappears or the app resigns active.
- Retains separate system-version, injection-mode, app-build and build-time
  information rows.

Port only RC9's presentation: a compact localized day/hour/minute duration
and the under-one-minute string. Keep the target clock source, lifecycle
handling and build information. Reduce refresh frequency deliberately if the
display no longer includes seconds. Do not copy the entire old header over the
new information-row APIs.

For the glass header, keep an aligned, bounded-width information block.
The RC9 helper enumerates direct labels, whereas the target also has nested
title/value row stacks; merging must handle both rather than assume identical
view hierarchies.

## Default-theme and asset slimming

The target currently declares five themes:
`default`, `ellekit`, `blue`, `red`, `purple`.
RC9 declares only `purple`, still named `Desert Dusk` in its plist, and uses
that key to select the custom-glass code paths.

RC9 retains `Background_Purple.imageset` and `AppIcon.appiconset`. Its four
other built-in backgrounds and four alternate app-icon sets are absent.
The purple background asset has the same aggregate byte size in both trees;
it is the bundled fallback, not the whole glass implementation.

Target candidates for removal after reference checks:

- `Background_Green.imageset`, `Background_ElleKit.imageset`,
  `Background_Blue.imageset`, `Background_Red.imageset`.
- `AppIcon_ElleKit.appiconset`, `AppIcon_Blue.appiconset`,
  `AppIcon_Red.appiconset`, `AppIcon_Purple.appiconset`.

These eight target sets total 2,848,770 source bytes (about 2.72 MiB), including
their JSON metadata. This is not a promised IPA size reduction: asset catalog
compilation, image compression and any change to the primary icon affect
the final result.

The corresponding migration must also handle:

1. The theme list and its stale saved values.
2. The old settings picker, theme-change relaunch and alternate-icon calls.
3. Both Debug and Release `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
4. Previously selected alternate icons during an in-place app update.
5. Required main icon, Dopamine logos, launch-screen assets and boot-logo
   generation. `DOTheme.generateBootLogo` still uses the bundled theme image.

Prefer retaining the `purple` key for this port. Renaming it requires updating
all theme gates and a preference migration, not just its display name.

## Persistence and cross-app migration

`DOCustomGlassMediaStore` resolves the installed application's data container
using `NSBundle.mainBundle.bundleIdentifier`, LaunchServices and an MCM
fallback. It stores media under
`Library/Application Support/CustomGlass/Media` in that container.
Only safe filenames are kept in the `DOCustomGlassTheme.*` preferences.

RC9's project and packaging use `com.opa334.Dopamine-roothide`; the target
packaging uses `cn.zqbb.dopaRH`. Consequently, carrying over a media filename
does not establish that the referenced file exists in the target container.
Do not claim that old RC9 wallpaper/avatar media automatically migrates.

RC9's theme sync uses a fixed path:
`/var/mobile/Library/Application Support/DopamineRH/glass-theme.plist`.
It mirrors only `DOCustomGlassTheme.*` keys, and its authoritative marker
ensures that removed keys do not reappear from an older preference store.

Before wiring the sync into target startup, decide how the new app owns its
theme store while RC9 remains installed:

- Do not overwrite RC9's shared theme snapshot during an empty first launch.
- Do not import media filenames without verifying/copying the corresponding
  files into the target app container.
- Preserve RC9 source data during migration and handle partial import failure.
- Keep license, jailbreak and package-manager preferences outside theme sync.
- Validate persistence both before and after jailbreak on the actual device.

An explicit one-time theme/media import, or a separately namespaced target
store with fresh customization, is preferable to accidental cross-app sharing.
The policy needs to be established before implementing persistence migration.

## Authorization and unrelated code boundaries

RC9's glass visibility is coupled to `DORHSupporterIsVerified()` in home,
navigation, settings and credits. Its jailbreak tap and `startJailbreak`
also enforce the license.

This UI port is not an authorization-system port. Do not fabricate a
verification stub, copy secrets or copy RC9's jailbreak activation method just
to make its UI compile. Preserve authorization implementation and policy for
a separate, reviewed integration; keep any new glass-availability decision
explicitly separate from license verification.

Do not wholesale-copy RC9's `DOSettingsController`:
it still contains mount-management methods, licensing UI, health-management
functionality and runtime-setting implementations outside this task.
Likewise, preserve the target's removal of Zebra, active TrollStoreLite fixes
and custom-mount replay. Do not restore them via an older UI file.

Leave `BaseBin`, exploits, bootstrap roots, install-version markers, signing,
Jetsam calculations, package databases, app identity and existing activation
guards unchanged.

## Port order and verification gates

1. Port uptime presentation with localized strings and source-contract tests,
   preserving the target's clock and timer lifecycle.
2. Extract active glass material and theme-page code into clearly scoped UI
   files. Add only the required source/framework references to the current
   Xcode project rather than replacing it.
3. Integrate home/profile, shared background and settings/about appearance.
   Merge the target's information rows, activation guards and log expansion.
4. Wire media persistence and an explicit cross-app theme-migration policy.
   Port scene/window replacement cleanup together with video playback.
5. Remove unused theme assets, icon build settings and settings entries as
   one checked change. Test saved selections and boot-logo behavior.
6. Run source checks, plist/project validation and a full native GitHub build.
   Inspect packaged resources and compare actual final package sizes.
7. Device-test cold launch, back navigation, compact-screen layouts, static
   wallpaper, video/Live Photo, canceled/failed imports, background/foreground,
   window replacement and persistence across reboot/re-jailbreak.
8. Integrate authorization separately after the glass build is accepted.

Windows source checks do not execute UIKit, Photos, AVFoundation or private
Core Animation APIs. No native UI compilation, rendering or on-device glass
validation was performed in this audit.
