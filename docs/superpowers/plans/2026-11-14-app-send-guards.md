# App Send Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the deferred app issues #23 (commands dropped while one is in flight, rejection banner cleared too early) and #26 (join sheet re-identified when a table's endpoint changes); close #44, whose fixable parts shipped in `a5dcdd6`.

**Architecture:** No new types. `TableSession` remembers the state version a rejection belongs to and clears it only on a newer state. The app disables the controls whose taps `TableSession.send` would silently drop. `DiscoveredTable` is identified by its name, and the join uses the endpoint currently listed under that name.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, Network.framework.

**Spec:** The issue bodies are the spec: `gh issue view 23`, `gh issue view 26`, `gh issue view 44`.

## Global Constraints

- Swift 6 language mode; fix concurrency errors, do not silence them.
- Code, comments, docs, commits, issue comments in English.
- Conventional Commits: `fix(session): …`, `fix(app): …`.
- Commit body ends with `Closes #N` for the issue it fixes (`Refs #N` when only part of it).
- No wire-format change: `Protocol.md` stays as is.
- The four CI commands in `AGENTS.md` pass before the PR.
- Branch `fix/app-send-guards` from `origin/main` (`ace4d06` or newer).
- Manual check: one real iPhone plus one simulator. No step needs two real iPhones.

## Out of scope

- #39 (AWDL without a shared network): needs two real iPhones; later.
- #35 (save time late in a tournament): a measurement on the iPhone, not code.
- #44 bullet 3 (turn haptic after coalesced states): accepted as is; it is not a regression, and the closing comment says so.
- Confirmation dialog buttons (`hostConfirmation`, `App/Sources/HostMenu.swift:72-73`) while another send is in flight: the dialog only opens from the menu that Task 2 disables, so this needs a send that starts while the dialog is already open. Not reported, and not addressed here.

## Review Focus

1. A guest reconnects after its command was rejected: the rejoin state has the same version, so the banner must stay (Task 1 test `rejectionSurvivesStateWithSameVersion`).
2. The rejected command is followed by a real change (another player acts): the banner clears (existing `rejectionIsShownUntilTheNextState` keeps passing).
3. A new `send` after a rejection: the banner clears at once, as before (`send` still sets `rejection = nil`).
4. The host deletes two lobby rows in one edit: both are removed, because the loop awaits each send (manual check, Task 4).
5. Two nearby tables with the same name: tapping either opens the sheet, and joining uses an endpoint listed under that name (manual check, Task 4).

---

### Task 1: Clear a rejection only on a newer state (#23)

**Files:**

- Modify: `Sources/PokerSession/TableSession.swift` (`rejection` doc comment line 26, `send` lines 106-117, `handle` line 181-183)
- Test: `Tests/PokerSessionTests/SessionTests.swift` (after `rejectionIsShownUntilTheNextState`, line 40)

**Interfaces:**

- Consumes: `TableClient.lastState` (`public private(set) var lastState: GameState?`, `Sources/PokerNet/TableClient.swift:34`), `GameState.version: Int`.
- Produces: new `private var rejectedAt = 0` in `TableSession`. Public API unchanged; only the doc comment of `rejection` changes.

Why it works: the host broadcasts every state before its ack (`Sources/PokerNet/TableHost.swift:190`), and a rejection changes nothing. So when a rejected ack arrives, `client.lastState` is the host's state at the time of the rejection. A state event still queued for `handle` cannot be newer than that.

- [ ] **Step 1: Write the failing test `rejectionSurvivesStateWithSameVersion`**

```swift
@Test func rejectionSurvivesStateWithSameVersion() async throws {
    let anna = try await hostSession()
    defer { Task { await anna.leave() } }
    let ben = await guestSession(anna)
    defer { Task { await ben.leave() } }
    try await eventually { ben.state?.seats.count == 2 }
    await ben.send(.startTournament(button: ben.me!))
    #expect(ben.rejection == .notHost)
    // The rejoin broadcasts the same state version again.
    await anna.tableHost!.disconnectAll()
    try await eventually { ben.connection == .reconnecting }
    try await eventually { ben.connection == .connected }
    // The state follows the welcome on the same stream; give it time to be handled.
    try await Task.sleep(for: .milliseconds(200))
    #expect(ben.rejection == .notHost)
}
```

The sleep cannot make the fixed code fail: it only gives the old code time to clear the banner.

- [ ] **Step 2: Run it and see it fail**

Run: `swift test --filter rejectionSurvivesStateWithSameVersion`
Expected: FAIL on the last `#expect` (`ben.rejection` is `nil`).

- [ ] **Step 3: Implement**

- In `send`, on `.rejected(reason)`: set `rejectedAt = await client.lastState?.version ?? 0`, then set `rejection = reason`. Read the version first, so no state can be handled between the two assignments.
- In `handle(.state(new))`: `if new.version > rejectedAt { rejection = nil }`. Leave `state = new` as is.
- Doc comment of `rejection`: `/// Reason of the last rejected command; cleared by \`send\` and by the next state newer than the one it was rejected on.`
- Add a `ponytail:` comment next to the `rejectedAt` read: a state that arrives between the ack and this read is counted as old, so the banner outlives one real change; upgrade path: return the version from `TableClient.send` together with the `AckResult`.

- [ ] **Step 4: Run the session tests**

Run: `swift test --filter PokerSessionTests`
Expected: all PASS, including `rejectionIsShownUntilTheNextState` and the new test.

- [ ] **Step 5: Commit**

`fix(session): keep a rejection until a newer state arrives` with `Refs #23`.

### Task 2: Disable lobby edits and the host menu while sending (#23)

**Files:**

- Modify: `App/Sources/LobbyView.swift:36` (host `ForEach` row)
- Modify: `App/Sources/TableScreen.swift:50-51` (`HostMenu` inside the toolbar `Menu`)

**Interfaces:**

- Consumes: `TableSession.isSending: Bool`.
- Produces: nothing new.

- [ ] **Step 1: Lobby rows**

Row becomes `Text(seat.name).deleteDisabled(seat.id == state.hostID || session.isSending).moveDisabled(session.isSending)`. Keep the `onDelete` loop as is; it awaits each `send`, so a multi-row delete is not dropped.

- [ ] **Step 2: Host menu**

Apply `.disabled(session.isSending)` to `HostMenu(…)` in `TableScreen`, not inside `HostMenu`. "End table" / "Leave table" stays enabled: `leave()` does not go through `send`.

- [ ] **Step 3: Build the app**

Run the app build commands from `AGENTS.md`.
Expected: `** BUILD SUCCEEDED **` or no output with `-quiet`, exit 0.

- [ ] **Step 4: Commit**

`fix(app): disable lobby edits and host menu while a command is in flight` with `Closes #23`.

### Task 3: Identify a discovered table by its name (#26)

**Files:**

- Modify: `App/Sources/StartView.swift:131` (retroactive `Identifiable`), `App/Sources/StartView.swift:79` (endpoint in `TableSession.join`)

**Interfaces:**

- Consumes: `NearbyTables.tables: [DiscoveredTable]`, `DiscoveredTable.name: String`, `DiscoveredTable.endpoint: NWEndpoint`.
- Produces: `extension DiscoveredTable: @retroactive Identifiable { public var id: String { name } }`.

- [ ] **Step 1: Change the identity**

`id` returns `name` instead of `Self`. A new endpoint for the same name no longer replaces the sheet, so the typed code stays.

- [ ] **Step 2: Join the endpoint that is listed now**

The sheet's `table` keeps the endpoint from the moment of the tap. In the join closure use `nearby.tables.first { $0.name == table.name }?.endpoint ?? table.endpoint`.

- [ ] **Step 3: Build the app**

Same command and expectation as Task 2 Step 3.

- [ ] **Step 4: Commit**

`fix(app): keep the join sheet when a table's endpoint changes` with `Closes #26`.

### Task 4: Verify, open the PR, close #44

- [ ] **Step 1: Run the four CI commands from `AGENTS.md`**

Expected: lint passes, `swift test` passes, docbuild has no warnings, app build exit 0.

- [ ] **Step 2: Open the PR**

Title `fix(app): guard sends in flight and keep the join sheet`. The body links this plan, lists `Closes #23`, `Closes #26`, and the manual checklist from Step 4. Do not enable auto-merge: Tasks 2 and 3 are UI-only and wait for the user's check.

- [ ] **Step 3: Close #44**

```sh
gh issue close 44 --comment "Bullets 1 and 2 are fixed in a5dcdd6 (host dialogs reset on a state.version change, showdown picks reset on a new hand). Bullet 3 (turn haptic after coalesced states) is accepted as is: it is not a regression and needs a reconnect that skips exactly to a new turn on the same street."
```

- [ ] **Step 4: Manual check (user, real iPhone as host, simulator as guest)**

1. Lobby: drag a seat to a new position; swipe-delete a guest; select two guests in edit mode and delete both. Each change shows on both devices.
2. Table: open the "Table" menu as host; pause and resume the clock; fold for the guest; undo. Each works as before.
3. Start screen: open the join sheet for the host's table, type part of the code, wait 30 s, finish the code and join. The sheet stays open and the join succeeds.
