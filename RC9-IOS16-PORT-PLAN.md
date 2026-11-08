# RC9 iOS 16 Port Ledger

## Baselines

- Target branch: `rc9-ios16-next`
- Target base: `2e1bd1e3eafd3cfbe52da1cd9a52c6cdae1d38c9`
- Target product: RootHide, iOS 16 only, TIPA only
- RC9 read-only source worktree: `G:\RootHide\runtime-rc9-audit`
- RC9 observed HEAD: `f2129c8f383c9998cc52f04aad9f1b65887fe6dc`
- RC9 source worktree is dirty and has local commits ahead of its tracked remote. Do not reset, switch, cherry-pick into, or write to that worktree as part of this port.

The target is a new RC9-flavored branch based on the verified iOS 16 code, not a wholesale replacement with the older RC9 tree. Every ported feature must retain the target's RootHide layout, iOS 16 pruning, additive Jetsam behavior, current spawn fixes, package identity, and TIPA-only build contract.

## Feature Inventory

| Feature | Target baseline | RC9 source boundary | Port status |
| --- | --- | --- | --- |
| Glass theme | Already contains the migrated RC9-derived glass UI, theme controls, media storage, video lifecycle handling, settings/about materials, and home focus behavior | Compare the current implementation with RC9 for remaining behavior and optimizations; do not replace the whole home controller | Audit complete; no additional iOS 16 behavior gap identified |
| Supporter authorization | No RC9 supporter entitlement engine; current `DOLicenseViewController` is the upstream open-source license browser | `DOSupporterLicense.h`, entry/settings/about/home integration, localizations, and release/security contracts | Core and a shared settings/Credits activation flow integrated locally; Custom Glass editing is gated at entry and write actions; jailbreak and focus mode remain ungated |
| Device diagnostics | No RC9 supporter/device diagnostic flow | The RC9 advanced-diagnostics sheet exposes hardware-identity and device-key probes implemented in `DOSupporterLicense.h` | Integrated into shared authorization sheet with explicit persistent-key disclosure and redacted output; requires source tests and real-device confirmation |
| Daily Low Power schedule | No schedule controller, SpringBoard scheduler, or RC9 schedule contract tests | `DOLowPowerScheduleController`, `DOEnvironmentManager` persistence, `RCLowPowerSchedule.h`, `lowpowerschedule.m`, SpringBoard entry, localization, project references, navigation handling, and tests | Source integration and Node contract tests complete; native Apple build and real-device scheduling remain unverified |

## Glass Audit Result

The focused comparison against RC9's read-only `DOMainViewController.m` and
`DONavigationController.m` found no missing iOS 16 glass behavior. The current
branch retains:

- video and Live Photo playback through the shared navigation wallpaper layer;
- zero full-screen blur for video, persisted playback speed, and pause/resume
  guards for inactive scenes, hidden views, jailbreak, and retired windows;
- shared Glass material refresh, adaptive foreground handling, profile persistence,
  edge-docked avatar focus mode, and the RC9 action-panel geometry;
- upper-section-only Glass treatment for Settings and Credits, including the
  internal scrolling behavior for long Credits content.

The remaining source differences are intentional: supporter authorization gates
custom wallpaper and Glass editing, while the base jailbreak flow remains
available without a supporter license. The low-power schedule adds its own
modal sizing rule. Do not replace the split iOS 16 controllers with the older
RC9 monolith unless a new device-level regression demonstrates a concrete gap.

## Dependency Order

1. Port the supporter authorization core and persistence contract without changing the current app identity or unrelated signing behavior.
2. Add the supporter entry points, display state, and action-time authorization checks across home, settings, credits, and navigation. Settings and Credits now call the same authorization UI.
3. Integrate device diagnostics as a separate user-invoked operation. The UI discloses that Secure Enclave probing may create a persistent key; the result excludes raw hardware identifiers, key fingerprints, license contents, signatures, and private signing material.
4. Port the daily low-power schedule as one feature spanning settings, validated configuration storage, Darwin notifications, the loaded SpringBoard runtime, status reporting, localization, and tests. Preserve its current fail-closed behavior when the system interface is unavailable. The target branch now has the full source integration, but it is not yet device-verified.
5. Compare the existing glass theme with RC9 and port only missing, verified behavior. Keep existing video blur suppression, background pause/retirement, profile persistence, and focus mode. This audit is complete; no additional glass patch is pending.

Each numbered stage should be a separate commit with focused tests. Do not dispatch a native build until the branch has passed source tests and the exact build candidate has been checked for uncommitted files.

## Authorization Compatibility Gates

- RC9 keeps signed supporter state outside the app container at `/var/mobile/Library/Application Support/DopamineRH/supporter-state.plist`, alongside a UserDefaults copy. Its tombstone makes license removal authoritative across RootHide preference redirection and reboot. Preserve verification-before-write, valid-license migration, and removal semantics.
- The legacy device-code algorithm includes `com.opa334.Dopamine-roothide` in its hash. Keep that protocol identifier fixed even though this fork's app bundle ID is `cn.zqbb.dopaRH`; changing the app identity must not silently mint a different supporter device code.
- License removal now reports failure unless the external tombstone is written and readable. A failed tombstone write must not delete the old state file, because doing so could let a stale RootHide-redirected defaults copy be reconsidered after reboot.
- License activation also fails closed when the external state write cannot clear an existing removal tombstone; the defaults copy is not published as a false-success fallback.
- Device-key diagnostics must not delete matching Keychain entries or silently downgrade to software/ephemeral keys. The current local core queries and validates Secure Enclave P-256 keys, fails closed when access or creation fails, and the diagnostic UI discloses that a successful first probe creates a persistent key.
- The RC9 source contains a custom Keychain group identifier, while the current target entitlements do not declare it. The staged key path uses the app's default Keychain group and does not request the absent entitlement. Do not add a Keychain access-group entitlement without verifying the target TrollStore signing flow.
- Keep the current target bundle identifier and package identity. Verify that the existing RC9 signed license protocol is independent of app bundle/version as its code comments specify, and test old-license upgrade, invalid replacement, removal tombstone, and re-import.
- The app must contain only the verifier public key. Never copy issuer private keys or real license/device-proof samples into the repository, tests, CI output, or release artifact.
- Device diagnostics are user-invoked probes, not a background health monitor. Reports must not expose raw ECID, private key material, complete license strings, or signed proof unless the user explicitly copies the intended device proof.

## Low Power Acceptance Boundary

The RC9 source implements a daily enable/disable schedule in local time, including overnight windows. The app edits and displays the plan; the SpringBoard module schedules events and requests the system mode. It does not require Dopamine to remain in the foreground or use a periodic polling loop. The implementation is now present on the target branch, but its native build and device behavior have not yet been verified.

This design may request event-time system wake behavior and is not a zero-wake or zero-power-cost guarantee. The checked-in RC9 design record says real-device sleep, event timing, and power measurements remain to be verified. Preserve that limitation in UI and release notes.

## Validation

- Keep the iOS 16 target's existing Node source-contract suite and XPF preparation.
- Port RC9 authorization, diagnostics, and schedule tests selectively; adapt them to the target test runner instead of copying obsolete whole-repository assumptions.
- Run Linux/macOS native C or Objective-C harnesses in CI where local Windows cannot compile them.
- Keep source tests, Apple native build, package identity checks, and device acceptance as separate evidence.
- Device checks must include existing license upgrade/removal/re-import behavior, diagnostics privacy, glass/video lifecycle, low-power plan enable/pause/manual override, respring, full reboot/re-jailbreak, and behavior after exiting the Dopamine app.
- Do not claim the schedule is device-verified or power-neutral until those device checks are recorded.
