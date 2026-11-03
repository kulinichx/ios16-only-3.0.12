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

The initial preparation changes CI and documentation only. Runtime code and
bootstrap resources remain as provided by the upstream base commit.

The workflow at `.github/workflows/build.yml`:

- Checks out the selected repository/ref with recursive submodules. The old
  upstream workflow explicitly checked out `roothide/Dopamine-roothide`
  instead, which could build different code from the intended fork.
- Installs RootHide Theos and extracts the iOS 16.5 SDK as xz.
- Caches Theos and the SDK separately from the old rootless build.
- Sets `BUILD_TIMESTAMP`, and builds the host trustcache tool for the
  runner's architecture.
- Verifies RootHide source categories, submodule revisions, the packaged
  RootHide marker/library, and the app's bundle identifier.
- Uploads separate IPA/TIPA artifacts, with source/tool/dependency provenance
  and the IPA SHA256 included in the IPA artifact.

The default branch is `ios16-roothide-3.0.12`. Use Actions workflow
`build_RootHide_baseline` at path `build.yml`. The branch can also be selected
explicitly with:

```sh
gh workflow run build.yml --repo kulinichx/ios16-only-3.0.12 --ref ios16-roothide-3.0.12
```

Push events only register the workflow; a full build is manual. The first
build must provision its tools and SDK, so no three-minute build time is
promised.

Local checks: `git diff --check`, recursive submodule status, and actionlint
1.7.12 passed. Shellcheck and pyflakes were disabled because they are not
installed. No native Xcode build or device test has been performed for this
baseline on this Windows machine.

## Compatibility and remaining work

This is a source baseline, not a completed iOS 16-only product. It still
contains upstream compatibility code, Zebra, custom mount management and
TrollStoreLite-related code.

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
2. Scope iOS 16-only changes and remove Zebra, ZQBB custom mount management
   and unnecessary TrollStoreLite flows on this verified RootHide branch.
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
