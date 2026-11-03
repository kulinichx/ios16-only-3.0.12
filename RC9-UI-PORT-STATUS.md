# RC9 UI port: first batch

Date: 2026-11-04

Target: `G:\RootHide\ZQBB IOS16\Dopamine-roothide-ios16`
Reference, read only: `G:\RootHide\runtime-rc9-audit`
Branch: `ios16-roothide-3.0.12`
Remote: `ios16-target` (`kulinichx/ios16-only-3.0.12`)

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
  29 source-contract tests pass.
- RC9 primary-icon SHA-256 equality, PNG headers and catalog pixel sizes pass.
- Themes/package-manager XML parses and actionlint 1.7.12 passes.
- `git diff --check` passes.
- New material source and required system frameworks are in the app's actual
  Xcode build phases; source checks detect duplicate project object IDs.
- Jailbreak execution and button-title method fingerprints match the tested
  `1754adf69c60b88fb034928e1cf8949e3dd8391d` baseline.

These are Windows/source checks, not an Objective-C native build or UIKit
rendering test. Full native compilation, packaged-resource inspection and
actual compressed TIPA size for this batch are not yet verified. The icon
artwork increases source bytes; deleting old theme assets does not establish
a particular compressed-package saving.

## Next validation

1. Manually run `build_RootHide_iOS16` on `ios16-roothide-3.0.12` in GitHub
   Actions. A push runs source checks only, not the full macOS build.
2. Inspect the resulting package's icon/resources and compare its actual size.
3. Device-test cold launch, the RC9 home-screen icon, all entry cards,
   compact-screen layout, update-button spacing and jailbreak log expansion.
4. Test static/video/Live Photo imports, cancellation/failure, playback speed,
   background/foreground, navigation and replacement-window cleanup.
5. Test theme/avatar/wallpaper persistence before and after jailbreak and a
   full reboot. Verify Sileo and existing tweaks still work.
6. Accept this UI batch before separately porting settings/about styling and
   reviewing authorization initialization and failure behavior.

Retain source `1754adf69c60b88fb034928e1cf8949e3dd8391d` and its known-working
31,125,127-byte TIPA as the rollback reference. Do not uninstall RC9's
jailbreak or delete bootstrap roots/package databases for a UI test.
