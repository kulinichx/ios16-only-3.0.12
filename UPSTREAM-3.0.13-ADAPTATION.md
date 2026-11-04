# 3.0.13 selective backport for iOS 16 RootHide

Checked: 2026-11-04, Asia/Shanghai.
Status: candidate prepared for GitHub build; not yet natively built or device-tested.

## Verified release and source identities

The GitHub API reports that w2599 published tag `3.0.13` at
2026-11-04 14:49:34 Asia/Shanghai. Its assets include both:

- `Dopamine_3.0.13_836_1793774444_6522285.ipa` (55,448,065 bytes).
- `Dopamine_roothide_zqbb_3.0.13-29_20261104_141516.ipa`
  (36,484,062 bytes).

Sources:

- https://github.com/w2599/Dopamine/releases/tag/3.0.13
- https://api.github.com/repos/w2599/Dopamine/releases/latest
- https://api.github.com/repos/w2599/Dopamine/branches/3.x_roothide
- https://github.com/opa334/Dopamine/releases/tag/3.0.13

The release targets `3.x_modify_`. Its `3.0.13` tag resolves to
`6522285754fd9c4574e9afc352dc31fe548567fc`, not a new RootHide baseline.
The public `3.x_roothide` branch still resolves to
`18049d5a81b294d3387b3af30c54558d04b8b5f5`, the baseline already used here.
This was independently checked by fetching both refs and reading the branch API.
The presence of the new RootHide binary does not establish a matching new
public source commit or byte-for-byte reproducibility.

Do not merge the tag wholesale, switch to rootless, or replace the existing tree.
The earlier conclusion that there was no w2599 RootHide 3.0.13 binary was
incomplete; the release does contain that asset.

## Changes adapted locally

### Restore spawn attributes

Source: `f3cd2b82af8d5fa3baea193384ac61b50d2e44bb`.

`BaseBin/systemhook/src/common/common.c` now records the original active
and inactive memory limits before applying the existing MB-additive policy.
It restores those fields after either original-environment or patched-environment
spawn call returns, including failure. Reusing the caller's attribute structure
must not repeatedly add the same MB allowance to the stored limits.

The MB formula, finite-value default, unlimited `-1` handling and INT_MAX
clamping remain unchanged. The upstream persona/UID/GID/suspended-flag fixes
for iOS 17.6+ are not imported into this iOS 16 projection. RootHide's own
posthook already restores its temporary flags and is unchanged.

### RootHide snapshot write adaptation

Source: `26d95449d25d176a31ae7bc475fd85ee3403498c`.

The upstream edit is to `BaseBin/rootlesshooks/SpringBoard.x`. This build
loads `roothidehooks.dylib`, so the adaptation is in
`BaseBin/roothidehooks/src/springboard.x` instead.

- Replace its broad variadic `fcntl` hook with the upstream
  `XBApplicationSnapshotManifestImpl` snapshot-write hook.
- Retain RootHide's existing `snapshotContainerPath` redirection and its
  Apple-internal bundle-identifier exception.
- Use the randomized `jbroot` snapshot directory, not `/var/jb`.
- Use the original implementation for empty inputs, stock Apple apps and
  paths outside that snapshot directory.
- Validate the generated destination prefix before creating its directory
  and writing the snapshot. Prefix checks include the trailing path separator.
- Do not use `isSubPathOf` for new destinations: that helper needs successful
  `realpath` calls and rejects files/directories which do not yet exist.
- Preserve the app-hiding and app-open-request hooks byte-for-byte after
  line-ending normalization.

The new hook uses private SpringBoard selectors, like the upstream change.
Local static checks cannot establish their runtime behavior on the user's
iOS 16 build. The native build and device snapshot checks remain required.

## Deliberately excluded

- Non-iOS-16 SPTM frame-level and iOS 26 beta/TXM changes.
- Upstream rootless identity, paths and project replacement.
- Reintroducing Zebra, custom mounting, TrollStoreLite or removed exploits.
- Version-number changes, dependency-pin changes and workflow/toolchain changes.
- Unfinished home focus changes and the lockscreen mockup.

The candidate also includes the separately requested About-page adjustments:
glass is limited to the upper action section, contributor collections no longer
scroll independently, and the section lookup is guarded before the table has
loaded its sections. These are local UI changes, not part of upstream 3.0.13.

The app/basebin version remains `3.0.12` and RootHide revision remains `29`.
This is a selective 3.0.13 fix backport, not a verified complete rebuild of
w2599's released RootHide 3.0.13 binary.

## Validation and remaining acceptance

Local command:

```text
node --test tests/ios16-contracts.test.cjs tests/glass-ui-contracts.test.cjs
```

Result: 77 tests, 76 passed, 0 failed, 1 skipped. `git diff --check` passes.
The skipped test compiles the actual save/patch/restore C fragments on
Linux/macOS and exercises success/failure, repeated reuse, unlimited/zero
limits, finite-value fallback, non-injection, saturation and NULL attributes.
This Windows host has no supported native C compiler or Xcode, so neither
that C test nor the app's native build has been run here. Both existing CI
jobs already run the test file; a new workflow is not needed.

Before accepting a build, verify normal app launching, Sileo, switcher
snapshot generation/refresh for jailbreak apps and ordinary Apple apps,
existing RootHide blacklist behavior and the unchanged MB preference.
No automatic update or device cleanup is performed by these changes. The
GitHub source-check job must pass for the candidate commit before manually
dispatching its TIPA build. A successful source check is not a native build
or device validation.
