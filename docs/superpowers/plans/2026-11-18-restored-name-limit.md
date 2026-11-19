# Restored name limits implementation plan

Spec: [Restored name limits](../specs/2026-11-18-restored-name-limit.md).

## Steps

1. Run the existing package tests and prepare the simulator project.
2. Add regression tests for legacy host snapshots and prefilled name fields.
3. Add the display-name operation to Game and normalize the host name while
   decoding HostSnapshot. Keep the JSON fields and all non-name state intact.
4. Apply the existing character limit on initial appearance of StartView.
5. Verify the regression cases, including Unicode and undo behavior, then run
   the full package and UI suites, DocC, lint, and the simulator build.
6. Prepare the diff, validation evidence, and PR description for user review.

## Constraints

- Keep Swift 6 concurrency checking and the existing name limits.
- Edit the XcodeGen specification only if project changes are needed.
- Use a separate SE3 simulator for UI checks.
- Avoid user accounts, personal saves, and signing credentials.
- Keep generated projects, build products, and test results out of commits.
