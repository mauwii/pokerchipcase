# Low-Hanging Fruits Implementation Plan

**Status:** implemented 2026-11-12 in PRs #40 (CI), #43 (net hardening), #45 (app polish), #48 (session tests), and the PR adding this file (create-table flow). Deviations: the DerivedData cache from Task 1 was dropped (the app job takes ~35 s); final reviews ran combined with the task review for the one- and two-task PRs. Deferred findings: #41, #42, #44, #46, #47.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 19 small deferred issues (#8 #9 #10 #12 #13 #14 #16 #18 #21 #22 #24 #25 #27 #28 #29 #30 #31 #32 #37) plus the pending CI trigger change, in five independent PRs.

**Architecture:** No new types or files except tests. Every fix is a guard, a reorder or a changed SwiftUI trigger at the place the issue names. Each PR is its own branch from `main`; PRs do not depend on each other and can merge in any order (PR 1 first is recommended, so later PRs get the faster CI).

**Tech Stack:** Swift 6, Swift Testing, Network.framework, SwiftUI (iOS 17), GitHub Actions.

**Spec:** the GitHub issues listed above (`gh issue view <n>`); protocol rules in `docs/PROTOCOL.md`.

## Global Constraints

- No external dependencies; package platforms stay `.iOS(.v17)`, `.macOS(.v14)`
- All code, comments, UI copy, commits and PR text in English
- Test suites keep `.timeLimit(.minutes(1))`; network waits use the existing `eventually` / `EventRecorder` helpers (max 5 s)
- Package check: `swift test` → all tests pass
- **App build check** (Tasks 8–11, 13–14), from the repo root:
  ```bash
  xcodegen generate --spec App/project.yml && xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet
  ```
  Expected: exit code 0
- Each PR body lists `Closes #n` for every issue it fixes. An issue whose fix was cut short gets a comment saying what was left out instead of being closed
- New review findings that are deferred become GitHub issues with the label `deferred` plus the area label (`net`, `app`, `core`, `protocol`)

## Executor Routing

| Task | Implementer | Task reviewer |
|---|---|---|
| 1 | inline, no subagent | — |
| 2–6 | haiku medium (tests and guards given) | opus high (protocol/networking) |
| 8–11, 14 | sonnet medium | sonnet medium (UI diff) |
| 12, 13 | sonnet medium | sonnet medium |
| End of each PR 2–5 | — | fable high, whole branch |

## Review Focus

1. **Real host relaunch:** the app relaunches, binds a new port (`.any`) and guests find it again only via Bonjour → `resumeOnNewPortViaBonjour` (Task 12).
2. **Host suspension drops every connection, the loopback client too:** after `appBecameActive()` the host device must be connected again, not stuck on "Reconnecting…" → `appBecameActiveReconnectsTheHostClient` (Task 12).
3. **Failed "Create table" while an old save exists:** the old tournament must survive the failed attempt → `failedStartRestoresThePreviousSave` (Task 13).
4. **A message exactly at the 1 MiB limit** must still arrive; only larger ones fail → `messageAtTheLimitArrives` (Task 6).
5. **Legit reconnects after the hello guards:** a client that reconnects on a new connection with its token must still get its seat back. Existing `reconnectWithTokenKeepsSeat` and `secondConnectionWithSameTokenReplacesFirst` cover it; Task 2 must keep them green.

---

## PR 1 — branch `ci/app-job`

### Task 1: CI push trigger, app job name, build cache (#28)

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Restrict the push trigger to `main`**

`on.push` gets `branches: [main]`; `pull_request` stays unfiltered. `rerun.yml` listens on `workflow_run` of `CI` and needs no change.

- [ ] **Step 2: Name the job and cache DerivedData**

Job `app` gets `name: App build`. Before the `xcodegen` step, add `actions/cache@v4` with:
- `path: .build/app`
- `key: app-${{ runner.os }}-${{ hashFiles('App/**', 'Sources/**', 'Package.swift') }}`
- `restore-keys: app-${{ runner.os }}-`

There is no `Package.resolved` (no dependencies), so it is not part of the key.

- [ ] **Step 3: Lint**

Run: `actionlint .github/workflows/ci.yml` (skip if not installed). Expected: no output.

- [ ] **Step 4: Commit, push, open PR**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run push builds only on main, name and cache the app job"
```

- [ ] **Step 5: Measure**

Compare the `App build` duration of the first PR run (cold cache) and a re-run (warm cache) via `gh run view --json jobs`. If the warm run is not faster by at least 1 minute, remove the cache step again (fresh checkouts reset mtimes, so Xcode may rebuild everything anyway) and note that in the PR body; the job name and trigger stay.

---

## PR 2 — branch `fix/net-hardening`

### Task 2: Ignore messages of dropped connections, accept `hello` only once (#8, #9)

**Files:**
- Modify: `Sources/PokerNet/TableHost.swift` (`receive`, `welcome`)
- Modify: `docs/PROTOCOL.md:53`
- Test: `Tests/PokerNetTests/HostLobbyTests.swift`

**Interfaces:**
- Produces: a second `hello` on a bound connection is answered with `.error(WireErrorCode.malformed.rawValue)`, envelope id = the hello's id; the connection stays open (same as other `malformed` cases, PROTOCOL.md table line 142).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func messagesAfterRejectionAreIgnored() async throws {
    let (host, port) = try await startHost()
    let ben = try await RawClient.connect(port)
    ben.send(hello("Ben", version: 2))
    ben.send(hello("Cem"))
    try await ben.waitForClose()
    try await Task.sleep(for: .milliseconds(200))
    #expect(await host.snapshot.game.state.seats.map(\.name) == ["Anna"])
    await host.stop()
}

@Test func secondHelloIsMalformedAndDoesNotJoinAgain() async throws {
    let (host, port) = try await startHost()
    let ben = try await RawClient.connect(port)
    ben.send(hello("Ben"))
    _ = try await ben.welcome()
    let id = UUID()
    ben.send(hello("Ben"), id: id)
    let reply = try await ben.nextEnvelope { $0.error != nil }
    #expect(reply.message.error == WireErrorCode.malformed.rawValue && reply.id == id)
    #expect(await host.snapshot.game.state.seats.map(\.name) == ["Anna", "Ben"])
    await host.stop()
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `swift test --filter "messagesAfterRejectionAreIgnored|secondHelloIsMalformedAndDoesNotJoinAgain"`
Expected: both FAIL (seats contain `"Cem"` resp. a second `"Ben"`).

- [ ] **Step 3: Implement**

- `receive(_:from:)`: first line `guard channels[id] != nil else { return }`.
- `welcome(_:from:requestID:)`: first line `guard bound[id] == nil else { return send(.error(WireErrorCode.malformed.rawValue), to: id, envelopeID: requestID) }`.
- `docs/PROTOCOL.md:53`: append "A second `hello` on the same connection is answered with `malformed`."

- [ ] **Step 4: Run, expect PASS**

Run: `swift test --filter PokerNetTests`. Expected: all pass, including `reconnectWithTokenKeepsSeat` and `secondConnectionWithSameTokenReplacesFirst`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokerNet/TableHost.swift docs/PROTOCOL.md Tests/PokerNetTests/HostLobbyTests.swift
git commit -m "fix(net): ignore messages of dropped connections, accept hello once"
```

### Task 3: Listener lifecycle and save order in TableHost (#10, #13, #14)

**Files:**
- Modify: `Sources/PokerNet/TableHost.swift` (`start(port:)`, `accept`, `handle`)
- Test: `Tests/PokerNetTests/HostCommandTests.swift`

- [ ] **Step 1: Write the failing test (#14)**

```swift
@Test func secondStartStopsTheFirstListener() async throws {
    let (host, first) = try await startHost()
    _ = try await host.start()
    await host.stop()
    await #expect(throws: (any Error).self) { try await RawClient.connect(first) }
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `swift test --filter secondStartStopsTheFirstListener`
Expected: FAIL, the connect to `first` succeeds.

- [ ] **Step 3: Implement**

- `start(port:)`: first line `listener?.cancel()`. Its `onStopped` callback is harmless: `listenerStopped` compares the id and the new listener is already stored.
- `accept(_:)` (#10): first line `guard listener != nil else { return connection.cancel() }`. No test: the race (accept hop after `stop()`) cannot be triggered deterministically.
- `handle(_:messageID:from:)` (#13): move `onChange(snapshot)` directly after `forgetRemovedPlayers()`, before `broadcastState()`. No new test: `onChange` already runs in the same actor turn, so no ordering is observable from a test; `onChangeAfterCommand` keeps covering that it runs.

- [ ] **Step 4: Run, expect PASS**

Run: `swift test --filter PokerNetTests`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokerNet/TableHost.swift Tests/PokerNetTests/HostCommandTests.swift
git commit -m "fix(net): cancel a replaced listener, refuse connections after stop, save before broadcast"
```

### Task 4: Released TableClient closes its connection (#12)

**Files:**
- Modify: `Sources/PokerNet/TableClient.swift`
- Test: `Tests/PokerNetTests/ClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func releasedClientClosesItsConnection() async throws {
    let (host, port) = try await startHost()
    var ben: TableClient? = TableClient(endpoint: loopback(port), code: code4711, name: "Ben")
    await ben?.connect()
    try await eventually { await host.connectedPlayers.count == 1 }
    ben = nil
    try await eventually { await host.connectedPlayers.isEmpty }
    await host.stop()
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `swift test --filter releasedClientClosesItsConnection`. Expected: FAIL with `TimeoutError`.

- [ ] **Step 3: Implement `deinit` in `TableClient`**

`deinit { channel?.cancel(); continuation.finish() }`. Pending sends need no handling: a running `send` holds `self`, so `pending` is empty at `deinit`. All internal tasks capture `[weak self]`.

- [ ] **Step 4: Run, expect PASS**

Run: `swift test --filter ClientTests`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokerNet/TableClient.swift Tests/PokerNetTests/ClientTests.swift
git commit -m "fix(net): close the connection when a TableClient is released"
```

### Task 5: Corrupt snapshot without host token does not crash (#16)

**Files:**
- Modify: `Sources/PokerNet/HostSnapshot.swift:33-35`
- Modify: `Sources/PokerSession/SaveFile.swift` (`isResumable`)
- Modify: `Sources/PokerSession/TableSession.swift` (`host`)
- Test: `Tests/PokerSessionTests/SessionTests.swift`

**Interfaces:**
- Produces: `public var hostToken: String?` on `HostSnapshot`; `TableSession.host` throws `CocoaError(.fileReadCorruptFile)` when it is nil.

- [ ] **Step 1: Write the failing test**

```swift
@Test func snapshotWithoutHostTokenThrows() async throws {
    var snap = HostSnapshot.newTable(hostName: "Anna", tableName: "Test", code: code4711, config: .relaxed)
    snap.tokens = [:]
    await #expect(throws: CocoaError.self) { try await TableSession.host(snap, saveFile: tempFile()) }
}
```

- [ ] **Step 2: Run, expect FAIL**

Add `import Foundation` to the test file if `CocoaError` does not resolve.

Run: `swift test --filter snapshotWithoutHostTokenThrows`. Expected: crash in `hostToken` (force unwrap).

- [ ] **Step 3: Implement**

- `hostToken` returns `tokens.first { $0.value == game.state.hostID }?.key`.
- `TableSession.host`: first line `guard let token = snapshot.hostToken else { throw CocoaError(.fileReadCorruptFile) }`, pass `token` to the `TableClient`.
- `isResumable`: `hostToken != nil && game.state.phase != .finished`.
- Test call sites pass `hostToken` to `token: String?` parameters and compile unchanged.

- [ ] **Step 4: Run, expect PASS**

Run: `swift test`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokerNet/HostSnapshot.swift Sources/PokerSession Tests/PokerSessionTests/SessionTests.swift
git commit -m "fix(net): treat a snapshot without host token as corrupt instead of crashing"
```

### Task 6: Tests for the 1 MiB line limit (#18)

**Files:**
- Test: `Tests/PokerNetTests/ChannelTests.swift`

- [ ] **Step 1: Write the tests**

The receiving side's channel must be observable, so the test starts its own listener instead of `startEchoListener`:

```swift
/// PSK listener that hands every accepted channel's recorder to `channels`.
private func startRecordingListener() async throws -> (NWListener, NWEndpoint.Port, AsyncStream<EventRecorder<ChannelEvent>>) {
    let (channels, inbox) = AsyncStream<EventRecorder<ChannelEvent>>.makeStream()
    let listener = try NWListener(using: PSK.parameters(code: code4711), on: .any)
    listener.newConnectionHandler = { connection in
        let channel = MessageChannel(connection: connection)
        inbox.yield(EventRecorder(channel.events))
        channel.start()
    }
    return (listener, try await listener.startAndWaitUntilReady(queue: .global()), channels)
}

@Test func oversizedMessageEndsTheReceiversStream() async throws {
    let (listener, port, channels) = try await startRecordingListener()
    defer { listener.cancel() }
    let sender = MessageChannel(to: loopback(port), code: code4711)
    let rec = EventRecorder(sender.events)
    sender.start()
    _ = try await rec.first { $0 == .ready }
    // Two receive chunks (64 KiB each) beyond the limit, so the newline cannot arrive before the check.
    sender.send(Data(repeating: UInt8(ascii: "a"), count: MessageChannel.maxMessageSize + 131_072))
    var it = channels.makeAsyncIterator()
    let receiver = try #require(await it.next())
    #expect(try await receiver.waitForEnd() as? ChannelError == .messageTooLarge)
    sender.cancel()
}

@Test func messageAtTheLimitArrives() async throws {
    let (listener, port) = try await startEchoListener(code: code4711)
    defer { listener.cancel() }
    let channel = MessageChannel(to: loopback(port), code: code4711)
    let rec = EventRecorder(channel.events)
    channel.start()
    _ = try await rec.first { $0 == .ready }
    let big = Data(repeating: UInt8(ascii: "a"), count: MessageChannel.maxMessageSize)
    channel.send(big)
    _ = try await rec.first { $0 == .message(big) }
    channel.cancel()
}
```

`code4711` comes from `Tests/PokerNetTests/Helpers.swift`.

- [ ] **Step 2: Run, expect PASS**

Run: `swift test --filter ChannelTests`. Expected: all pass (no production change; if `oversizedMessageEndsTheReceiversStream` fails, the limit is broken: stop and report).

- [ ] **Step 3: Commit**

```bash
git add Tests/PokerNetTests/ChannelTests.swift
git commit -m "test(net): cover the 1 MiB message limit"
```

### Task 7: PR 2 wrap-up

- [ ] **Step 1:** `swift test` → all pass.
- [ ] **Step 2:** Whole-branch review (fable high), then open the PR with `Closes #8, #9, #10, #12, #13, #14, #16, #18`.

---

## PR 3 — branch `fix/app-polish`

No unit tests for SwiftUI views; each task ends with the app build check and one simulator run of the described scenario.

### Task 8: ActionBar copy and stale all-in confirmation (#24, #31)

**Files:**
- Modify: `App/Sources/ActionBar.swift`

- [ ] **Step 1: Implement**

- Call button title: `legal.map { "Call \($0.callAmount)" } ?? "Call"`.
- In the existing `.onChange(of: state.version, initial: true)` also set `pending = nil`.

- [ ] **Step 2: App build check** → exit code 0.
- [ ] **Step 3: Simulator:** while waiting, the greyed button reads "Call". Open the all-in dialog, let the host pause the clock: the dialog closes.
- [ ] **Step 4: Commit** `fix(app): plain "Call" while waiting, drop stale all-in confirmation`

### Task 9: Showdown selection, lobby dealer, turn haptic (#25, #32, #37)

**Files:**
- Modify: `App/Sources/ShowdownView.swift:36`
- Modify: `App/Sources/LobbyView.swift`
- Modify: `App/Sources/TableScreen.swift:40`

- [ ] **Step 1: Implement**

- `ShowdownView`: `.onChange(of: state.pots, initial: true)` instead of `state.version`.
- `LobbyView`: on the `Picker`, `.onChange(of: choice) { if $1 == nil { dealer = nil } }` (`choice` already falls back to nil for a seat that left).
- `TableScreen`: `.sensoryFeedback(.impact(weight: .heavy), trigger: session.legalActions != nil ? session.state?.street : nil) { $1 != nil }`. The value changes on every new turn (nil → street) and on a street change during my turn; keep the existing comment about why it lives here.

- [ ] **Step 2: App build check** → exit code 0.
- [ ] **Step 3: Simulator:** half-selected winners survive a clock pause; picker shows "Random" after the chosen dealer is removed. The haptic case needs a device (note it in the PR body as manual check).
- [ ] **Step 4: Commit** `fix(app): keep showdown picks, reset a vanished dealer, haptic on every new turn`

### Task 10: Host menu cleanup (#27)

**Files:**
- Modify: `App/Sources/HostMenu.swift`
- Modify: `App/Sources/StartView.swift`

- [ ] **Step 1: Implement**

- `HostMenu`: `private var removable: [Seat]`. It is empty unless `state.phase` is `.betting` or `.handComplete` (the only phases where `removeFromGame` accepts it), otherwise the seats that are not the host and not eliminated. Show the "Remove player" `Menu` only `if !removable.isEmpty`.
- `hostConfirmation`: replace the local `run(_:)` with inline `Task { await session.send(...) }`.
- `StartView`: delete `resume(_:)`, call `host(savedGame)` directly.
- Not changed: the `""` title for `nil` (the dialog is never presented then) and `TableSession.name` (the guest ticket needs it; the shared init stores it for the host too). Say so in the PR body.

- [ ] **Step 2: App build check** → exit code 0.
- [ ] **Step 3: Commit** `refactor(app): hide impossible removals, inline host menu wrappers`

### Task 11: Cancel the event task on leave (#29)

**Files:**
- Modify: `Sources/PokerSession/TableSession.swift` (`start`, `leave`)

- [ ] **Step 1: Implement**

Store the `Task` created in `start()` in `private var eventTask: Task<Void, Never>?`; `leave()` calls `eventTask?.cancel()` first. Cancelling ends the `for await` over the `AsyncStream`. No test: one stored property and one call.

- [ ] **Step 2:** `swift test --filter SessionTests` → all pass.
- [ ] **Step 3: Commit** `fix(session): cancel the event task when leaving a table`

PR 3 wrap-up: whole-branch review (fable high), PR with `Closes #24, #25, #27, #29, #31, #32, #37`.

---

## PR 4 — branch `test/session-gaps`

### Task 12: PokerSession test gaps (#22)

**Files:**
- Test: `Tests/PokerSessionTests/DisplayTests.swift`
- Test: `Tests/PokerSessionTests/SessionTests.swift`

- [ ] **Step 1: Write the tests**

```swift
// DisplayTests.swift: A button, B/C blinds with 1 chip each, D acts first; values verified on main.
@Test func halfPotClampedToMinRaise() throws {
    var g = Game(hostID: "A", hostName: "A",
                 config: TournamentConfig(startingStack: 1000, levels: [BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600)]))
    for p in ["B", "C", "D"] { try g.apply(.join(player: p, name: p), by: "A", at: t0) }
    for p in ["B", "C"] { g.state.seats[g.state.index(of: p)!].stack = 1 }
    try g.apply(.startTournament(button: "A"), by: "A", at: t0)
    #expect(g.state.quickPicks(for: "D") == [
        QuickPick(kind: .halfPot, raiseTo: 40), QuickPick(kind: .pot, raiseTo: 42), QuickPick(kind: .allIn, raiseTo: 1000),
    ])
}

@Test func raiseAboveTheStackAndBlindCallCountAsAllIn() throws {
    #expect(try started().state.commitsAllChips(.raiseTo(amount: 5000), by: "A"))
    var g = try started(stacks: ["B": 20])  // B posts 10, has 10 left
    try g.act(.call)  // A
    #expect(g.state.commitsAllChips(.call, by: "B"))
    #expect(try !started(stacks: ["B": 40]).state.commitsAllChips(.call, by: "B"))
}
```

```swift
// SessionTests.swift
@Test func appBecameActiveReconnectsTheHostClient() async throws {
    let anna = try await hostSession()
    defer { Task { await anna.leave() } }
    let h = anna.tableHost!
    // Like an iOS suspension: listener and every connection, the loopback client's too, are gone.
    await h.simulateListenerFailure()
    await h.disconnectAll()
    try await eventually { anna.connection == .reconnecting }
    await anna.appBecameActive()
    try await eventually { anna.connection == .connected }
    let cem = await guestSession(anna, name: "Cem")
    defer { Task { await cem.leave() } }
    // The host's own client receives broadcasts again.
    try await eventually { anna.state?.seats.count == 2 }
}

@Test func resumeOnNewPortViaBonjour() async throws {
    let name = "T-\(UUID().uuidString.prefix(8))"
    let file: SaveFile<HostSnapshot> = tempFile()
    let anna = try await TableSession.host(
        .newTable(hostName: "Anna", tableName: name, code: code4711, config: .relaxed), saveFile: file)
    let ben = await TableSession.join(
        endpoint: .service(name: name, type: Wire.serviceType, domain: "local.", interface: nil),
        tableName: name, code: code4711, name: "Ben", ticketFile: tempFile())
    defer { Task { await ben.leave() } }
    try await eventually(timeout: .seconds(10)) { ben.me != nil }
    let p = ben.me
    // Crash without leave(), then relaunch on a new port like the app does.
    await anna.tableHost!.stop()
    await anna.client.disconnect()
    let resumed = try await TableSession.host(try #require(file.load()), saveFile: file)
    defer { Task { await resumed.leave() } }
    #expect(resumed.port != anna.port)
    try await eventually(timeout: .seconds(10)) { await resumed.tableHost!.connectedPlayers.contains(p!) }
}
```

`eventually(timeout:)` exists in `Tests/PokerSessionTests/Helpers.swift`; the Bonjour waits get 10 s because resolution is slower than loopback. If the suite's 1-minute limit is hit on CI, move `resumeOnNewPortViaBonjour` into its own `@Suite(.timeLimit(.minutes(1)))`.

The `quickPicks` dedup branch from the issue is unreachable: the pot target is always ≥ `minRaiseTo` (checked on main). Do not test it; say so in the PR body.

- [ ] **Step 2: Run**

Run: `swift test --filter PokerSessionTests`. Expected: all pass. A failure here is a real bug: stop and report it, do not change production code in this task.

- [ ] **Step 3: Commit** `test(session): cover min-raise clamp, all-in calls, host suspension, Bonjour resume`

PR 4 wrap-up: whole-branch review (fable high), PR with `Closes #22`.

---

## PR 5 — branch `fix/create-table`

### Task 13: Failed table start keeps the old save, table name limit (#30)

**Files:**
- Modify: `Sources/PokerSession/TableSession.swift` (`host`)
- Modify: `App/Sources/StartView.swift` (`CreateTableSheet`)
- Test: `Tests/PokerSessionTests/SessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func failedStartRestoresThePreviousSave() async throws {
    let blocker = try await hostSession()  // occupies its port
    defer { Task { await blocker.leave() } }
    let empty: SaveFile<HostSnapshot> = tempFile()
    let new = HostSnapshot.newTable(hostName: "Cem", tableName: "New", code: code4711, config: .relaxed)
    await #expect(throws: (any Error).self) { try await TableSession.host(new, saveFile: empty, port: blocker.port!) }
    #expect(empty.load() == nil)
    let old: SaveFile<HostSnapshot> = tempFile()
    let saved = HostSnapshot.newTable(hostName: "Ben", tableName: "Old", code: code4711, config: .relaxed)
    try old.save(saved)
    await #expect(throws: (any Error).self) { try await TableSession.host(new, saveFile: old, port: blocker.port!) }
    #expect(old.load() == saved)
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `swift test --filter failedStartRestoresThePreviousSave`. Expected: FAIL, `empty.load()` is the new snapshot.

- [ ] **Step 3: Implement**

- `TableSession.host`: read `let previous = saveFile.load()` before the first save. Wrap `host.start(port:)` in `do/catch`; on error, `try? saveFile.save(previous)` if it exists, else `saveFile.delete()`, then rethrow. The save stays before `start`: after `start`, a guest's join could fire `onChange` before the first save and get overwritten.
- `CreateTableSheet`: compute the trimmed final name once. Disable "Create" when its `utf8.count > 63` (Bonjour service name limit, add that as a comment), and show `Text("Name is too long").foregroundStyle(.red)` in the form while it is.

- [ ] **Step 4: Run, expect PASS**

Run: `swift test --filter PokerSessionTests`, then the app build check. Expected: all pass, exit code 0.

- [ ] **Step 5: Commit** `fix(session): keep the old save when a new table fails to open, limit table names to 63 bytes`

### Task 14: Confirm before replacing a resumable game (#21)

**Files:**
- Modify: `App/Sources/StartView.swift`

- [ ] **Step 1: Implement**

"Create table" sets `creating = true` only if `savedGame == nil`. Otherwise it sets a new `@State private var confirmDiscard = false` to true. Attach `.confirmationDialog("Discard the saved game?", isPresented: $confirmDiscard, titleVisibility: .visible)` with `Button("Discard and create", role: .destructive) { creating = true }`. The save itself is only replaced when the new table starts (Task 13 keeps it on failure).

- [ ] **Step 2: App build check** → exit code 0.
- [ ] **Step 3: Simulator:** with a resumable game, "Create table" asks first; Cancel keeps "Resume game".
- [ ] **Step 4: Commit** `fix(app): confirm before a new table replaces the saved game`

PR 5 wrap-up: whole-branch review (fable high), PR with `Closes #21, #30`.
