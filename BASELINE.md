# ZQBB RootHide baseline

Last updated: 2026-11-04

## Source identity

- Local directory: `G:\RootHide\ZQBB IOS16\Dopamine-roothide-ios16`
- Upstream: `https://github.com/w2599/Dopamine.git`
- Upstream branch: `3.x_roothide`
- Base commit: `18049d5a81b294d3387b3af30c54558d04b8b5f5`
- Working branch: `ios16-roothide-3.0.12`
- Version files: `3.0.12` and RootHide revision `29`.
- Target repository: `https://github.com/kulinichx/ios16-only-3.0.12.git`

The GitHub release tagged `3.0.12` contains both traditional rootless and
RootHide IPA attachments. Its automatically generated source archive refers
to tag commit `e6810c1d`, from the rootless branch `3.x_modify_`; it is not the
RootHide source baseline.

The selected RootHide branch has the expected version and implementation.
This does not establish byte-for-byte correspondence with a published IPA.
The clone has its own Git object store and does not depend on the old local
rootless repository.

## RootHide evidence

- `Application/Dopamine/Jailbreak/DOBootstrapper.m` implements both
  `DOBootstrapper(roothide)` and `DOEnvironmentManager(roothide)`.
- Root discovery uses `.jbroot-*` under
  `/var/containers/Bundle/Application`, with a secondary root under
  `/var/mobile/Containers/Shared/AppGroup`.
- The app identifier is `cn.zqbb.dopaRH`.
- Packaging includes `Dopamine.roothide` and `libroothider.dylib`.
- Building requires the RootHide fork of Theos.

The legacy rootless code remains in the upstream tree; inspecting that code
alone does not identify the active RootHide category overrides.

## Dependency commits

All tracked submodules, including nested dependencies, are initialized:

| Path | Commit |
| --- | --- |
| `BaseBin/ChOma` | `7dccded6bc17081c08f5f5cdbd7a4b051543a825` |
| `BaseBin/XPF` | `9e12b8faa7444f6fe7f699aec6b6c96d151455d3` |
| `BaseBin/XPF/external/ChOma` | `7dccded6bc17081c08f5f5cdbd7a4b051543a825` |
| `BaseBin/XPF/external/img4lib` | `69772c72f3c08f021ec9fa4c386f2b3df60a38b7` |
| `BaseBin/XPF/external/img4lib/lzfse` | `88e2d2788b4021d0b2eb9fe2d97352ae9190f128` |
| `BaseBin/_external/modules/litehook` | `4f062946a964575694878130acecb7c990baba38` |
| `BaseBin/opainject` | `0068566501f3ddd04830f1ef0f1b74a8d1512281` |

## Build configuration

The original baseline preparation changed CI and documentation only.
The initial baseline at commit `1caaf2f7` was subsequently built successfully
on GitHub Actions. The iOS 16 slimming pass below changes runtime and package
resources on top of that baseline. Its full native build at `1754adf6`
succeeded, and the user reported initial device success; see the validation
snapshot below for the scope and remaining checks.

The workflow at `.github/workflows/build.yml`:

- Checks out the selected repository/ref with recursive submodules. The old
  upstream workflow explicitly checked out `roothide/Dopamine-roothide`
  instead, which could build different code from the intended fork.
- Installs RootHide Theos and extracts the iOS 16.5 SDK as xz.
- Caches Theos and the SDK separately from the old rootless build.
- Sets `BUILD_TIMESTAMP`, and builds the host trustcache tool for the
  runner's architecture.
- Runs source-contract checks, validates the Xcode/plist syntax on macOS,
  verifies RootHide source categories and submodule revisions, then checks
  the package's required/excluded files, app identity and iOS 16 minimum.
- Uploads separate IPA/TIPA artifacts, with source/tool/dependency provenance
  the IPA/TIPA SHA256 and a package size listing included in the IPA artifact.

The default branch is `ios16-roothide-3.0.12`. Use Actions workflow
`build_RootHide_iOS16` at path `build.yml`. The branch can also be selected
explicitly with:

```sh
gh workflow run build.yml --repo kulinichx/ios16-only-3.0.12 --ref ios16-roothide-3.0.12
```

Push events run inexpensive source checks; a full macOS build is manual. The first
build must provision its tools and SDK, so no three-minute build time is
promised.

Local checks: `git diff --check`, recursive submodule status, and actionlint
1.7.12 passed. Shellcheck and pyflakes were disabled because they are not
installed. No native Xcode build or device test has been performed for this
baseline on this Windows machine. The baseline's successful cloud build is
not validation of subsequent slimming changes.

## iOS 16 slimming pass

Completed source changes:

- Removed Zebra's deb, icon, license display, package-manager option, source
  creation and Xcode resource references. This does not uninstall a
  user-installed Zebra or delete its data on the phone.
- Replaced the broad `Resources/*.deb` copy with an explicit list containing
  Sileo, the RootHide manager and the whitelist manager. Generated libroot,
  libkrw and basebin-link packages remain Xcode resources.
- Removed custom mount installation UI and automatic `HelloMntDaemon`
  replay/marker creation. Existing on-device mount packages/configuration
  are not automatically removed, and essential RootHide mounts are retained.
- Removed the TrollStoreLite Fix UI, setting/serialization field, pre-spawn
  auto-trust and TXM session/lease modules, including their otherwise unused
  standalone TXM trust helpers.
- Preserved normal TrollStore classification, required code signing and
  generic RootHide trust paths. Passive recognition of old `_TrollStoreLite`
  markers remains in shared classification/signature code so an existing
  Lite app is not misclassified or unexpectedly re-signed. This is not an
  installer or the removed Lite launch fix.
- Set the app/project minimum OS to 16.0. Both the UI support check and the
  activation entry reject non-16 major versions before exploit execution.
  Individual exploit device/version restrictions still apply; this does not
  claim support for every iOS 16 device/version.
- Simplified app-level SPTM/PAC checks and removed the iOS 15 spinlock branch
  from the modified launchd spawn path.
- Removed the old iOS 15 bootstrap file and extra post-iOS-16 launchctl debs.
  Excluded the iOS-15-only badRecovery framework at packaging time.
- Left the MB-additive Jetsam algorithm and its user configuration unchanged.

Local validation: 11 Node source-contract tests, the package-manager XML
parse, actionlint 1.7.12, and `git diff --check` passed. The tests check source
connections and resources, not actual iOS process behavior.

Size reference: the baseline TIPA measured 34.74 MiB locally. Its compressed
Zebra payload alone was 4.88 MiB. The slim TIPA at `1754adf6` measures
31,125,127 bytes (29.68 MiB), approximately 5.06 MiB smaller. Removing the
iOS 15 bootstrap from the source tree does not save a further 18.50 MiB in
the IPA, because it was already not packaged.

## Validated snapshot: 2026-11-04

- Full manual build: `1754adf69c60b88fb034928e1cf8949e3dd8391d`.
- Successful GitHub Actions run:
  `https://github.com/kulinichx/ios16-only-3.0.12/actions/runs/41671702364`.
  It ran from 2026-11-04 00:11:59 to 00:25:32, Asia/Shanghai.
- Locally inspected package:
  `G:\RootHide\ZQBB IOS16\TIPA\roothide-Dopamine-(3.0.12-29-1754adf)-.tipa`.
  Its filename identifies this commit; artifact identity was not independently
  verified by a provenance hash in this check.
- The package contains Sileo, the RootHide manager and whitelist manager
  debs. Its entry names contain no Zebra, bootstrap1800, palera1n,
  badRecovery or extra launchctl deb payloads.
- User-reported initial device result: the new package is installed,
  previously installed tweaks remain present, and those tweaks take effect.
  This is user feedback, not an independently observed device test.
- Still unverified: device/iOS build details, repeat full-reboot jailbreak
  cycles, settings persistence, long-running stability, measured Jetsam
  behavior, and comprehensive RC9 migration/rollback behavior.

Keep this source commit and package as the initial known-working reference.
Port the glass UI separately from authorization so each change can be
tested against this reference.

The initial RC9 UI source comparison is recorded in
`RC9-UI-PORT-AUDIT.md`. It identifies the active glass material, uptime
presentation, single-theme resources, authorization coupling and the
cross-app theme/media persistence boundary. This is an audit, not a completed
runtime UI port. The subsequent first-batch implementation and its separate
validation status are recorded in `RC9-UI-PORT-STATUS.md`. Do not treat the
glass build as device-validated merely because the earlier slim build was.

## RC9 UI first batch: 2026-11-04

The first batch ports the RC9 glass homepage, appearance editor, profile,
static/video/Live Photo wallpaper, localized uptime and primary app icon.
Only the purple fallback theme remains. App identity stays `cn.zqbb.dopaRH`;
authorization, exploit execution, bootstrap, signing and Jetsam are unchanged.
Settings/about retain the target's native content and modal styling.

Theme preferences use an independent `DopamineRH-iOS16` snapshot directory.
RC9's existing media/preferences are not imported or overwritten; select the
wallpaper and avatar again in this app.

Initial local validation used 29 Node source-contract tests, icon
file/hash/dimension checks, XML parsing, actionlint and `git diff --check`.
After two runner checks and one localization-import regression were added,
all 32 tests and full Intel native build #18 passed for source `a8e736ef`.
Its scripted package verification and IPA/TIPA uploads also succeeded.
Actual package-size comparison and device regression remain required;
see `RC9-UI-PORT-STATUS.md`. The earlier slim build remains the user-tested
device reference; native compilation alone does not validate the glass UI.

## Compatibility and remaining work

This is an iOS-16-restricted slimming pass, not a claim that every non-16
branch has been deleted. Low-level shared compatibility branches, offsets,
exploit metadata/targets and signed-installation fallback flows still need
separate dependency review. Do not remove code merely because it uses the
word "rootless", "signing" or a historical version constant.

RC9 source is preserved at `G:\RootHide\runtime-rc9-audit`. Its
`DOPAMINE_INSTALL_VERSION` is 2; this baseline uses 3. The new source can
discover and rerandomize an existing RootHide installation and replace
basebin. The two apps are not proven to have isolated bootstrap state.
The user now reports that existing tweaks remain and work with this build.
That is initial compatibility evidence for this device, not a comprehensive
migration/rollback audit or a guarantee for other configurations.

Do not bypass duplicate-app checks or manually delete Sileo, preboot roots,
or `.jbroot-*` directories. If removing the unintended rootless test
environment, first fully reboot out of RC9 and use that rootless app's own
Remove Jailbreak operation; preserve the RC9 installation.

Next work:

1. Complete a short device regression: full reboot and re-jailbreak, Sileo
   and tweak availability, settings persistence and ordinary use. Do not
   remove the current jailbreak environment as a regression step.
2. Finish the RC9 migration/rollback review and compare the existing
   MB-additive Jetsam implementation with RC9. Keep the current algorithm
   unchanged unless the review establishes a concrete defect.
3. Port RC9 glass UI without changing bootstrap, package data, signing,
   exploit behavior or authorization in the same change.
4. Integrate authorization separately after the glass build is verified.
   Audit initialization order and failure behavior before enforcing it.
5. Review remaining non-16 paths and optional assets only where dependency
   analysis shows they are unused; retain required iOS 16 components.

At the user's request, the old rootless branch `ios16-only-3.0.12` was deleted
from the target GitHub repository and the old local checkout. The old
directory `G:\RootHide\ZQBB IOS16\Dopamine-3.0.12-full` remains as historical
source in detached HEAD state. Its runtime changes have not been copied into
this baseline. Deleting Git branches does not remove an on-device jailbreak
environment.
