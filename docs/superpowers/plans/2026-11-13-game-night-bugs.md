# Game-Night Bugs Implementation Plan

**Goal:** Fix #50, #41, #33, #34, #20 in one PR off `main` (branch `fix/game-night-bugs`).

**Spec:** [2026-11-13-game-night-bugs.md](../specs/2026-11-13-game-night-bugs.md)

**Tech stack:** Swift 6, Swift Testing, Network.framework, SwiftUI (iOS 17).

## Constraints

- No new dependencies. Test suites keep `.timeLimit(.minutes(1))` and use the existing `eventually` / `EventRecorder` helpers.
- TDD in `PokerNet` and `PokerSession`: write the failing test, watch it fail, implement, watch it pass.
- The app changes (alert text, banner, leave flow) are checked by hand in the simulator.
- `docs/PROTOCOL.md` is updated with the wire changes (`tableClosed`, mid-game `removed`).
- Before the PR: `swift test` and the app build from AGENTS.md must both pass.
- New small findings become `deferred` issues. Other deferred issues are not touched.

## Task 1: #41 host seat guard (PokerSession)

- [ ] Test `snapshotWithoutHostSeatThrows` in `SessionTests`: a new-table snapshot with its seats emptied → `TableSession.host` throws `CocoaError`.
- [ ] Move the seat lookup into the guard in `TableSession.host`.

## Task 2: #34 removed mid-game (PokerNet)

- [ ] Test `removedMidGameIsDisconnectedAndForgotten` in `HostCommandTests`: start the tournament (3 players so it continues), remove Ben → Ben gets `error removed`, the connection closes, and his token is gone.
- [ ] `TableHost.handle`: after a successful `.removePlayer(p)`, also forget `p`'s token and reject `p`'s connections.

## Task 3: #33 tableClosed (PokerCore, PokerNet, PokerSession)

- [ ] Client test `hostEndingTheTableFailsWithoutRetry`: `host.end()` → `.failed(.tableClosed)`, no reconnect.
- [ ] Session test `guestIsToldWhenTheHostEndsTheTable`: `anna.leave()` → `ben.connection == .failed(.tableClosed)`.
- [ ] Add `WireErrorCode.tableClosed`, `ClientFailure.tableClosed`, `TableHost.end()`, and `leave()` uses `end()`.

## Task 4: #50 wrong code over Bonjour (PokerNet)

- [ ] Discovery test `wrongCodeViaBonjourFailsWithoutRetry`: a client on the discovered `.service` endpoint with a wrong code → `.failed(.wrongCode)`.
- [ ] Channel test `closedBeforeReadyFailsHandshake`: a plain TCP listener that closes every connection at once → channel ends with `handshakeFailed`.
- [ ] `MessageChannel`: resolve `.service` endpoints over plain TCP, then TLS to the resolved address. Classify errors before TLS `.ready` as `handshakeFailed`, except unreachable errors.
- [ ] The existing reconnect tests (`clientReconnectsAfterHostRestart`, `resumeOnNewPortViaBonjour`, …) still pass.

## Task 5: #20 surfaced errors (PokerSession, app)

- [ ] `SaveFileTests`: `delete()` of a missing file does not throw; `delete()` that cannot remove the file throws.
- [ ] Session tests: a failing host save sets `.saveFailed`; a failed `send` sets `.sendFailed`; a failing delete in `leave()` returns `false` and sets `.deleteFailed`.
- [ ] Implement `SessionProblem`, `problem`, `SaveFile.delete() throws`, and `leave() -> Bool`.
- [ ] App: banner text, `Messages.swift`, `TableScreen` leave flow, and the `StartView` discard alert.

## Task 6: docs and checks

- [ ] `docs/PROTOCOL.md`: `tableClosed` row, `removed` also mid-game, the client list of final codes, and a note on resolving Bonjour first.
- [ ] `swift test`, app build, manual simulator check (wrong code, end table, remove mid-game).
- [ ] PR linking spec and plan, `Closes #50 #41 #33 #34 #20`.
