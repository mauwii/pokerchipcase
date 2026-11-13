# Deferred Issue Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the small, fully specified deferred issues in two PRs: tests and tooling (#54, #42 partly, #74, #75, #77, #78, #79, #81) and app guards (#63, #64, #44 partly).

**Architecture:** No new types. Each task is the fix the issue suggests, in the file the issue names. PR A has test coverage or is CI config and auto-merges; PR B is UI-only and waits for the user's manual check on an iPhone.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, GitHub Actions, pre-commit (markdownlint-cli2, actionlint).

**Spec:** The issue bodies are the spec: `gh issue view <N>`.

## Global Constraints

- Swift 6 language mode; fix concurrency errors, do not silence them.
- Code, comments, docs, commits, issue comments in English.
- Conventional Commits: `test(core): …`, `ci: …`, `chore: …`, `fix(app): …`.
- Each commit body ends with `Closes #N` for the issue it fixes (`Refs #N` when only part of it).
- The four CI commands in `AGENTS.md` pass before each PR.
- Both branches start from `origin/main` (`eefb413` or newer), not from `fix/docs-protocol-anchor`.

## Out of scope

- #73: the tag pin is deliberate (comment in `.pre-commit-config.yaml:23`: Dependabot matched the frozen comment against other crates' tags). Close with that reason.
- #42 bullet "snapshotWithoutHostTokenThrows does not assert the save file": already done (`Tests/PokerSessionTests/SessionTests.swift:239`). Bullets 1–3 stay open.
- #44 bullet 3 (turn haptic): stays open, not a regression.
- #85, #83, #71, #39, #35, #26, #23, #19: larger or need a device; later plans.

## Review Focus

1. CLAUDE.md with the markdownlint comment: Claude Code must still load `AGENTS.md` through `@AGENTS.md`.
2. Sonar issue check after a failed scan step: must still run when the scan fails, and must not run on a cancelled workflow or without the token.
3. A host dialog open while a guest's action changes `state.version`: dialog closes, nothing is sent.
4. Two consecutive showdowns with identical pots (guest dealer reconnecting): winner picks reset at the new hand.
5. Exactly two pots: picker and table both say "Main" and "Side"; three pots say "Side 1", "Side 2".

---

## PR A: branch `fix/deferred-tests-tooling`

### Task 1: Legacy hello and client events tests (#54, #42)

**Files:**

- Modify: `Tests/PokerCoreTests/WireTests.swift` (after `helloGoldenJSON`, line 22)
- Modify: `Tests/PokerNetTests/ClientTests.swift` (in `ClientTests`)

**Interfaces:**

- Consumes: `Wire.decodeClient(_:)`, `Hello(name:token:)`, `client(_ port:)` and `startHost()` helpers, `EventRecorder.waitForEnd()`.

- [ ] **Step 1: Add `legacyHelloWithProtocolVersionDecodes`**

```swift
@Test func legacyHelloWithProtocolVersionDecodes() throws {
    let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Anna","protocolVersion":1},"type":"hello","v":1}"#.utf8)
    #expect(try Wire.decodeClient(data).message == .hello(Hello(name: "Anna", token: nil)))
}
```

- [ ] **Step 2: Add `eventsFinishWhenClientIsReleased`**

Build the client with `TableClient(endpoint:code:name:retryDelay:)` into a `var ben: TableClient?` (as in `DiscoveryTests.swift:37`), `let events = EventRecorder(ben!.events)`, `ben = nil`, then `#expect(try await events.waitForEnd() == nil)`. Do not connect; the test pins `continuation.finish()` in `TableClient.deinit`.

- [ ] **Step 3: Run**

Run: `swift test --filter 'legacyHelloWithProtocolVersionDecodes|eventsFinishWhenClientIsReleased'`
Expected: both PASS (they pin current behavior). Comment out `continuation.finish()` in `Sources/PokerNet/TableClient.swift:64` once: the second test must time out. Restore it.

- [ ] **Step 4: Commit**

`test: pin legacy hello decoding and client event stream end` with `Closes #54` and `Refs #42`.

### Task 2: Markdown lint config (#74, #75)

**Files:**

- Modify: `.markdownlint.yaml` (delete the `MD041` comment and line)
- Modify: `.github/pull_request_template.md`, `CLAUDE.md` (append `<!-- markdownlint-disable-file MD041 -->` as the last line, after `@AGENTS.md`)
- Modify: `.editorconfig` (append `[*.md]` with `indent_size = 2`)

- [ ] **Step 1: Make the three edits**
- [ ] **Step 2: Run** `pre-commit run --all-files`. Expected: all hooks pass.
- [ ] **Step 3: Check the import:** `claude -p "Quote the first heading of AGENTS.md as loaded in your context, without reading files"` from the repo root. Expected: `# AGENTS.md`. If the comment breaks the import, move it to the first line and repeat.
- [ ] **Step 4: Commit** `chore: scope MD041 to the files without a title and indent Markdown by 2` with `Closes #74` and `Closes #75`.

### Task 3: Sonar issue step (#77, #78, #79, #81)

**Files:**

- Modify: `.github/workflows/ci.yml:28` (environment), `:68` (step `if`), `:75` (jq filter)

- [ ] **Step 1: #77** Set the "Fail on open SonarCloud issues" step to `if: ${{ !cancelled() && env.HAS_SONAR_TOKEN == 'true' }}`.
- [ ] **Step 2: #78** In the `::error` jq line, replace `\(.message)` with `\(.message | gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A"))`.
- [ ] **Step 3: #79** No code change. SonarCloud's `api/webservices/list` lists `componentKeys` for `api/issues/search` without `deprecatedSince` and has no `components` (checked 2026-11-13). Close #79 with that finding.
- [ ] **Step 4: #81** Read the `jobs.<job_id>.environment` section of the GitHub workflow syntax docs. If it documents `deployment: false`, change line 28 to `environment: { name: sonarcloud, deployment: false }` and confirm the environment secret still reaches the job (scan step runs on the PR). If not documented, close #81 as not supported, with the docs link.
- [ ] **Step 5: Run** `pre-commit run actionlint --all-files`. Expected: pass.
- [ ] **Step 6: Commit** `ci: annotate Sonar issues on a failed gate and escape their messages` with `Closes #77`, `Closes #78` (and `Closes #81` if Step 4 changed the file).

### Task 4: PR A

- [ ] Run the four `AGENTS.md` commands; all pass.
- [ ] Push, `gh pr create` with this plan linked, then `gh pr merge --auto --merge`.
- [ ] Close #73 and #79 with their reasons; comment on #42 and #44 which bullets remain.

---

## PR B: branch `fix/app-deferred`

### Task 5: Pot names and showdown guards (#63, #64, #44)

**Files:**

- Modify: `App/Sources/OvalTable.swift:136-138` (`potName` becomes a file-level function)
- Modify: `App/Sources/ShowdownView.swift:25` (picker label)
- Modify: `App/Sources/TableView.swift:52-55` (reset), `:74` (guard)
- Modify: `App/Sources/TableScreen.swift` (clear `hostPending`)
- Modify: `docs/superpowers/specs/2026-11-13-table-redesign.md:62` (picker position)

**Interfaces:**

- Produces: `func potName(_ index: Int, of count: Int) -> String` in `OvalTable.swift`, internal. Returns `"Main"` for 0, `"Side"` when `count == 2`, else `"Side \(index)"`.

- [ ] **Step 1: #64** Move `potName` out of `OvalTable` with the signature above; call it as `potName($0, of: state.pots.count)` in `OvalTable` and as `Text("\(potName(i, of: state.pots.count)) \(state.pots[i].amount)")` in the picker. In the spec line 62, replace "above the table" with "in the bottom bar below the table".
- [ ] **Step 2: #63** `toggle` guard: `guard state.pots.indices.contains(pot), winners.indices.contains(pot), state.pots[pot].eligible.contains(id) else { return }`.
- [ ] **Step 3: #44 picks** Move the body of the `onChange(of: state.pots, initial: true)` closure into `private func resetPicks()`; call it from that `onChange` and from a new `.onChange(of: state.handNumber) { resetPicks() }`.
- [ ] **Step 4: #44 host dialogs** In `TableScreen`, next to `.hostConfirmation($hostPending, session: session)`, add `.onChange(of: session.state?.version) { hostPending = nil }` (same pattern as the all-in dialog in `ActionBar.swift:56`).
- [ ] **Step 5: Build** the app with the `AGENTS.md` app build command. Expected: no errors, no new warnings.
- [ ] **Step 6: Commit** `fix(app): share pot names and reset stale showdown picks and host dialogs` with `Closes #63`, `Closes #64`, `Refs #44`.

### Task 6: PR B

- [ ] Push, `gh pr create` with this plan linked and a manual test list (Review Focus 3–5). No auto-merge; the user checks on the iPhone (`-debugTable` gives bots for the side-pot case).
