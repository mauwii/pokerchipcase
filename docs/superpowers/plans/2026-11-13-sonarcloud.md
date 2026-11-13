# SonarCloud Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CI-based SonarCloud scan with Swift coverage, a quality gate and an open-issue check, starting from zero open issues.

**Architecture:** The existing `test` job writes an `llvm-cov show` report and runs the scan in the `sonarcloud` environment; runs without the token skip the Sonar steps. A second task clears the 24 code smells Automatic Analysis found on `main`.

**Tech Stack:** SonarCloud, `SonarSource/sonarqube-scan-action` v8.4.0, `xcrun llvm-cov`, GitHub Actions, Swift 6.

**Spec:** `docs/superpowers/specs/2026-11-13-sonarcloud.md`

## Global Constraints

- Project key `mauwii_pokerchipcase`, organization `mauwii`.
- `SONAR_TOKEN` only in the environment `sonarcloud`, never a repo secret.
- Every action pinned by commit SHA with a version comment.
- The Swift fixes change no behavior; `swift test` and the app build stay green.
- Code, comments, docs and commits in English; Conventional Commits.

## Review Focus

- A Dependabot PR (no token): the `test` job passes on `swift test` alone, every Sonar step skipped, and the coverage table still lands in the job summary.
- The report contains only `Sources/` files, never `Tests/` or `.build/`.
- `coverage.report` must not be committed (`.gitignore`).
- The issue-check `SCOPE` on a `push` to `main` must be `branch=main`, on a PR `pullRequest=<number>`; a wrong scope passes silently with `total: 0`.
- An empty closure "fixed" by deleting it changes behavior (e.g. a required callback); the fix is a comment, not a removal.

---

### Task 1: Sonar config and CI

**Files:**

- Create: `sonar-project.properties`
- Modify: `.gitignore`, `.github/workflows/ci.yml` (job `test`), `CONTRIBUTING.md`, `AGENTS.md`

**Interfaces:**

- Produces: the file name `coverage.report`; the environment name `sonarcloud`.

- [ ] **Step 1: `sonar-project.properties`** exactly as in the spec section "sonar-project.properties".

- [ ] **Step 2: `.gitignore`** gets the line `coverage.report`.

- [ ] **Step 3: Job `test` in `ci.yml`** becomes:

```yaml
  test:
    runs-on: macos-latest
    timeout-minutes: 30
    environment: sonarcloud
    env:
      # Dependabot and fork PRs get no environment secrets
      HAS_SONAR_TOKEN: ${{ secrets.SONAR_TOKEN != '' }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          # SonarCloud needs the history for new-code detection and blame
          fetch-depth: 0
      - run: swift test --enable-code-coverage
      # coverage.report: llvm-cov show text format, read by sonar.swift.coverage.reportPaths;
      # the per-file table goes to the job summary, also for runs without the token
      - name: Coverage report
        run: |
          BIN=$(swift build --show-bin-path)
          OBJECTS=("$BIN/PokerCoreTests.xctest/Contents/MacOS/PokerCoreTests"
            -object "$BIN/PokerNetTests.xctest/Contents/MacOS/PokerNetTests"
            -object "$BIN/PokerSessionTests.xctest/Contents/MacOS/PokerSessionTests")
          PROFILE="$BIN/codecov/default.profdata"
          xcrun llvm-cov show -instr-profile "$PROFILE" "${OBJECTS[@]}" Sources > coverage.report
          {
            echo '### Coverage'
            echo '```text'
            xcrun llvm-cov report -instr-profile "$PROFILE" "${OBJECTS[@]}" Sources | sed "s|^$PWD/Sources/||"
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"
      - name: SonarCloud scan
        if: env.HAS_SONAR_TOKEN == 'true'
        uses: SonarSource/sonarqube-scan-action@4d1dc0c91ee400dcf8a6dddf2f705ac36542e304 # v8.4.0
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      # Sonar way rates new code smells only by their debt ratio, so it passes even
      # critical ones; accepted and false-positive issues do not count
      - name: Fail on open SonarCloud issues
        if: env.HAS_SONAR_TOKEN == 'true'
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SCOPE: ${{ github.event_name == 'pull_request' && format('pullRequest={0}', github.event.number) || format('branch={0}', github.ref_name) }}
        run: |
          curl --fail --silent --show-error --header "Authorization: Bearer $SONAR_TOKEN" \
            "https://sonarcloud.io/api/issues/search?componentKeys=mauwii_pokerchipcase&$SCOPE&resolved=false&ps=100" > issues.json
          jq -r '.issues[] | "::error file=\(.component | sub("^[^:]*:"; "")),line=\(.line // 1),title=\(.rule)::\(.message)"' issues.json
          jq -e '.total == 0' issues.json
```

Note: the package builds three test binaries (`PokerCoreTests`, `PokerNetTests`, `PokerSessionTests`), so the report merges them with `-object`. Locally this covers 16 of the 17 files in `Sources/`; `PokerCore/Command.swift` has no executable code.

- [ ] **Step 4: Docs**

- `CONTRIBUTING.md`, after the Checks code block and the pre-commit paragraph: "CI also runs a SonarCloud scan and fails on any open SonarCloud issue in the pull request. Fix it, or mark a false positive or an accepted issue in SonarCloud with a reason."
- `AGENTS.md`, Planning workflow: the deferred-issue labels become "`core`, `net`, `protocol`, `app` or `tooling`".

- [ ] **Step 5: Verify locally**

Run: `swift test --enable-code-coverage >/dev/null && BIN=$(swift build --show-bin-path) && xcrun llvm-cov show -instr-profile "$BIN/codecov/default.profdata" "$BIN/PokerCoreTests.xctest/Contents/MacOS/PokerCoreTests" -object "$BIN/PokerNetTests.xctest/Contents/MacOS/PokerNetTests" -object "$BIN/PokerSessionTests.xctest/Contents/MacOS/PokerSessionTests" Sources > coverage.report && grep -c '^/.*\.swift:$' coverage.report && grep -c '/Tests/' coverage.report; git status --short coverage.report; pre-commit run --all-files`
Expected: `16`, then `0`, no `git status` line for `coverage.report`, all hooks `Passed` (actionlint and zizmor cover the new steps).

- [ ] **Step 6: Commit**

```bash
git add sonar-project.properties .gitignore .github/workflows/ci.yml CONTRIBUTING.md AGENTS.md
git commit -m "ci: add SonarCloud scan with Swift coverage"
```

### Task 2: Clear the open SonarCloud issues

**Files:** the ones the API lists. As of 2026-11-13 on `main`:

| Rule | Locations |
|---|---|
| S1186 empty closure | `App/Sources/StartView.swift:87`, `:88`; `App/Sources/TableScreen.swift:20`; `Sources/PokerNet/TableHost.swift:27`, `:255`; `Tests/PokerNetTests/Helpers.swift:148`; `Tests/PokerNetTests/HostCommandTests.swift:17` |
| S108 empty block | `Sources/PokerNet/TableClient.swift:123`; `Sources/PokerNet/TableHost.swift:111`, `:131`; `Sources/PokerSession/SaveFile.swift:27`; `Tests/PokerNetTests/ClientTests.swift:64`; `Tests/PokerNetTests/Helpers.swift:168` |
| S3661 `try!` | `Tests/PokerNetTests/ClientTests.swift:192`, `:234`; `Tests/PokerNetTests/Helpers.swift:105` |
| S3358 nested ternary | `App/Sources/OvalTable.swift:96`, `:100`, `:124`; `App/Sources/Theme.swift:92` |
| S1066 mergeable `if` | `App/Sources/ActionBar.swift:24` |
| S1659 several variables in one declaration | `App/Sources/OvalTable.swift:14` |
| S3087 closures nested deeper than 2 | `Tests/PokerNetTests/DiscoveryTests.swift:88` |
| S107 9-parameter init | `Sources/PokerSession/TableSession.swift:51`: no code change; the maintainer marks it Accepted in SonarCloud with the reason "a parameter struct only for this rule adds a type with no other use" |

Re-check the list first: `curl -s "https://sonarcloud.io/api/issues/search?componentKeys=mauwii_pokerchipcase&resolved=false&ps=100" | jq -r '.issues[] | "\(.rule) \(.component|sub("^[^:]*:";"")):\(.line)"'`. Line numbers may have moved; fix what the API lists.

**Interfaces:**

- Consumes: nothing from Task 1.

- [ ] **Step 1: Fix each finding**

- S1186 / S108: a comment inside the closure or block that says why it is empty (e.g. `// Nothing to clean up: the listener owns no resources.`). Never delete the closure or block.
- S3661: `try` in a `throws` test or helper; where the context cannot throw (a stored property initializer), make it a `throws` function or use `#require`.
- S3358: an `if`/`switch` expression or a small local `let` per branch.
- S1066: one `if` with both conditions joined by `,`.
- S1659: one declaration per line.
- S3087: extract the innermost closure into a local function in the test.

- [ ] **Step 2: Verify**

Run: `swift test 2>&1 | tail -1 && xcodegen generate --spec App/project.yml >/dev/null && xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet && echo BUILD OK && pre-commit run --all-files`
Expected: `✔ Test run with 91 tests … passed`, `BUILD OK`, all hooks `Passed`.

- [ ] **Step 3: Commit**

```bash
git add -u
git commit -m "refactor: clear SonarCloud code smells"
```

- [ ] **Step 4: Push and open the PR**

Before the push, the maintainer has: turned off Automatic Analysis, created the environment `sonarcloud` with `SONAR_TOKEN`, allowed `SonarSource/sonarqube-scan-action@*`, and marked S107 Accepted. The PR body links the spec and this plan. Expected on the PR: the scan step uploads coverage for `Sources/` only, the gate and the issue check pass. If the PR shows no coverage for `Sources/`, switch to the spec's lcov fallback in the same PR.
