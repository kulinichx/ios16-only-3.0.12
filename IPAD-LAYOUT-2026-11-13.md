# iPad Preferences Layout Follow-up

## Reports And Comparison

- iPad mini 6, iOS 16.2: Settings and Credits compress rows horizontally;
  the supplied screenshots show landscape. The reporter says an earlier package
  worked, possibly `50c98f6` or `da4f0da`; the exact package is not confirmed.
- Owner's iPad Pro M2, iOS 16.6: both orientations work normally.
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

The double-constrained table viewport is a compatibility hypothesis, not a
confirmed runtime diagnosis. A successful build or arithmetic test does not
prove iOS 16.2 Preferences row layout is fixed. Need mini 6 confirmation and
regression checks on the already-working Pro M2 and iPhone.

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
