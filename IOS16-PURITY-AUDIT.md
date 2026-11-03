# iOS 16 source pruning audit

Status: source-pruning candidate with passing local static checks.
Native-build and device acceptance remain pending. The source parent is
`72e77482c41793f545019377a0e92099c0aba9eb` on
`ios16-roothide-3.0.12`. This audit supersedes the earlier
packaging-only exclusions, not the known-working device baseline.

## Scope and important limits

This pass removes non-16 application/runtime implementations and their
first-party build targets, rather than just deleting their compiled output
from the IPA. It does not promise that every version-related string in every
third-party dependency has disappeared.

The Git submodule commit pins are unchanged. ChOma, opainject and litehook
keep their general-purpose implementations. XPF is now specialized before
compilation by the parent-controlled `scripts/prepare-xpf-ios16.cjs`, pinned
to upstream commit `9e12b8faa7444f6fe7f699aec6b6c96d151455d3`.
Its old bad_recovery and sptm_txm source/header pairs are physically deleted
from the working dependency tree; old/new OS set selection and unused kcall
finders are removed. Only ten iOS 16 metric sets remain. The library rejects
non-Darwin-22 kernelcaches and non-NULL monitor image arguments.

The preparation runs in both CI jobs and the BaseBin build, so a fresh clone
does not silently compile the complete upstream XPF. It reconstructs from
the locked Git source, validates all affected files before mutation, rejects
unrelated edits/unexpected source files, and is idempotent. The local XPF
submodule therefore intentionally appears dirty; its changes are reproduced
by the parent script, not an unpublished submodule commit. Run preparation
before manually invoking the source tests on a fresh recursive checkout.

The public XPF header, three-argument entry API and reserved structure slots
remain unchanged for ABI compatibility. The old SPTM/TXM field names in that
header are not a live implementation: no corresponding image loading,
patchfinding or set dispatch remains. Generic Mach-O/IMG4 parsers and
instruction-encoding discovery still serve iOS 16 and are not stripped just
because the upstream library can parse formats used by another OS.
Do not claim every version-related string or shared library ABI slot has
been erased from the recursive checkout.

An iOS 16 deployment target/entry guard also does not establish support for
every iOS 16 release or device. The retained exploit restrictions still apply.

## Physically removed

- `Application/Dopamine/Exploits/badRecovery`
- `Application/Dopamine/Exploits/weightBufs`
- `Application/Dopamine/Exploits/multicast_bytecopy`
- `Application/Dopamine/Exploits/palera1n`
- Their Xcode native targets, groups, products, dependencies and embedding
  references. There are no empty exploit-directory placeholders.
- The kfd IOSurface R/W backend, its dispatch cases and its old offset fields.
- The iOS 15 IOSurface allocation implementation and backboardd method.
- `BaseBin/hookd`, its local providers/clients, and its memory-hook helpers.
- Standalone TXM, stock_fixes, arm64 kcall and Fugu14 kcall implementations,
  including the Fugu14 assembly companion.
- The active palera1n hook loader and `.installed_palera1n` marker updates.
- Generated dyldhook iOS 15 / iOS 18 task sources, the spinlock fix,
  fake-library redirect and the disabled forkfix reimplementation.
- XPF's bad_recovery/sptm_txm implementation/header pairs and their build
  registration, old trustcache finders, obsolete metric sets and unused
  kcall/thread-security/trigon finders.

The remaining exploit frameworks are exactly ClearSword, DarkSword, Titan,
dmaFail, kfd and momentarius. Retaining these does not mean all are selected
on every device. Each keeps its own iOS 16 range/device restrictions,
including the original applicable beta-build exceptions.

## Runtime specialization

- Removal/post-exploitation no longer contains iOS 17/18-only branches.
- Settings switch styling no longer uses the original literal
  `@available(iOS 19.0, *)` condition in
  `UI/Settings/PSLists/DOPSListController.m`. Its adjacent comment refers
  to iOS 26.0+, so calling this an "iOS 19 adaptation" was imprecise:
  it was a higher-version UI condition, not evidence of iOS 19 support.
  The original iOS 16 branch and its switch tint remain unchanged.
  Log startup no longer contains the post-16 logging path.
- Kernel offsets now live in `BaseBin/libjailbreak/src/offsets_ios16.c`.
  Only the Darwin 22.x specialization is retained.
- kfd uses sem_open and its iOS 16 mapping offsets; A9 retains its required
  160-page setting.
- Titan loses A17/newer mappings, the post-16 stack adjustment and newer-XNU
  IPC branches. Its iOS 16.3 beta/SMR distinction remains.
- ClearSword and DarkSword lose A18 dispatch, unused state and disabled A18
  implementations. The non-A18 iOS 16 path is preserved.
- Device-family definitions/mapping no longer include A8, A17, A18, M3 or
  M4. The A8-only home alert and its localization entries are removed.
- proc/task/ucred, trustcache, address translation, PTE and hook paths use
  their iOS 16 layouts; SPTM/TXM-specific schema fields are removed.
- The iOS 15 spinlock RPC endpoint and hookd message handling are removed
  without renumbering surviving IPC commands.
- iOS 18.4 shared-region environment changes and the newer dyld `gAPIs`
  fallback are removed. The iOS 16 path remains.
- dyldhook builds, selects and packages exactly two variants: arm64 and
  arm64e, both compiled with `IOS=16`. Their existing `iOS16-17` filenames
  are intentionally preserved; the filename does not enable an iOS 17
  build or activation path.

## Required retained functionality

- RootHide identity `cn.zqbb.dopaRH`, version 3.0.12 / RootHide revision 29,
  bootstrap discovery/migration, rerandomization and existing tweak data.
- Sileo, the RootHide manager, the whitelist manager and the iOS 16 bootstrap.
- The existing MB-additive Jetsam implementation and user settings.
- The RC9-derived glass UI, icon, editable profile, wallpaper and uptime.
  This pass does not introduce authorization behavior.
- Required signing, trustcache and normal TrollStore classification.
  A generic function is not obsolete just because TrollStore installs the app.
- The timestamp-preservation operation after rewriting a file signature:
  this is kept as generic file-integrity behavior, even though its upstream
  comment explains a newer dyld motivation.
- Passive classification of old TrollStoreLite/palera1n apps, to avoid
  accidentally treating them as normal App Store apps. No Lite installer,
  Lite launch fix or active palera1n exploit is restored.
- DarkSword's five required IOSurface/IOKit helpers are in its own local
  `IOSurface_helpers.h`. They are derived from kfd/weightBufs, so their
  attribution and `LICENSE_weightBufs.md` remain. A retained license is not
  a retained exploit.
- Host SDK compatibility, including using a newer Xcode SDK to compile an
  iOS 16 deployment target.

No phone files, `.jbroot-*` installations, Sileo databases, package data,
preboot roots or RC9 source were changed by this local editing operation.
The pre-existing bootstrap migration routines still run when the user
later installs/activates a build; their presence is not a rollback guarantee.
Other historical checkouts/downloads outside `Dopamine-roothide-ios16` are
not build inputs and have not been deleted as part of this operation.

## Build and regression checks

- Framework packaging uses a six-framework allowlist and fails if an
  unexpected framework appears. It is not a post-build hiding mechanism.
- CI checks the outer IPA and extracts the inner `basebin.tar`, verifying
  the two dyldhooks and absence of the retired runtime payloads. It also
  checks exported symbols in the packaged libxpf and records the prepared
  XPF source digest in build provenance.
- Node source contracts cover the Xcode object graph, physically removed
  directories, metadata, version guards, surviving field references, local
  includes, stable message IDs and UI wiring.
- The offset-assignment model compares 144 combinations of Darwin 22.x,
  A9-A16 family, arm64/arm64e, EL1/EL2 and the relevant proc sizes against
  the pre-pruning baseline. Aggregate SHA256:
  `ab5d4bde72e285447fc4e3812e211592c7f0a4774fe4a69c372888c38be6f06b`.
  This is a source-level assignment model, not a kernel simulator.
- All ten retained XPF metric lists match the upstream iOS 16 selections.
  Registration models compare 28 PPL/non-PPL architecture/Darwin-22
  combinations. A test prepares a pristine local XPF clone, repeats the
  operation, verifies the digest and confirms unrelated edits are refused.
- Prepared XPF source digest (six changed files and four removed files):
  `33146b2a9e12f1f3eeba1426580e45e4e6b51dae5158f7cd60c3d1c8bd2b45c3`.
- Run locally:
  `node scripts/prepare-xpf-ios16.cjs`,
  `node --test tests/ios16-contracts.test.cjs tests/glass-ui-contracts.test.cjs`
  and `git diff --check`, plus `git -C BaseBin/XPF diff --check`.
  Metadata XML is also parsed locally. Record the
  actual final result in the handoff; do not infer a native build from it.

Local result for this pass: all 68 Node source-contract tests pass, all six
exploit metadata files parse as XML, and both `git diff --check` commands pass.
Recursive submodule commits remain at the original pins, with the intentional
prepared XPF working-tree edits described above. No local actionlint executable
or Apple native compiler was available, so neither an actionlint rerun nor a
native compilation is claimed for this pass.

## First native-build failure and correction

Native run `41711594213` for source `7d6a3874` failed while linking
`libjailbreak.dylib`: `_gUserReturnDidHappen` was referenced by `_pac_loop`
in `kcall_Fugu14-arm64.o`. The Fugu14 C implementation had been removed,
but its assembly companion `src/kcall_Fugu14.S` was inadvertently retained
and matched the Makefile's `src/*.S` wildcard. This was a pruning omission,
not a runner or Xcode selection failure.

The assembly companion is now removed instead of restoring the obsolete
implementation or adding a dummy symbol. A regression check explicitly
covers the libjailbreak C, Objective-C and assembly wildcard inputs while
preserving the required `inline_svc.S`. The earlier static suite did not
cover this assembly dependency; passing source checks did not establish
link correctness. The corrected candidate still needs a new native build.

The follow-up native run reached the application build and then failed
because `DOJailbreaker.m` used `pthread_create` and `pthread_detach` without
including `<pthread.h>`; the old build had obtained that declaration
indirectly. The explicit import is now restored and covered by a source
contract. The `install_name_tool` messages earlier in that run were
non-fatal commands already guarded by `|| true`.

The next run (`41718579585`, source `74549b2d`) completed the native build
successfully, then failed at the IPA framework allowlist comparison. The
actual list was sorted, while the expected list was not; the two equivalent
six-framework sets therefore compared unequal. The workflow now sorts both
sets identically, and the source contract guards that normalization. This
was a packaging-verification script failure, not a compiler or IPA-content
failure; the IPA content checks before this comparison had passed. A rerun
is still required to complete the remaining inner-archive checks and upload.

## Remaining acceptance work

1. Native Intel macOS/Xcode build of this exact source revision. Windows
   does not provide the required Apple toolchain in this session.
2. Inspect the produced IPA and inner archive using the CI checks. Package
   size and build-time improvement have not been measured for this pass.
3. Device regression: full reboot/re-jailbreak, Sileo and existing tweaks,
   userspace restart, settings, glass home/settings/about and Jetsam.
   Do not remove the existing jailbreak as a test prerequisite.
4. Validate kernel patchfinding on the actual supported iOS 16 devices. The
   model checks establish set/registration preservation, not correctness of
   instruction searches against every real kernelcache or runtime stability.
