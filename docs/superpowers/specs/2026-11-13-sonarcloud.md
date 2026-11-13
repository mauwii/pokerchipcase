# SonarCloud

CI-based SonarCloud analysis with Swift test coverage, a quality gate, and a check that fails on any open issue.

## Setup outside the repo

Done by the maintainer, not by code:

- The project `mauwii_pokerchipcase` exists in the SonarCloud organization `mauwii` (the personal GitHub account, imported).
- Turn off Automatic Analysis (Administration, Analysis Method). With it on, the CI scan fails.
- Create a project analysis token and store it as `SONAR_TOKEN` in a new GitHub environment `sonarcloud`, with no branch restriction and no required reviewer. The token can only upload analyses for this one project, and the PR scan needs it. Fork PRs get no secrets, and Dependabot runs get no environment secrets.
- Add `SonarSource/sonarqube-scan-action@*` to the Actions allow-list in the repo settings. Only GitHub-owned actions are allowed today.

## sonar-project.properties

```properties
sonar.projectKey=mauwii_pokerchipcase
sonar.organization=mauwii

sonar.sources=Sources,App/Sources
sonar.tests=Tests

# written by the CI job test
sonar.swift.coverage.reportPaths=coverage.report
# the SwiftUI app has no unit tests by design, analyzed for issues only
sonar.coverage.exclusions=App/Sources/**
# fail the scan step, and with it the job test, on a red quality gate
sonar.qualitygate.wait=true
```

`.gitignore` gets `coverage.report`.

## CI

The job `test` in `.github/workflows/ci.yml` runs the scan, so the test suite runs on macOS only once:

1. `environment: sonarcloud`, and `env: HAS_SONAR_TOKEN: ${{ secrets.SONAR_TOKEN != '' }}`. Runs without the token (Dependabot) skip every Sonar step and pass on the tests alone.
2. `swift test --enable-code-coverage`.
3. Write the report, with or without the token:

   ```sh
   BIN=$(swift build --show-bin-path)
   xcrun llvm-cov show -instr-profile "$BIN/codecov/default.profdata" \
     "$BIN/PokerCoreTests.xctest/Contents/MacOS/PokerCoreTests" \
     -object "$BIN/PokerNetTests.xctest/Contents/MacOS/PokerNetTests" \
     -object "$BIN/PokerSessionTests.xctest/Contents/MacOS/PokerSessionTests" \
     Sources > coverage.report
   ```

   On the CI runner the bundle names differ (one bundle for the package instead of one per target), so the step globs `$BIN/*.xctest` and passes every bundle's binary, joined with `-object`; the profile comes from `dirname $(swift test --show-codecov-path)`.

   This is the `llvm-cov show` text format that `sonar.swift.coverage.reportPaths` reads. Passing `Sources` limits the report to library code.

   The same step appends the per-file table of `xcrun llvm-cov report` (same profile, objects and `Sources`) as a code block under `### Coverage` to `$GITHUB_STEP_SUMMARY`, so the run page shows coverage without a download. It runs with or without the token. Line-by-line coverage is in SonarCloud.
4. `SonarSource/sonarqube-scan-action`, pinned by commit SHA with a version comment, with `SONAR_TOKEN` from the environment.
5. "Fail on open SonarCloud issues": Sonar way rates new code smells only by their debt ratio, so the gate passes even critical ones. This step queries `https://sonarcloud.io/api/issues/search?componentKeys=mauwii_pokerchipcase&<scope>&resolved=false&ps=100` with `curl`, where `<scope>` is `pullRequest=<number>` on PRs and `branch=<name>` otherwise. It prints each issue as a `::error file=…,line=…,title=<rule>::<message>` annotation with `jq` and fails unless `.total == 0`. Accepted and false-positive issues count as resolved and do not fail it.

The Sonar docs list `sonar.swift.coverage.reportPaths` for Xcode 7 to 13.2. If the first scan shows no coverage for `Sources/`, the fallback is `llvm-cov export -format=lcov` plus a short awk script that writes the Sonar generic coverage XML (`DA` lines to `lineToCover`, `BRDA` lines to branch counts), imported with `sonar.coverageReportPaths`.

## Existing issues

Automatic Analysis on `main` found 24 code smells and no bugs or vulnerabilities. On `main`, the issue check counts all of them, so this PR clears them:

| Rule | Count | Action |
|---|---|---|
| S1186 empty closure | 7 | a comment in the closure that says why it is empty |
| S108 empty block | 6 | a comment in the block that says why it is empty |
| S3661 `try!` in tests | 3 | `try` in a throwing test or helper |
| S3358 nested ternary | 4 | `if`/`switch` expression |
| S1066 mergeable `if` | 1 | merge the conditions |
| S1659 several variables in one declaration | 1 | one declaration per line |
| S3087 closures nested more than 2 deep | 1 | extract the inner closure |
| S107 initializer with 9 parameters (`TableSession`) | 1 | accept in the SonarCloud UI: a parameter struct only to satisfy the rule adds a type with no other use |

The fixes do not change behavior. `swift test` and the app build stay green.

## Docs

`CONTRIBUTING.md`: CI fails on any open SonarCloud issue in the PR. Fix it, or mark a false positive or an accepted issue in the SonarCloud UI with a reason.

## Verification

- The PR scan shows coverage for `Sources/` and none for `App/Sources/`.
- The quality gate and the issue check pass on the PR and, after the merge, on `main`.
- A Dependabot PR stays green with the Sonar steps skipped.
