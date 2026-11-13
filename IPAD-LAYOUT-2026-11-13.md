# iPad Preferences Layout Follow-up

## Reports And Comparison

- Follow-up report: owner's iPad M2 on iOS 16.5 also has misaligned Settings
  and Credits in landscape; another user's iPad mini 6 has the same issue.
  The owner explicitly identified `Dopamine-rh-rc9-9a6c3ce.tipa` as the affected
  package. That package is present at `TIPA/11-12/`; its named source revision
  precedes candidate repair `5bef17ce`, so this is not a report against the repair.
- The iOS 16.5 report supersedes the earlier assumption that the owner's M2
  was unaffected. The mini 6 OS version was not reconfirmed in this follow-up.
- iPad mini 6, iOS 16.2: Settings and Credits compress rows horizontally;
  the supplied screenshots show landscape. The reporter says an earlier package
  worked, possibly `50c98f6` or `da4f0da`; the exact package is not confirmed.
- Earlier report: owner's iPad Pro M2, iOS 16.6, both orientations working;
  do not treat this earlier observation as validation of the current report.
- Compared both earlier commits with `9a6c3ce6`. Settings/Credits table-frame
  arithmetic, the Preferences base controller and custom cell constraints are
  unchanged across those commits. No particular recent commit is established
  as the cause of the report.
- Compared local ZQBB `origin/3.x_roothide` snapshot `18049d5a` and official
  RootHide 3.0.13-30 snapshot `9617d75f`. The upstream Preferences table follows
  its controller width with 12-point side spacing, without our 620-point cap.
  These are local source comparisons, not a claim to have fetched latest HEAD.
- Settings uses dynamic PSSpecifier insertion; glass rectangles use current
  section/row counts. Credits still starts with DOHeaderCell followed by its
  three actions. Removing its authorization row and builder group did not
  displace the first group. No stale row-index dependency was found that
  explains the horizontal compression in both pages.

## Candidate Repair

- Remove the additional 620-point table viewport cap from Settings/Credits,
  following the upstream horizontal frame policy. Keep the fixed back row,
  safe-area spacing and existing bottom padding.
- Constrain custom header, action button and credits collection children to
  their containing contentView, not the outer cell. Bound header text width.
- Keep Credits glass in section zero only; its horizontal bounds now follow
  an actual action row rather than the full-width section rectangle.
- Do not add forced scrolling, nested layout/reload calls, device-model checks,
  OS-version guesses, trait overrides or private Preferences method overrides.
- No menu options, authorization, jailbreak or mount behavior changed.

## Official Source Recheck And Shared Layout

- Read `https://github.com/roothide/Dopamine-roothide.git` with `git ls-remote`
  during this follow-up. Official HEAD and `refs/heads/3.x` both resolve to
  `9617d75f476423fdfd33477299c8a1349eb6f375`, matching the local Git object used
  for source comparison. No merge of unrelated upstream changes is needed.
- Official `DOPSListController` applies its table frame in the common layout
  callback, using controller width minus 24 points. Official Credits inherits
  this layout. Its navigation controller sizes secondary pages as compact
  modals; our glass Settings/Credits intentionally use full-screen controllers,
  so copying the official modal size alone would change their presentation.
- Retain the official width policy and the prior contentView constraint repair.
  Introduce `preferencesTableFrame` so our common controller applies the final
  frame once, instead of first applying the compact-page frame and then having
  Settings/Credits overwrite it. The default frame remains exactly the official
  `(12, 5, width - 24, height - 10)`; the two full-screen pages reserve their
  existing safe area and fixed back row. Glass refresh follows that frame.
- This shared-layout adjustment is local adaptation for the glass UI, not a
  claim that official RootHide contains this new method or guarantees a fix.
- Follow-up verification: UI and iOS 16 suites total 95 tests, 89 passed,
  0 failed, 6 platform skips. Git ownership checks initially blocked XPF
  fixtures; rerun passed with process-local safe-directory entries for the
  existing XPF checkout and its Git directory, without global Git changes.
- `git diff --check` passes. A native Xcode build and actual landscape/portrait
  checks on the affected devices remain pending; no new TIPA was produced.

The double-constrained table viewport is a compatibility hypothesis, not a
confirmed runtime diagnosis. A successful build or arithmetic test does not
prove iOS 16.x Preferences row layout is fixed. Need confirmation on the affected
M2 running iOS 16.5 and mini 6, plus portrait and iPhone regression checks.

## Verification

- Focused UI suite: 49 tests, 46 passed, 0 failed, 3 macOS-only skips.
- Full Windows suite including optional original-issuer tests on synthetic
  fixtures: 165 tests, 155 passed, 0 failed, 10 platform skips.
- New tests execute the production table-frame arithmetic for mini/Pro in
  both orientations, phones, split-view sizes, safe-area offsets and zero bounds.
  This is geometry coverage, not a UIKit rendering test.
- Source contracts guard contentView anchoring, upper-only Credits glass,
  fixed return controls and unchanged core behavior.
- `git diff --check` passed. Native build and real-device confirmation pending.

## Build Preparation

- Current chat confirmation: owner's iPad Pro M2 on iOS 16.6 works in both
  orientations. The separate iOS 16.5 report above must not replace that result.
  No affected-device success is claimed for this candidate.
- Reran the complete Windows suite against the shared final-frame layout:
  166 tests, 156 passed, 0 failed, 10 platform skips. Optional original-issuer
  tests used synthetic fixtures; no production signing records were modified.

## Published Test Build

- Source commit `faa47ee86a830f3a9cc8b3aee25bb93520d252be` pushed to the
  owner's `rc9-ios16-next` branch (remote `ios16-target`).
- Push source checks `43363409823` succeeded: 166 tests, 150 passed,
  0 failed, 16 platform/optional/shallow-checkout skips.
- Manual macOS build `43363479172` succeeded; build job duration 5m28s.
  macOS tests: 166 total, 158 passed, 0 failed, 8 skips.
- `Verify TIPA` passed, including archive integrity, packaged menu/locales
  and application/keychain entitlement checks.
- Artifact `RootHide_iOS16_TIPA` (ID `14010055278`) uploaded successfully,
  containing `Dopamine-rh-rc9-faa47ee.tipa`. Artifact ZIP is 29,105,194 bytes;
  this is not a measurement of the unwrapped TIPA itself.
- No automatic local TIPA download. Real mini 6 / iOS 16.2 Settings/Credits
  confirmation and regression checks on the owner's M2 remain pending.

## Landscape Header Follow-up

- User supplied a screenshot of `faa47ee`: the Credits action rows are centered,
  but the title and custom developer collections are displaced to the right.
  Thus the earlier viewport change is insufficient for custom section headers.
- Both `DOHeaderCell` and `DOCreditsCell` are registered as `headerCellClass`,
  but inherited `UITableViewCell`. Their custom children depended on the cell's
  internally laid-out contentView even though Preferences uses them as headers.
  The screenshot is consistent with that mismatch; no iOS 16 runtime inspection
  was performed to measure the internal contentView frame.
- Convert these two custom headers to UIView while preserving initWithSpecifier,
  preferredHeightForWidth, class names, data sources and collection height.
  Pin header contents to their own view bounds, removing table-cell content
  layout from this path. Ordinary DOButtonCell rows remain table cells.
- Bound and center the title label, with font shrinking for long version text.
  Credits remains two columns, without internal collection scrolling. No changes
  to menu options, table viewport, authorization or jailbreak functionality.
- Focused UI tests: 50 total, 47 passed, 0 failed, 3 platform skips. Full Windows
  suite: 166 total, 156 passed, 0 failed, 10 skips; optional issuer tests use
  synthetic fixtures. Source checks are not UIKit rendering verification.
- Native build and actual portrait/landscape confirmation pending for this fix.
