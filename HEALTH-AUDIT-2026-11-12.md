# RC9 iOS 16 follow-up audit

Date: 2026-11-12, America/Denver.
Local baseline: `8a3875e5a5411de565753900671dc2a9f4099624`.
Scope: authorization, glass media transactions/lifecycle, mount management,
maintenance failure handling, and low-power scheduling.
The audit was initially read-only. The user subsequently authorized repairs;
the implementation and verification status are recorded below.

## Source identities checked this time

Remote refs were queried directly with `git ls-remote`, not inferred from
release titles or stale tracking branches.

| ZQBB public ref | Observed commit |
| --- | --- |
| `3.x_modify_` and tag `3.0.13` | `6522285754fd9c4574e9afc352dc31fe548567fc` |
| `3.x_roothide` | `18049d5a81b294d3387b3af30c54558d04b8b5f5` |
| `3.x_roothide_AI_review_fix` | `3ac500e9d95553c2ffd651894315d79b31ee8aed` |

Fetched the last commit into `refs/upstream-audit/20261112/zqbb-review`;
no checkout, merge, or runtime source replacement.
Its tree is identical to the previously reviewed `d37a79f5` tree
(`69bdedaad7c2575c9a992d376311598e34b94189`), despite a different commit ID.
Official RootHide tag 30 (`9617d75f`) is an ancestor of that review branch.

The release API still names tag `3.0.13`, target `3.x_modify_`, and includes
`Dopamine_roothide_zqbb_3.0.13-30_20261106_103030.ipa`.
That attachment name does not establish which source commit built it.
No release binary was downloaded or reverse engineered in this pass.

The mount feature is ZQBB's feature. Its public implementation is present
in `65222857`; the two public RootHide refs above do not contain those mount
handlers. This project adapts that feature onto its existing RootHide base.
It is not a byte-for-byte copy of a publicly verified RootHide release build.

## New findings

### 1. [P1] Parent and child mount entries share deletable copy storage

Locations:

- `BaseBin/jbctl/src/internal.m:70` creates intermediate copy directories.
- `BaseBin/jbctl/src/internal.m:79` reuses any nonempty directory as a complete copy.
- `Application/Dopamine/Jailbreak/DOEnvironmentManager.m:865` validates paths
  individually, without detecting relationships between entries.
- `Application/Dopamine/Jailbreak/DOEnvironmentManager.m:987` recursively
  deletes the selected copy without checking retained descendants.

Concrete sequence: add `/System/Library/Fonts/Cache`, then
`/System/Library/Fonts` on a device where both directories exist.
The first operation creates the parent copy directory containing `Cache`.
The second sees that nonempty parent and skips copying its other contents.
Mounting this incomplete parent can hide the parent's other files.
If both entries are configured and the parent copy is subsequently deleted,
the child's customized files in that copy tree are deleted too, although its
entry is retained. After reboot the remaining entry can recreate stock files.

This storage/reuse behavior also exists in ZQBB `65222857` (`initMountPath`
and `fakeMount:unmount:shouldDeleteMntFiles:`). It is an inherited edge case,
not evidence that the feature was independently invented here.
The previous A/A_tmp fix addresses a different collision and does not close it.

Recommendation: define ownership for overlapping copy trees before mounting
or deleting; preserve existing custom files and account for old configurations.
If overlapping entries cannot be supported, report the exact conflict rather
than silently mounting an incomplete tree or deleting another entry's files.
Cover both insertion orders, retained child data, and reboot restoration.
Do not impose unrelated path restrictions.

### 2. [P2] Failed respring fallback is reported as success

Locations:

- `BaseBin/jbctl/src/main.m:160`: failed `execve(sbreload)` invokes void `killall`.
- `BaseBin/libjailbreak/src/util.c:965`: enumeration failures return silently;
  `kill` failures at line 988 are ignored.
- `BaseBin/jbctl/src/main.m:241`: the command then returns zero.
- `Application/Dopamine/UI/DOMainViewController.m:1544`: zero keeps the faded,
  noninteractive interface, assuming the restart took effect.

If sbreload cannot execute and the fallback finds/signals no backboardd
process, no respring occurs but the new UI recovery path is bypassed.
The backend's unconditional success behavior is also present in ZQBB's
current review tree. The UI's reliance on that status is this project's code.

Recommendation: propagate whether a restart request was actually delivered,
and restore the interface on failure. A timeout recovery must avoid issuing
duplicate restart commands. Test both backend failure propagation and UI state.

### 3. [P2] Unmount deletes the copy before persisting removal from the list

Location: `Application/Dopamine/UI/Settings/DOSettingsController.m:1060`.

After successful unmount, the code deletes the copy, then saves the updated
list at line 1066. If that save fails, the on-disk list still contains the
path. `DORuntimeConfiguration.restoreCustomMounts` will create a new stock copy
and mount it at the next jailbreak, undoing the user's requested removal.
The error message acknowledges failure but does not prevent that restoration.

ZQBB `65222857` uses the same delete-before-list-save order, without reporting
the save result. Our explicit error handling improves visibility but does not
make those operations recoverable.

Recommendation: after unmount, persist removal before irreversible cleanup.
On persistence failure retain the copy and make retry possible. On cleanup
failure keep the entry removed and identify the leftover copy for cleanup.
Keep this separate from the already fixed add/save rollback bug.

## Existing residuals, not new findings

- Legacy unbound RH1 migration remains compatible and copyable with its state;
  the original authorization P1 is still open. RHB1 preview is not mandatory
  device binding for all users. No issuer files or real licenses were changed.
- Explicit recursive mount-copy deletion still runs synchronously.
- Repeated legacy authorization reads/signature verification still occur.
- Media imports stage files before commit; process termination can leave
  unreferenced files. This pass did not establish a new committed-reference
  corruption bug in the repaired media transaction.

## Validation and limits

Ran all five existing test files locally:
120 total, 112 passed, 0 failed, 8 Windows platform skips.
`git diff --check` passed before this documentation addition.
The tests cover A/A_tmp and command failures, but do not cover parent/child
copy ownership, failed respring fallback status, or unmount-list save failure.

New findings above are based on production control-flow and upstream source
comparison, not new native fault-injection or real device mount experiments.
Windows cannot run the Foundation/Security/UIKit paths in this checkout.
No new build was triggered and no new macOS result is claimed by this report.
Existing successful build evidence remains recorded separately in
`HEALTH-AUDIT-FOLLOWUP-2026-11-11.md`.

Preserved the user's existing `BaseBin/XPF` changes and `TIPA/` contents.

## Authorized repairs

- Kept ZQBB's copy paths, saved-list format, read-only bind mounts and reusable
  copies. Added a shared path-relationship helper rather than a new mount engine.
- New overlapping entries are rejected with the exact conflicting saved path.
  Existing overlapping lists can still be reduced: remove the parent first,
  preserving the child's copy. Removing the child first is refused so the
  remaining parent cannot become eligible to restore an incomplete copy.
- Startup skips a saved parent with saved descendants before considering its
  nonempty intermediate directory reusable. Child entries can still restore.
  Recursive cleanup independently refuses copies shared with retained entries.
- After successful unmount, persist list removal before deleting the copy.
  Save failures retain the original copy and entry for retry; cleanup failures
  retain the copy but not the entry, and display its actual location.
- Added `killall_with_result`; retained the void wrapper for existing callers.
  Respring fallback now returns failure when enumeration/signaling fails or no
  matching process receives a signal. At least one delivered signal is success.
  This feeds the existing nonzero-status UI recovery, without repeating commands.
- Tests exercise the production Foundation path helpers, copy preparation,
  list persistence and cleanup methods using a temporary filesystem and fault
  flags. C tests extract the production respring fallback and signaling code.
  They do not execute system mounts or signal real system processes.

The repairs do not repair already damaged copies, enable mandatory authorization
binding, or make explicit recursive cleanup asynchronous. Existing copies whose
entries were removed before this protection are not automatically classified
or deleted; no broad cleanup or device migration is performed.

Local verification after repairs: 122 tests, 113 passed, 0 failed, 9 Windows
platform skips. The added Foundation test requires a native macOS run before
its result can be claimed. Native compilation/build results remain pending.

First macOS run `43061739569` passed 121/122 tests and stopped before app
compilation. The new removal test incorrectly switched directly from a saved
child to its parent between independent scenarios; the protection correctly
rejected it. The fixture now asserts that rejection and clears its temporary
list before starting the next scenario. No production protection was relaxed.

## Final native validation

Recorded 2026-11-12, America/Denver (client date).

- Built commit: `b5cd3398cf77cf74b5800d920ac2f9010d80db81` on `rc9-ios16-next`.
- Linux source run `43062221404`: 122 total, 116 passed, 0 failed,
  6 macOS-only skips. Includes extracted C respring/signaling fault cases.
- macOS build run `43062365812`: success, build job 8 minutes 15 seconds.
- macOS native tests: 122 total, 122 passed, 0 failed, 0 skipped.
- Actual app compilation, Verify TIPA, resource checks and artifact upload passed.
- Package: `Dopamine-rh-rc9-b5cd339.tipa`.
- Artifact: `RootHide_iOS16_TIPA`, ID `13873949078`.
- No new package was downloaded locally by this repair pass.

This verifies compilation and the bounded fault-injection scenarios, not real
bindfs behavior, UIKit device error presentation, or physical Secure Enclave
binding. Old RH1 policy and the existing issuer data remain unchanged.

## Remaining performance repairs

The follow-up after `8da14837` addresses two of the explicit residuals:

- Mount removal now persists the list on the app thread, then uses the existing
  asynchronous child runner for `jbctl internal cleanup_mount_copy`. Recursive
  deletion no longer happens in the app. The settings busy state spans both
  unmount and cleanup. Startup mount restoration remains synchronous.
- The child independently refuses mounted paths, retained/shared copies,
  missing or malformed lists, and symlinked copy components. It uses the same
  ZQBB copy namespace; it does not scan for or delete unrelated leftovers.
- Glass material reloads and low-power cell/layout styling share a display-only
  authorization snapshot across translation units. It expires after one second
  and invalidates on license changes and app lifecycle changes. Successful
  activation/removal invalidates before notifying views, independent of observer
  delivery order. Jailbreak execution and protected editing keep fresh checks.
- Native tests exercise production cleanup on temporary directories and the
  render snapshot in two translation units, including expiry and invalidation.
  The cleanup task/privileges and authorization result are test doubles; no
  system mount, real license or issuer key is used.

Legacy unbound RH1 migration is still an open P1: preserving all legacy devices
without an issuer-approved binding exchange cannot establish non-copyable
identity. Mandatory binding remains disabled for that compatibility path.
Media staging orphans after process termination also remain an acknowledged
storage residual; this change does not broadly clean user media.

Native validation was pending when these changes were first committed. The
results for the follow-up are recorded below, separately from the older package.

Initial follow-up native run `43138754655` passed 123/124 tests, including the
cross-translation-unit render snapshot. The removal fixture's `JBROOT_PATH`
macro expanded its global `root` name inside the production helper's local
`root` declaration, giving that test a nil copy root. Renamed the fixture global
to `fixtureRoot`; no production cleanup protection was relaxed.

### Follow-up validation completed

- Built commit: `13daa5ec215d62bcd93ee495a2bb5b8b10d555a1`.
- Local Windows: 124 total, 114 passed, 0 failed, 10 platform skips.
- Linux source run `43139322782`: 124 total, 117 passed, 0 failed,
  7 macOS-only skips.
- macOS build run `43139413247`: success, build job 4 minutes 54 seconds.
- macOS native tests: 124 total, 124 passed, 0 failed, 0 skipped.
- App compilation, Verify TIPA/resources and upload all passed.
- Package: `Dopamine-rh-rc9-13daa5e.tipa`.
- Artifact: `RootHide_iOS16_TIPA`, ID `13908519452`; uploaded artifact ZIP
  SHA256 `17dfd99c0a30313f5d8e96d7e6811579dda8b987c8281bd30ac9aa2841840fc8`.
- Package was not downloaded locally by this pass. Existing XPF edits and TIPA
  directory contents remain untouched.

These results close the explicit synchronous-cleanup and material/layout
verification performance repairs, not the legacy RH1 migration policy or media
staging-orphan residuals. Device bindfs, UIKit appearance and physical Secure
Enclave behavior still require device validation; native mocks are not that proof.

## Media orphan recovery follow-up

- After theme bootstrap, schedule one utility-queue pass over the app's explicit
  container media directory. Do not delay startup with directory enumeration.
- Only exact app-generated UUID filenames with known image/video prefixes and
  extensions qualify, and only when their modification time is over 24 hours old.
- Preserve the union of all three media references in authoritative external
  theme state and local defaults. Missing, unsupported-version or malformed
  reference state stops deletion rather than being treated as an empty theme.
- Share active staged filenames across translation units, registering before
  image writes or video copies and releasing after commit or failure cleanup.
  Recheck active status and references under the same lock as media commit.
- Resolve the exact container, then walk fixed directory components using
  no-follow directory descriptors. Only unlink immediate regular-file children;
  do not recurse, follow symbolic links or remove unknown files/directories.
- Native Foundation fixtures add old/fresh/active/referenced media, shared
  translation-unit occupancy, malformed/missing state and symlink cases. Codecs
  and container discovery are test doubles; filesystem operations are real in
  a temporary directory.

Validation completed for commit `41d6df6e31d154d2f48095cc6b9414be59fbbda4`:

- Local Windows: 125 total, 115 passed, 0 failed, 10 platform skips.
- Linux source run `43141326339`: success.
- macOS run `43141411466`: 125 tests, 125 passed, 0 failed, 0 skipped.
- Build job: success, 4 minutes 39 seconds. Actual app compilation, Verify TIPA,
  resource checks and artifact upload passed.
- Package: `Dopamine-rh-rc9-41d6df6.tipa`.
- Artifact: `RootHide_iOS16_TIPA`, ID `13909782087`; uploaded artifact ZIP
  SHA256 `3be911719810efec75db3f33d14c111d1ea81005c881df88e80ef70bb08c4e58`.
- No package downloaded locally; existing XPF edits and TIPA contents preserved.

This closes bounded recovery of old generated media orphans, not arbitrary
temporary files or unknown user files. References remain subject to the normal
theme bootstrap/recovery policy. Real device appearance/storage behavior is not
proven by native codec/container test doubles. Legacy RH1 binding migration
remains open and the real issuer tool/data remain untouched.

## Binding migration tooling safeguards

The legacy RH1 compatibility policy is unchanged. This follow-up only hardens
the repository's independent migration helper and Windows preview UI:

- Preview returns a deterministic digest of each selected signed RH1 and exact
  hardware/key binding. Issue commands require the reviewed digest and reject
  changed data before opening the issuer key. This detects review/issue drift;
  it does not establish that a historical binding was legitimately reviewed.
- Existing/source output paths are rejected before private-key access. Bounded
  database reads enforce the 16 MiB limit before parsing, including file growth.
- All outputs are written and synced in a unique staging directory first.
  Hard-link publication refuses overwrites, including files created after the
  initial check. Ordinary failures roll back only outputs with matching file
  identity; incomplete rollback reports remaining paths. Unsupported filesystems
  fail rather than falling back to overwrite-prone publication.
- UI clears old preview state on reload, carries the correct digest and reports
  clipboard/staging cleanup problems separately from successful issuance.
- Tests use generated disposable issuer keys and temporary databases only.
  Cover stale review, source/existing targets, single/batch issuance, injected
  write/link/cleanup failure, concurrently replaced files, and Windows Forms
  preview startup. No real issuer key/database was opened or changed.

This is not crash-atomic multi-file publication. Power loss or forced process
termination may leave complete partial outputs and staging files for manual
inspection. Directory ACLs remain the issuer's responsibility; no hostile local
filesystem security boundary is claimed. Mandatory binding remains disabled
pending issuer-approved migration and physical-device validation.

Local Windows validation: 137 tests, 127 passed, 0 failed, 10 platform skips.
Includes actual Windows Forms preview startup and NTFS hard-link publication
using disposable data. An initial fixture assertion used argv after the helper
consumed it; the capture wrapper now copies argv. No production guard relaxed.
Linux CI run `43143626679` passed for commit
`4b4a74653efb4edaa247a2151dc1293e8ee9d4d6`: 137 tests, 129 passed, 0 failed,
8 platform skips (7 macOS-native cases plus Windows Forms startup). Includes
the dangling-link refusal and POSIX output-permission assertions. No new macOS
build was requested for this tooling-only change; no app/runtime source changed.
The most recent tested TIPA remains `Dopamine-rh-rc9-41d6df6.tipa`.

## Windows launcher visibility repair

User double-click reproduction found five running helper instances whose main
forms all had native `IsWindowVisible == false`. Direct PowerShell smoke tests
passed because they had not exercised the hidden VBS launch path.

- VBS now starts the child with normal window startup information; PowerShell's
  own `-WindowStyle Hidden` hides its console without hiding the modal form.
- Launch errors propagate a nonzero status. Test mode suppresses the error
  message box, returns the child status and never loads the real issuer folder.
- A Windows regression test invokes the actual VBS launcher, shows the form,
  checks native visibility using a short UI timer, then closes it. A disposable
  stub verifies propagation of a child failure status without blocking dialogs.
- Local full suite: 138 tests, 128 passed, 0 failed, 10 platform skips. Both
  Windows preview and actual launcher visibility checks passed.
- The five observed duplicate hidden forms were closed gracefully by exact
  title and process/path checks. No issuer database or key was read or changed.

No app/runtime files changed and no new TIPA is needed for this launcher repair.

## Migration preview contact notes

- Read-only inspection of the original issuer's PowerShell source confirmed
  that names/contact remarks are saved as `Note`. No real records or key read.
- The helper now passes this original string through the preview, and the grid
  adds a contact/note column with full-text tooltips. Multiline notes display on
  one row without changing their original value. Missing/non-string notes show
  as empty; no guessed names, database writes or new license fields.
- Single-user confirmation includes both ID and note. Review digests now cover
  the displayed note too, so a changed name/contact requires renewed review.
- Disposable-key tests cover exact note preservation, unchanged records and
  RH1, no note in RHB1, legacy empty notes and refusal after a note changes.
  Windows Forms integration uses a mock preview, including Chinese and multiline
  text, and checks both displayed cells and original tooltips.

This is a computer-tool-only change; no mobile TIPA rebuild is needed.
Local full suite: 140 tests, 130 passed, 0 failed, 10 platform skips. Includes
actual Windows Forms note-cell/tooltips integration and visible VBS startup.

## Separate User Field And Original Dark Palette

The preceding note-only repair was incomplete: the issuer stores the user name
in `DisplayName`, independently of `Note`. Read-only inspection of its record
writer and grid projection confirmed the exact fields. No real database or key
was opened to establish this mapping.

- Preview now carries `DisplayName`, verified license device code and
  `LastIssuedAt` alongside `Note`. The grid matches the original five information
  columns and adds binding state. Confirmation includes name, ID, device and note.
- Reused original issuer background, surface, alternate-row, input, text,
  selection and button palette values; no original tool files were modified.
- Review digest includes name/date as well as notes; changes require renewed
  review but do not change signed RH1/RHB1 formats or issuer records.
- Extended disposable-data tests check independent names/notes, device and date,
  optional-field fallback, stale-name refusal, actual Windows Forms cells and
  dark palette values. Rendered a synthetic-data preview and visually inspected
  all six columns and the dark surface/buttons; no real user data in the image.

No mobile runtime changes and no TIPA rebuild required.
Local validation: 140 tests, 130 passed, 0 failed, 10 platform skips.

## Remember Last Issuer Directory

- Store only the validated absolute issuer path and settings format version in
  the current user's LocalAppData/RootHideSupporterBinding/settings.json.
  Write a unique temporary file and replace the prior settings; leave source
  issuer records and keys untouched. Saving failure does not prevent using an
  already validated directory, and clearly states it will not be remembered.
- Normal startup restores that path and runs only `plan`, not issue commands.
  Missing/invalid databases or corrupt/unsupported settings keep issue buttons
  disabled and prompt directory reselection. A successful new selection replaces
  stale settings. The folder picker starts at the currently loaded path.
- Smoke tests ignore real LocalAppData settings. An explicit test-only directory
  isolates cross-launch persistence checks from real issuer data. Tests cover
  initial selection, reopening, replacement with another directory, unavailable
  source databases, corrupt/oversized/relative/unsupported settings and recovery.
- Initial persistence test caught Windows PowerShell binding an empty backup
  argument incorrectly for File.Replace. Use a unique explicit backup path and
  remove it after replacement; the multi-launch update test now passes.

Only the desktop helper changed. The reported mobile lookup/-34018 failure
remains separate and is not fixed by remembering the desktop directory.
Local full suite: 141 tests, 131 passed, 0 failed, 10 platform skips.

## Device Proof Lookup Entitlement Repair

- Downloaded the successful run 43141411466 artifact and inspected the actual
  Mach-O LC_CODE_SIGNATURE XML entitlement slot in Dopamine-rh-rc9-41d6df6.tipa.
  Both application-identifier and keychain-access-groups are absent, matching
  the source entitlement plist. This is a packaging defect consistent with the
  reported lookup / errSecMissingEntitlement (-34018), not a stale RH1 license.
- Read the official TrollStore RootHelper/main.m signApp implementation: fallback
  keychain entitlements apply only when no entitlement dictionary exists, so it
  does not repair this application's existing nonempty entitlement dictionary.
  Apple Security SecItemServer.c reports missing entitlement when a client has
  neither application-identifier nor keychain-access-groups.
- Add application-identifier cn.zqbb.dopaRH and exactly one keychain access group
  with the same value. No wildcard, Apple token group or invented team identity.
  Keep the bundle identifier, legacy device-code seed, Secure Enclave key tag,
  default key lookup/create queries, RH1/RHB1 formats and migration policy intact.
  No key deletion, license removal or software-key fallback.
- CI now extracts entitlements from the final packaged executable using ldid,
  parses them with plutil and checks identity, exact access group and preserved
  platform/sandbox flags. The extracted plist is included in build artifacts.
  Tests reject missing/broad/mismatched permissions and parse the source plist
  with native platform parsers on Windows/macOS.

Real-device proof generation and continuity of any keys from independently
signed historical builds remain unverified. Existing keys are not deleted or
silently migrated between access groups. Keep the old RH1 authorization during
testing; changing or removing it cannot supply a missing code-sign entitlement.

Local Windows suite: 143 tests, 133 passed, 0 failed, 10 platform skips.
The new native XML-parser check and entitlement rejection cases passed. Native
macOS app compilation, final signature verification and device proof testing
are still pending at this point.

Follow-up CI evidence for runtime commit
`e725865e860f9dd188ca9ff54c34648e168137b3`:

- Push source checks run `43151323499`: success.
- Manual macOS build run `43151400215`: success, build job 7m1s.
- macOS suite: 143 tests, 139 passed, 0 failed, 4 Windows-only skips. Native
  Foundation/Security tests passed, still using mock hardware/key lookup.
- Final packaged executable passed ldid/plutil entitlement verification for
  cn.zqbb.dopaRH; no wildcard access group or fabricated signing team.
- Package `Dopamine-rh-rc9-e725865.tipa`, artifact `RootHide_iOS16_TIPA`,
  ID `13914690452`. Artifact ZIP SHA256 (not the inner TIPA hash):
  `9fd65f485a1429a32d4428ce85032797914e3e6c19bcaa5820533b0ed28178b6`.
- Added the non-destructive 0028 proof/binding test procedure to
  SUPPORTER-BINDING-MIGRATION.md. No real issuer records or private key opened,
  no credentials issued, and no files in the original issuer tool modified.

Device proof generation and subsequent RHB1 activation still require the
owner's phone validation; CI success alone does not establish device success.
