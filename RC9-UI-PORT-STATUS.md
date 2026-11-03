# RC9 UI port: first batch

Date: 2026-11-04

Target: `G:\RootHide\ZQBB IOS16\Dopamine-roothide-ios16`
Reference, read only: `G:\RootHide\runtime-rc9-audit`
Branch: `ios16-roothide-3.0.12`
Remote: `ios16-target` (`kulinichx/ios16-only-3.0.12`)

The pushed baseline is `851480cc`, including Settings glass/back navigation,
RC9 home-layout alignment and About back navigation. Full build #22
(`41697683880`) passed for that source. The user subsequently requested About
glass too; this local follow-up is documented at the end and still needs its
own native build and device validation. Earlier sections describe historical
checkpoints, not the current working-tree layout.

## Implemented

- Extracted RC9's active Liquid Glass material and appearance editor into
  dedicated UI sources. The retired Metal overlay is not included.
- Ported the glass homepage, avatar, username/motto, draggable focus mode,
  settings/about/theme entry cards and restart actions.
- Preserved Light/Dark Glass, wallpaper blur, glass blur, transparency,
  highlight and recommended-value reset controls.
- Ported static-image, video and Live Photo wallpaper imports, muted looping,
  playback speed, background/foreground handling and window-replacement cleanup.
  Decorative video pauses during jailbreak and cannot restart in a retired
  window. Glass slider notifications do not reload wallpaper files.
- Changed uptime presentation to localized full day/hour/minute units with
  a less-than-one-minute state. Retained continuous time, weak timer ownership
  and page/app lifecycle stops; refreshes are aligned to minute boundaries.
- Preserved system/injection mode, build version and build time rows, uniform
  small-screen fitting and root-coordinate jailbreak-button expansion.
- Kept the purple fallback theme; removed the unused default themes,
  alternate icons, settings theme chooser and alternate-icon build settings.
- Replaced the primary app icon with all 15 RC9 PNGs plus its `Contents.json`.
  All 16 file hashes match the RC9 snapshot; referenced PNG dimensions match
  their catalog slots. Debug and Release still select `AppIcon`.
  Existing alternate-icon selection is reset to the primary icon on launch.

## Ownership and boundaries

The app remains `cn.zqbb.dopaRH`, version 3.0.12, RootHide revision 29.
No BaseBin, jailbreak engine, exploit, bootstrap/package database, signing,
Jetsam algorithm or authorization implementation was ported or modified in
this UI batch. The other-jailbreak activation guard remains in place.
Zebra, active TrollStoreLite fixes and custom mount management remain removed.

Media stays in this app's explicitly resolved data container:
`Library/Application Support/CustomGlass/Media`.
Theme-only preference synchronization uses:
`/var/mobile/Library/Application Support/DopamineRH-iOS16/glass-theme.plist`.
It does not use RC9's `DopamineRH` directory. No old RC9 media filenames are
automatically imported. Choose the avatar and wallpaper again in this app;
RC9's originals are left untouched.

Settings and about retain the target's native modal contents and styling.
Their RC9 glass interior styling and authorization integration are deferred.
This is the first UI batch, not a claim that every RC9 feature was migrated.

## Verification performed

- `node --test tests/ios16-contracts.test.cjs tests/glass-ui-contracts.test.cjs`:
  32 source-contract tests pass after the runner and localization follow-ups.
- RC9 primary-icon SHA-256 equality, PNG headers and catalog pixel sizes pass.
- Themes/package-manager XML parses and actionlint 1.7.12 passes.
- `git diff --check` passes.
- New material source and required system frameworks are in the app's actual
  Xcode build phases; source checks detect duplicate project object IDs.
- Jailbreak execution and button-title method fingerprints match the tested
  `1754adf69c60b88fb034928e1cf8949e3dd8391d` baseline.

Source checks alone are not a UIKit rendering test. The subsequent Intel
native build and scripted package checks passed, as recorded below. The
actual compressed TIPA size has not been measured locally for this batch.
The icon artwork increases source bytes; deleting old theme assets does not
establish a particular compressed-package saving. Device/UI validation is
still required.

## Next validation

1. Use the artifact from successful full build #18, source `a8e736ef`, for
   device validation. A push runs source checks only, not the full macOS build.
2. Inspect the resulting package's icon/resources and compare its actual size.
3. Device-test cold launch, the RC9 home-screen icon, all entry cards,
   compact-screen layout, update-button spacing and jailbreak log expansion.
4. Test static/video/Live Photo imports, cancellation/failure, playback speed,
   background/foreground, navigation and replacement-window cleanup.
5. Test theme/avatar/wallpaper persistence before and after jailbreak and a
   full reboot. Verify Sileo and existing tweaks still work.
6. Accept this UI batch before separately porting settings/about styling and
   reviewing authorization initialization and failure behavior.

## Hosted-runner scheduling follow-up: 2026-11-04

The first full glass build, run #14 (41679764405), never acquired a machine.
The build job waited from 00:59:35 to 01:14:37 Asia/Shanghai, with no executed
steps. GitHub reported: "The job was not acquired by Runner of type hosted
even after multiple attempts", alongside the macOS ARM64 capacity notice.
This was a runner-allocation failure, not a native compiler result.

Run #12's successful logs identify `macos-26-arm64` and Xcode 26.6. The
workflow used `macos-latest` and `latest-stable`, so this was the newest stable
Xcode installed in that image, not necessarily Apple's latest release.

To change one variable at a time, switch to the documented standard
`macos-26-intel` runner and explicitly pin Xcode 26.6, which is listed in
that image. This keeps the tested OS/Xcode generation while changing the
host architecture. It does not revert to RC9's Xcode 16.4 or alter the iOS
16.0 deployment target/Theos iOS 16.5 SDK.

The workflow now verifies the actual X64 architecture and Xcode version
before dependency installation. It records the image, architecture, actual
Xcode build, developer directory and Xcode iPhoneOS SDK in build provenance.
The Theos cache already includes architecture, so ARM cache contents are
not reused for Intel. The first Intel build may need a fresh dependency
cache. This change does not guarantee zero queue time or a shorter compile.

Added two source-contract checks (31 total). No app/UI, authorization,
jailbreak engine, signing, bootstrap or package data changes accompany this
runner adjustment. At this checkpoint, a full Intel native build and device
validation were still required.

Run #16 (41683288432, source `fad56fe6`) acquired `macos-26-intel` in about
11 seconds. X64/Xcode 26.6 verification, the source contracts and native
plist/project checks passed. This verifies allocation for this attempt,
not a guarantee that future jobs never queue.

That build then exposed a separate native compiler error:
`DOCustomGlassView.m` called `DOLocalizedString` without importing its
declaration. Added the owning `DOUIManager.h` import and a regression check
(32 source checks total). This is a first-port extraction error, not an
Xcode-version or Intel compatibility error. Run #16 did not produce an
installable package; the corrected source was verified in run #18 below.

## Verified full glass build

- Run #18: `41687922330`.
- Source: `a8e736ef812a6900dda2088456afbf5c36ede7b4`.
- Workflow: `build_RootHide_iOS16`, branch `ios16-roothide-3.0.12`.
- Result: success; the build job took 9 minutes 15 seconds.
- `macos-26-intel`, actual X64 architecture and Xcode 26.6 checks passed.
- All 32 source-contract tests and native plist/project checks passed.
- Full native build, scripted IPA verification, IPA/TIPA artifact uploads
  and dependency-cache post steps all succeeded.
- Scripted package verification covers ZIP integrity, RootHide identity,
  minimum iOS 16.0, required payloads, excluded Zebra/non-16 packages and
  byte equality of the IPA and TIPA.
- Artifacts remain on GitHub Actions. No local package was downloaded or
  substituted during this verification.

This closes the observed runner-allocation failure and native compilation
gate for this source. It does not guarantee that Intel jobs never queue,
that future builds finish in three minutes, or that the glass layout/media
lifecycle works correctly on the device. Device testing and the deferred
settings/about styling and authorization work remain separate.

Retain source `1754adf69c60b88fb034928e1cf8949e3dd8391d` and its known-working
31,125,127-byte TIPA as the rollback reference. Do not uninstall RC9's
jailbreak or delete bootstrap roots/package databases for a UI test.

## Device feedback follow-up: settings and missing reboot copy

The user reported that Settings had no glass material or visible return
button. This was an incomplete first-batch port: Settings retained its
opaque compact modal while the app's navigation bar remained hidden.

Local follow-up changes:

- Treat only `DOSettingsController` as a full-screen glass page; other native
  modal controllers and selection-page return headers retain their behavior.
- Add an always-available 44-by-44-point accessible back button and left-edge
  return gesture. Reserve space below the safe area so list content cannot
  cover the button.
- Reuse the extracted RC9 material for one noninteractive glass backdrop per
  settings section. Keep cells transparent, preserve native controls, refresh
  reused cells and remove stale section backdrops after specifier changes.
- Refresh glass on appearance/theme changes and remove the theme observer
  during deallocation.
- Restore the missing `Menu_Reboot_Device_Title` and
  `Alert_Reboot_Device_Body` strings from RC9 in English and both Simplified
  Chinese localization directories.
- Fingerprint all original settings methods from exploit enumeration through
  the final action against the pre-edit source; they remain unchanged.

The user's RC9/new-build screenshots also show a denser diagnostic header,
different header alignment and a lower jailbreak bar in the new build.
The new build retains ZQBB system/injection/build information and uses its
bounded content layout plus an update reserve; these are not a pixel-identical
RC9 home layout. No home-layout changes, personal-data imports, supporter
badge or authorization changes are included in this follow-up.

Local source checks: 38 tests pass, including settings-navigation, section
material, original-method fingerprints and reboot-localization checks.
`git diff --check` passes. This follow-up is not yet committed, pushed,
natively compiled or device-validated; run #18 predates these fixes.

## User-requested RC9 home-layout alignment

The user requested the original RC9 title/panel positioning and only version,
author and uptime beneath the logo. The username and motto are user-editable
profile data, not values to import or hardcode from the reference screenshot.

Local changes:

- Remove the extra system/injection/build-version/build-time rows from Home.
  Keep the existing truthful `versionSupportString`; do not invent a wider
  device support range or change compatibility checks.
- Display the three-line version/author/uptime block compactly and centered
  beneath the centered Dopamine logo. The lines share a left edge; their
  natural width is capped to the available header width instead of being
  frozen to one measured uptime string.
- Restore RC9's safe-area centering, phone side insets, iPad width bounds,
  panel dimensions, reserve-minus-grid-drop spacing and negative jailbreak-bar
  offsets. Remove the whole-page wrapper that stretched to the available
  screen height and altered the reference positions.
- Keep avatar docking and gesture coordinates tied to the physical root
  view edges. Focus mode fades the header information and profile text without
  collapsing their layout space. The logo and action panels remain in place;
  tapping the docked avatar or dragging inward restores the text.
- Retain username/motto tap editors, limits and persistence. Seed editors
  from the actual saved input rather than the displayed fallback placeholders.
  Do not overwrite saved personal data or import RC9 media automatically.
- Keep the continuous-time uptime calculation, minute-aligned weak timer and
  page/application lifecycle cleanup. Refresh the plain label text without
  resetting RC9's subtitle font scaling.
- Preserve the other-jailbreak guard, root-coordinate button expansion and
  existing jailbreak execution/button-title method fingerprints.

Design suggestions only, not added in this follow-up: light feedback on
edge docking, a larger invisible return hit area, reduced-motion handling
and an optional non-gesture focus toggle. Do not hide all action panels or
introduce a new layout while matching RC9.

Verification: 43 local source-contract tests pass; `git diff --check` passes.
The tests cover the requested three-line header, RC9 layout constants,
root-view docking, profile editing and the previous settings fixes. No
Xcode/UIKit runtime is available on this Windows host, so this is not a
pixel-match or device-rendering result. Native compilation and fresh
device screenshots are still required, particularly on compact screens.

## About navigation follow-up (2026-11-04)

The user confirmed that Settings now has a return button, but About still
does not. About uses `DOCreditsViewController`, which retained the native
compact modal without its own navigation control while the shared system
navigation bar is hidden.

- Add a fixed, accessible 44-by-44-point back button outside the scrolling
  Credits table. Reserve safe-area space above the list.
- Add left-edge return with the same distance/direction threshold as
  Settings. Both actions pop only the current controller.
- Preserve About's compact native presentation and all original specifiers,
  credits and actions. This is a navigation fix, not an About glass redesign.
- Inspect the existing License header and its one-level return to Credits;
  leave that working route unchanged.
- Fingerprint the original Credits methods to detect unintended changes.

Verification: all 45 local source-contract tests and `git diff --check`
pass. Windows has no Xcode/UIKit runtime, so native compilation and device
verification of About and License navigation remain required.

The preceding full build #20, run `41693553004`, completed successfully for
`a6067091695d715757fd28409b6a150db271f682`. It does not include this About
follow-up; a package built from the new commit is required.

## User-requested About glass follow-up (2026-11-04)

The user requested About glass during the health audit. This supersedes the
earlier decision to keep About compact and native-styled.

- Make only Settings and Credits full-screen glass pages; License and other
  Preferences subpages retain their original framing and return controls.
- Keep the fixed 44-point back button, reserved safe-area navigation row and
  left-edge return gesture.
- Make the page/table transparent over the existing shared wallpaper and add
  noninteractive section surfaces using the existing RC9 material renderer.
- Include native group-header rectangles even when a section has zero rows:
  Credits stores its contributor collections in `headerCellClass` entries.
- Preserve Credits.plist, original business methods, contributor collection
  delegates, source/Discord links and the License route. Clear nested button
  chrome without replacing their actions.
- Refresh appearance during layout, content reuse, return navigation and theme
  changes; remove obsolete section surfaces and unregister the theme observer.

Verification: 48 local source-contract tests and `git diff --check` pass.
These are structural checks, not proof of UIKit rendering or performance.
Build #22 passed for the preceding `851480cc` source, not these new changes.

See `HEALTH-AUDIT-2026-11-04.md` for six open P2 findings in the earlier UI
port. They are recorded separately, not silently fixed in the About styling
change. Do not treat green source checks as confirmation that those runtime
or layout risks have been resolved.

## About continuous glass surface (2026-11-04)

The device screenshot showed the About page broken into separate glass
surfaces with exposed wallpaper gaps. This came from creating a separate
backdrop for each Preferences table section.

- Replace per-section backdrops with one noninteractive glass surface behind
  the full visible table viewport.
- Keep the existing section headers, contributor collections, links,
  source/Discord/License actions, scrolling and independent back navigation.
- The single surface stays fixed while the table content scrolls and is
  resized with the table frame; theme changes reload its material.

All 68 local source-contract tests pass and `git diff --check` is clean.
This host has no Xcode/UIKit renderer, so device appearance still needs a
fresh build and screenshot review.

## TIPA-only delivery follow-up (2026-11-04)

The user confirmed that iOS 16 does not need a separate IPA artifact.

- Make's default target now creates `Dopamine.tipa` directly from the built
  app; it no longer creates an IPA and copies it to a second filename.
- The Actions job validates the TIPA archive and its iOS 16 contents, then
  uploads one `RootHide_iOS16_TIPA` artifact with build provenance and package
  inspection files.
- Remove the separate IPA rename, verification/comparison and upload steps.
- Add source-contract coverage so a later workflow or Makefile edit cannot
  silently restore IPA delivery.

All source-contract tests and `git diff --check` pass locally. This Windows
host cannot run the pinned macOS/Xcode native build. A fresh manual Actions
build is still needed to validate the revised archive target and uploaded
artifact.

## Titan iOS 16.6 failure follow-up (2026-11-04)

Two device logs from `iPhone15,2`, iOS 16.6 (20G75), fail at the same
`Bypassing PPL (Titan)` stage with `JBErrorDomain Code=-4`. Kernel exploit
startup and the preceding kernel information output complete.

Comparison against the pre-pruning source found an iOS 16 regression in
Titan's `proc_find_by_name`: the iOS-only pruning had replaced the XNU
generation check with a fixed `0x381` process-name offset. The original code
uses `0x579` when the XNU major version is greater than 8792. The newer layout
is still part of iOS 16, so deleting this branch was incorrect; with the
wrong offset Titan cannot locate `backboardd` and its IOGPU user client.

- Restore the XNU-version-dependent `0x579` / `0x381` selection using the
  existing iOS 16 Titan version decoder.
- Add a source-contract regression test for this selection.
- Do not classify this as a wallpaper issue or ask the user to keep retrying
  the unchanged build.

All 70 source-contract tests and `git diff --check` pass. A fresh macOS/Xcode
build and device validation are still required; these structural tests cannot
execute Titan on the target hardware.
