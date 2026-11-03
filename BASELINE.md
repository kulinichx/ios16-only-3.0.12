# ZQBB RootHide baseline

Last updated: 2026-11-03

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
resources on top of that baseline; that pass still needs a new native build
and device validation.

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
Zebra payload alone was 4.88 MiB. A result near 30 MiB is an estimate until a
new IPA/TIPA is built. Removing the iOS 15 bootstrap from the source tree does
not save a further 18.50 MiB in the IPA, because it was already not packaged.

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
Source review must establish migration behavior before using this baseline
to jailbreak over the user's existing RC9 environment.

Do not bypass duplicate-app checks or manually delete Sileo, preboot roots,
or `.jbroot-*` directories. If removing the unintended rootless test
environment, first fully reboot out of RC9 and use that rootless app's own
Remove Jailbreak operation; preserve the RC9 installation.

Next work:

1. Audit RC9-to-baseline root discovery, rerandomization, installed-version
   handling and basebin replacement.
2. Build and inspect the slim IPA/TIPA, then review remaining low-level
   non-16 paths, exploit targets, signed-installation fallback flows and
   optional theme assets without changing the required iOS 16 components.
3. Compare the existing MB-additive Jetsam implementation with RC9. This
   upstream branch already offers MB settings; do not blindly port a second
   implementation.
4. Port RC9 glass UI and authorization features after core behavior is
   verified.

At the user's request, the old rootless branch `ios16-only-3.0.12` was deleted
from the target GitHub repository and the old local checkout. The old
directory `G:\RootHide\ZQBB IOS16\Dopamine-3.0.12-full` remains as historical
source in detached HEAD state. Its runtime changes have not been copied into
this baseline. Deleting Git branches does not remove an on-device jailbreak
environment.
