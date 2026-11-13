# Ponytail Audit Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the boilerplate the 2026-11-12 ponytail audit found (≈55 lines), with no behavior change except one wire-format simplification.

**Architecture:** Pure deletions and one modifier hoist. Two PRs: PR A (Tasks 1–2, Swift package + app views, no behavior change), PR B (Task 3, protocol change, needs the user's go-ahead because it changes `docs/PROTOCOL.md`).

**Tech Stack:** Swift 6, Swift Testing, SwiftUI (iOS 17).

**Spec:** the audit result, re-checked against `main` at `ebe75b9`:

| # | Audit finding | Verdict |
|---|---|---|
| 1 | Explicit `public init` on `LegalActions`, `Pot`, `QuickPick`, `SeatTicket`, `HostSnapshot` | **Valid.** Only their own module and `@testable` tests build them; the App builds none. |
| 2 | Hand-written `init` equal to the synthesized one in `TableView`, `HostMenu`, `NextHandBar`, `RankingView` | **Valid.** None has a `private` stored property. |
| 3 | `Hello.protocolVersion` "can never fire" | **Partly wrong.** It fires when `v` and `protocolVersion` differ; `HostLobbyTests.versionMismatchSendsErrorAndCloses` tests exactly that. It is redundant with the envelope `v`, not dead. Still removable — see Task 3. |
| 4 | `RankingView` repeats `session.leave()` + `onLeave()` | **Valid.** |
| 5 | Banner repeats `.frame(maxWidth: .infinity).padding(6).background(.bar)` 3× | **Valid.** |
| 6 | `onStopped: … = {}` default has one caller | **Wrong — drop.** Three test callers rely on the default (`Tests/PokerNetTests/Helpers.swift:171`, `ClientTests.swift:51`, `ChannelTests.swift:100`). |

## Global Constraints

- No external dependencies; no new files except this plan
- All code, comments, commits and PR text in English
- Package check: `swift test` → all tests pass
- **App build check**, from the repo root:

  ```bash
  xcodegen generate --spec App/project.yml && xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet
  ```

  Expected: exit code 0

## Review Focus

- `@testable import` must stay on every test file that builds the five types of Task 1; a plain `import` turns their now-internal init into a compile error, which `swift test` catches.
- `HostMenu.pending` is `@Binding`; the synthesized init keeps the label `pending: Binding<HostConfirm?>`, so `TableScreen` must compile unchanged.
- The banner hoist must not draw an empty `.bar` strip when no banner applies: modifiers on an empty `@ViewBuilder` result render nothing, check in the simulator once.
- Task 3: an old client (still sending `protocolVersion`) must still be accepted by a new host — `Codable` ignores unknown keys, so no code is needed, only confirm in review.
- Task 3: after the change, the host's envelope-`v` rejection path (`TableHost.swift:106`) must be covered by a host test; today only the redundant `protocolVersion` path is.

---

## PR A: `chore/ponytail-cleanup`

### Task 1: Drop redundant memberwise inits in the package

**Files:**

- Modify: `Sources/PokerCore/Hand.swift:262-267` (`LegalActions`)
- Modify: `Sources/PokerCore/Types.swift:85-88` (`Pot`)
- Modify: `Sources/PokerSession/Display.swift:9-12` (`QuickPick`)
- Modify: `Sources/PokerSession/SaveFile.swift:44-49` (`SeatTicket`)
- Modify: `Sources/PokerNet/HostSnapshot.swift:13-18` (`HostSnapshot`)

**Interfaces:**

- Produces: the same initializer labels as today, now `internal` (synthesized). No caller outside the declaring module exists.

- [ ] **Step 1: Delete the five `public init(...)` blocks.** Keep everything else in each type.
- [ ] **Step 2: Run `swift test`.** Expected: all tests pass. A compile error naming one of the five types means a non-`@testable` caller exists: restore that one init and note it in the PR.
- [ ] **Step 3: Run the App build check.** Expected: exit code 0.
- [ ] **Step 4: Commit** `refactor: drop memberwise inits Swift already synthesizes`

### Task 2: Trim app view boilerplate

**Files:**

- Modify: `App/Sources/TableView.swift:9-12`, `App/Sources/HostMenu.swift:18-22`, `App/Sources/ShowdownView.swift:69-72` (`NextHandBar`), `App/Sources/RankingView.swift:10-14` — delete the hand-written `init`
- Modify: `App/Sources/TableScreen.swift:28` — pass `onLeave: leave` to `RankingView`
- Modify: `App/Sources/RankingView.swift:30-35` — button action becomes `Button("Leave table", action: onLeave)`
- Modify: `App/Sources/TableScreen.swift:66-74` — banner hoist

**Interfaces:**

- Consumes: `TableScreen.leave()` (private, already calls `session.leave()` then `onLeave()`).
- Keep the explicit `init` in `TableScreen`, `ActionBar`, `ShowdownView`, `LobbyView`: their `@State private` properties make the synthesized init private.

- [ ] **Step 1: Delete the four inits; route RankingView's leave through `TableScreen.leave`.**
- [ ] **Step 2: Hoist the banner modifiers.** `banner` becomes a `Group { if … Text("Reconnecting…") else if … Text("Sending…") else if … Text(rejection.message).foregroundStyle(.red) }` with `.frame(maxWidth: .infinity).padding(6).background(.bar)` applied once to the `Group`.
- [ ] **Step 3: Run the App build check.** Expected: exit code 0.
- [ ] **Step 4: Check in the simulator:** no banner strip while connected and idle; "Sending…" strip appears on an action.
- [ ] **Step 5: Commit** `refactor(app): drop synthesized view inits, reuse leave, hoist banner style`

PR A is UI-touching: open it, do not auto-merge; the user reviews.

---

## PR B: `chore/drop-hello-protocol-version` (only after the user approves)

### Task 3: Remove `Hello.protocolVersion`, rely on the envelope `v`

**Files:**

- Modify: `Sources/PokerCore/Wire.swift:3-14` — remove the field and its init parameter
- Modify: `Sources/PokerNet/TableHost.swift:148` — delete the `protocolVersion` guard
- Modify: `Sources/PokerNet/TableClient.swift:113` — `Hello(name: name, token: token)`
- Modify: `Tests/PokerNetTests/Helpers.swift:83-85` — drop the `version:` parameter of `hello(_:token:version:)`
- Modify: `Tests/PokerNetTests/HostLobbyTests.swift:80,89` — send a raw `v:2` hello instead
- Modify: `Tests/PokerCoreTests/WireTests.swift:23-30` — expected JSON without `protocolVersion`
- Modify: `docs/PROTOCOL.md:50,138,162` — example, error table row, versioning paragraph

**Interfaces:**

- Produces: `public struct Hello { var name: String; var token: String? }`, `init(name:token:)`.

- [ ] **Step 1: Rewrite the two host tests to send the envelope mismatch** (covers `TableHost.swift:106`, untested today):

```swift
ben.sendRaw(Data(#"{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Ben"},"type":"hello","v":2}"#.utf8))
#expect(try await ben.error() == WireErrorCode.versionMismatch.rawValue)
```

- [ ] **Step 2: Run `swift test --filter HostLobbyTests`.** Expected: PASS (the `v` path already exists, so these pass before the removal too).
- [ ] **Step 3: Remove the field, guard and test/doc references listed above.** WireTests expected JSON: `{"id":"…0001","payload":{"name":"Anna"},"type":"hello","v":1}`. PROTOCOL.md: `versionMismatch` row reads "`v` does not match"; versioning paragraph drops the `hello.protocolVersion` sentence.
- [ ] **Step 4: Run `swift test` and the App build check.** Expected: all pass, exit code 0.
- [ ] **Step 5: Commit** `refactor(protocol): drop hello.protocolVersion, the envelope v already carries it`

PR B is fully covered by tests: open with `gh pr merge --auto --merge`.
