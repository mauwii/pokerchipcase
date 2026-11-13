# PokerCore Implementation Plan (plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Status:** executed in PR #1. The final review added fixes beyond this plan: chip conservation (lone matched player is not asked to act, dead chips go to the top pot), `GameState.version` / `stateVersion` against stale double taps, and the host as a fallback for `resolveShowdown`.

**Goal:** Swift package `PokerChipCase` with the target `PokerCore`: complete, tested tournament logic for No-Limit Texas Hold'em plus the wire protocol types, built in CI.

**Architecture:** `Game` is a `Codable` value type holding the current `GameState` and the history. Every change goes through `Game.apply(_:by:at:)`: the command is authorized, validated and applied atomically, or it throws a `Rejection` and the state stays unchanged. Time comes in as a parameter and there is no randomness in the core, so all tests are deterministic.

**Tech Stack:** Swift 6 (language mode 6), Swift Package Manager, Swift Testing (`import Testing`), Foundation. No external dependencies.

**Spec:** `docs/superpowers/specs/2026-11-11-pokerchipcase-design.md`

**Follow-up plans:** plan 2 `PokerNet` (host/client, TLS-PSK, Bonjour), plan 3 app (SwiftUI, XcodeGen, app build in CI).

## Global Constraints

- Package platforms: `.iOS(.v17)`, `.macOS(.v14)`; `swift-tools-version: 6.0`
- No external dependencies
- All public types are `Sendable`, `Codable`, `Equatable`
- Amounts are integer chips (`Int`), no denominations
- At most 10 players per table, at least 2 to start
- License MIT
- No randomness and no system clock in `PokerCore`

## Review Focus

1. **Short stack in the big blind:** a player with less than the big blind is all-in after posting; the others still have to call the full big blind → test `shortStackedBigBlindIsAllIn` (Task 2).
2. **Double tap / acting out of turn:** the same action sent twice → the second is rejected with `notYourTurn`, state unchanged → `outOfTurnRejectedAndStateUnchanged`, `doubleTapRejected` (Task 3).
3. **Everyone all-in before the river:** no betting round possible → immediate showdown, uncalled excess returned → `onlyOnePlayerLeftToActRunsOut` (Task 5).
4. **Two players eliminated in the same hand:** whoever had more chips at hand start places better → `twoEliminatedSameHandRankedByStartingStack` (Task 7).
5. **Mistake at showdown:** undo after the payout restores all stacks exactly → `undoAfterShowdownRestoresChips` (Task 9).

---

## File Structure

```text
Package.swift
LICENSE
.gitignore
.github/workflows/ci.yml
Sources/PokerCore/
  Types.swift       Chips, PlayerID, BlindLevel, TournamentConfig, Seat, Phase, Street, Pot, BlindClock, GameState
  Command.swift     Command, Action, Rejection
  Game.swift        Game, apply dispatch, authorization, lobby commands, history/undo
  Hand.swift        hand start, blinds, betting rounds, street changes, showdown, hand end  (extension GameState)
  Pots.swift        computePots, payout with odd chip
  Clock.swift       blind level clock
  Wire.swift        protocol messages, encoder/decoder
Tests/PokerCoreTests/
  Helpers.swift
  LobbyTests.swift  HandStartTests.swift  BettingTests.swift  AllInTests.swift
  PotTests.swift    ShowdownTests.swift   HandEndTests.swift  ClockTests.swift
  UndoTests.swift   WireTests.swift
docs/PROTOCOL.md
```

---

### Task 1: Package scaffold, types, lobby, CI

**Files:**

- Create: `Package.swift`, `LICENSE`, `.gitignore`, `.github/workflows/ci.yml`, `Sources/PokerCore/Types.swift`, `Sources/PokerCore/Command.swift`, `Sources/PokerCore/Game.swift`
- Test: `Tests/PokerCoreTests/LobbyTests.swift`

**Interfaces:**

- Produces:

  ```swift
  public typealias Chips = Int
  public typealias PlayerID = String

  public struct BlindLevel { public var smallBlind: Chips; public var bigBlind: Chips; public var duration: TimeInterval }
  public struct TournamentConfig {
      public var startingStack: Chips; public var levels: [BlindLevel]
      public static let relaxed: TournamentConfig   // "Relaxed – 20 min"
      public static let quick: TournamentConfig     // "Quick – 10 min"
      public static let presets: [(name: String, config: TournamentConfig)]
  }
  public struct Seat {
      public var id: PlayerID; public var name: String; public var stack: Chips
      public var roundBet: Chips; public var handBet: Chips; public var stackAtHandStart: Chips
      public var folded: Bool; public var allIn: Bool; public var acted: Bool; public var mayRaise: Bool
      public var eliminatedRank: Int?
  }
  public enum Phase: String { case lobby, betting, showdown, handComplete, finished }
  public enum Street: String { case preflop, flop, turn, river }
  public struct Pot { public var amount: Chips; public var eligible: [PlayerID] }
  public struct BlindClock { public var levelIndex: Int; public var levelEndsAt: Date?; public var pausedRemaining: TimeInterval? }
  public struct GameState {
      public var config: TournamentConfig; public var hostID: PlayerID
      public var seats: [Seat]; public var phase: Phase; public var street: Street
      public var buttonIndex: Int?; public var handNumber: Int
      public var currentBet: Chips; public var lastRaiseSize: Chips
      public var toActIndex: Int?; public var pots: [Pot]; public var clock: BlindClock
      public func seat(_ id: PlayerID) -> Seat?
  }

  public enum Action { case fold, check, call, raiseTo(amount: Chips), allIn }
  public enum Command {
      case join(player: PlayerID, name: String)
      case removePlayer(player: PlayerID)
      case arrangeSeats(order: [PlayerID])
      case startTournament(button: PlayerID)
      case act(player: PlayerID, action: Action)
      case resolveShowdown(winners: [[PlayerID]])
      case startNextHand
      case pauseClock
      case resumeClock
      case undo
  }
  public enum Rejection: String, Error {
      case notHost, notDealer, notYourTurn, invalidPhase, illegalAction, invalidAmount,
           unknownPlayer, duplicatePlayer, tableFull, tooFewPlayers, invalidShowdown, nothingToUndo
  }

  public struct Game {
      public internal(set) var state: GameState
      public internal(set) var history: [GameState]
      public init(hostID: PlayerID, hostName: String, config: TournamentConfig)
      public mutating func apply(_ command: Command, by actor: PlayerID, at now: Date) throws(Rejection)
  }
  ```

  All types: `Codable, Equatable, Sendable`.

- [ ] **Step 1: Create the package**

`Package.swift`: package `PokerChipCase`, library product `PokerCore`, target `PokerCore`, test target `PokerCoreTests`, platforms per Global Constraints. `.gitignore`: `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcodeproj`, `.DS_Store`. `LICENSE`: MIT, year 2026, holder = `git config user.name`.

- [ ] **Step 2: Write failing tests** (`LobbyTests.swift`, `@testable import PokerCore`, `let t0 = Date(timeIntervalSince1970: 0)`)

```swift
@Test func hostIsSeatedOnCreation() {
    let g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    #expect(g.state.phase == .lobby)
    #expect(g.state.seats.map(\.id) == ["A"])
    #expect(g.state.seat("A")?.stack == 1000)
}
@Test func hostAddsPlayers() throws {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    try g.apply(.join(player: "B", name: "Ben"), by: "A", at: t0)
    #expect(g.state.seats.map(\.id) == ["A", "B"])
}
@Test func onlyHostMayAddPlayers()       // join by "B" → .notHost
@Test func duplicatePlayerRejected()     // join "A" again → .duplicatePlayer
@Test func tableFullAtTen()              // 10 seats, 11th join → .tableFull
@Test func arrangeSeatsReorders()        // order ["B","A"] → seats ["B","A"]; order with unknown/missing ID → .unknownPlayer
@Test func removePlayerInLobby()         // remove "B" → seats ["A"]; remove "A" (host) → .illegalAction
@Test func presetsStartAtTenTwenty() {
    #expect(TournamentConfig.relaxed.levels.first == BlindLevel(smallBlind: 10, bigBlind: 20, duration: 1200))
    #expect(TournamentConfig.quick.levels.first?.duration == 600)
    #expect(TournamentConfig.presets.map(\.name) == ["Relaxed – 20 min", "Quick – 10 min"])
}
```

- [ ] **Step 3: Run** `swift test` → Expected: compile error (types missing)

- [ ] **Step 4: Implement**

Types and enums as above. Presets: `startingStack` 1000, SB/BB levels `10/20, 15/30, 25/50, 50/100, 75/150, 100/200, 150/300, 200/400, 300/600, 500/1000`; `relaxed` 1200 s each, `quick` 600 s each. `join` sets `stack = config.startingStack`. `apply` works on a copy and assigns only on success; before every successful command except `.undo` the old `state` is appended to `history` (the undo logic itself comes in Task 9 – appending is enough here). Lobby commands only in `.lobby`, otherwise `.invalidPhase` (exception `removePlayer`, see Task 7). Commands not implemented yet throw `.invalidPhase` for now.

- [ ] **Step 5: Run** `swift test` → Expected: all tests PASS

- [ ] **Step 6: CI**

`.github/workflows/ci.yml`: triggers `push` and `pull_request`, job on `macos-latest`, steps `actions/checkout@v4`, `swift test`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift LICENSE .gitignore .github Sources Tests
git commit -m "feat(core): package scaffold, types, lobby commands, CI"
```

---

### Task 2: Tournament start and hand start

**Files:**

- Create: `Sources/PokerCore/Hand.swift`, `Tests/PokerCoreTests/Helpers.swift`
- Modify: `Sources/PokerCore/Game.swift` (dispatch `startTournament`)
- Test: `Tests/PokerCoreTests/HandStartTests.swift`

**Interfaces:**

- Consumes: Task 1
- Produces:
  - `extension GameState { mutating func startHand() }` – resets hand fields, posts blinds, sets `toActIndex`
  - `public var dealerID: PlayerID?` (player at `buttonIndex`)
  - `public var currentLevel: BlindLevel`
  - `public var potTotal: Chips` (sum of all `handBet`)
  - `public var minRaiseTo: Chips { currentBet + lastRaiseSize }`
  - Test helpers in `Helpers.swift`:

    ```swift
    let t0 = Date(timeIntervalSince1970: 0)
    let tenTwenty = [BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600)]
    extension Game {
        /// Host = first player. Stacks are set in the lobby, then startTournament(button:) at t0.
        static func started(_ stacks: KeyValuePairs<PlayerID, Chips> = ["A": 1000, "B": 1000, "C": 1000],
                            levels: [BlindLevel] = tenTwenty, button: PlayerID = "A") throws -> Game
        /// Applies act(player: toAct, action:).
        mutating func act(_ action: Action, at now: Date = t0) throws(Rejection)
        var toAct: PlayerID? { get }
    }
    ```

- [ ] **Step 1: Failing tests**

```swift
@Test func threeHandedBlindsAndFirstToAct() throws {
    let g = try Game.started()
    #expect(g.state.phase == .betting && g.state.street == .preflop)
    #expect(g.state.seat("B")?.roundBet == 10)
    #expect(g.state.seat("C")?.roundBet == 20)
    #expect(g.toAct == "A")
    #expect(g.state.currentBet == 20 && g.state.minRaiseTo == 40 && g.state.potTotal == 30)
    #expect(g.state.dealerID == "A" && g.state.handNumber == 1)
}
@Test func headsUpButtonPostsSmallBlind() throws {
    let g = try Game.started(["A": 1000, "B": 1000])
    #expect(g.state.seat("A")?.roundBet == 10 && g.state.seat("B")?.roundBet == 20)
    #expect(g.toAct == "A")
}
@Test func shortStackedBigBlindIsAllIn() throws {
    let g = try Game.started(["A": 1000, "B": 1000, "C": 15])
    #expect(g.state.seat("C")?.roundBet == 15 && g.state.seat("C")?.allIn == true)
    #expect(g.state.currentBet == 20)
}
@Test func startRequiresTwoPlayers()     // host only → .tooFewPlayers
@Test func startRequiresHost()           // startTournament by "B" → .notHost
@Test func startWithUnknownButton()      // button "Z" → .unknownPlayer
@Test func clockStartsAtTournamentStart() throws {
    let g = try Game.started()
    #expect(g.state.clock.levelIndex == 0 && g.state.clock.levelEndsAt == t0 + 600)
}
```

- [ ] **Step 2: Run** `swift test --filter HandStartTests` → Expected: FAIL

- [ ] **Step 3: Implement**

Position rules: with ≥3 active players the SB is the next non-eliminated seat after the button, the BB the one after that, and the next one after the BB acts first. Heads-up: button = SB and acts first preflop. Posting a blind = `min(blind, stack)`; stack 0 → `allIn = true`. `currentBet = currentLevel.bigBlind` (nominal, even with a short BB), `lastRaiseSize = bigBlind`. All seats: `acted = false`, `mayRaise = true`, `folded = false`, `stackAtHandStart = stack` (before posting). `toActIndex` skips all-in seats. `startTournament`: host only, `.lobby`, ≥2 seats, button must exist; sets `clock.levelEndsAt = now + levels[0].duration`, `handNumber = 1`, calls `startHand()`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): tournament start, blinds, first to act"` (`git add` new files first)

---

### Task 3: Betting rounds

**Files:**

- Modify: `Sources/PokerCore/Hand.swift`, `Sources/PokerCore/Game.swift` (dispatch `act`)
- Test: `Tests/PokerCoreTests/BettingTests.swift`

**Interfaces:**

- Consumes: Task 2 (`startHand`, helpers)
- Produces:

  ```swift
  public struct LegalActions: Equatable, Sendable {
      public var canCheck: Bool; public var callAmount: Chips   // additional chips to call, 0 if check is possible
      public var minRaiseTo: Chips?; public var maxRaiseTo: Chips?   // nil = raising not allowed
  }
  extension GameState { public func legalActions(for player: PlayerID) -> LegalActions? }  // nil if not their turn
  extension GameState { mutating func perform(_ action: Action, by seat: Int) throws(Rejection) }
  ```

- [ ] **Step 1: Failing tests** (default: A, B, C with 1000 each, button A, SB B, BB C)

```swift
@Test func legalActionsAtStart() throws {
    let g = try Game.started()
    #expect(g.state.legalActions(for: "A") == LegalActions(canCheck: false, callAmount: 20, minRaiseTo: 40, maxRaiseTo: 1000))
    #expect(g.state.legalActions(for: "B") == nil)
}
@Test func bigBlindHasOptionPreflop() throws {
    var g = try Game.started(); try g.act(.call); try g.act(.call)
    #expect(g.state.street == .preflop && g.toAct == "C")
    #expect(g.state.legalActions(for: "C")?.canCheck == true)
}
@Test func callCheckAdvancesToFlop() throws {
    var g = try Game.started(); try g.act(.call); try g.act(.call); try g.act(.check)
    #expect(g.state.street == .flop && g.state.currentBet == 0 && g.toAct == "B" && g.state.potTotal == 60)
    #expect(g.state.seats.allSatisfy { $0.roundBet == 0 })
}
@Test func minRaiseEnforced() throws {
    var g = try Game.started()
    #expect(throws: Rejection.invalidAmount) { try g.act(.raiseTo(amount: 30)) }
    try g.act(.raiseTo(amount: 40))
    #expect(g.state.currentBet == 40 && g.state.minRaiseTo == 60)
}
@Test func reRaiseSizeTracksLastRaise() throws {
    var g = try Game.started(); try g.act(.raiseTo(amount: 100))
    #expect(g.state.minRaiseTo == 180)
}
@Test func raiseAboveStackRejected()          // A raiseTo 1001 → .invalidAmount
@Test func checkNotAllowedFacingBet()         // A check → .illegalAction
@Test func foldToOneAwardsPot() throws {
    var g = try Game.started(); try g.act(.fold); try g.act(.fold)
    #expect(g.state.phase == .handComplete)
    #expect(g.state.seat("C")?.stack == 1010 && g.state.seat("B")?.stack == 990)
}
@Test func outOfTurnRejectedAndStateUnchanged() throws {
    var g = try Game.started(); let before = g
    #expect(throws: Rejection.notYourTurn) { try g.apply(.act(player: "B", action: .call), by: "B", at: t0) }
    #expect(g == before)
}
@Test func doubleTapRejected() throws {
    var g = try Game.started(); try g.apply(.act(player: "A", action: .call), by: "A", at: t0)
    #expect(throws: Rejection.notYourTurn) { try g.apply(.act(player: "A", action: .call), by: "A", at: t0) }
}
@Test func hostMayFoldOrCheckForOthersOnly() throws {
    var g = try Game.started(); try g.act(.call)          // A calls, B to act
    #expect(throws: Rejection.illegalAction) { try g.apply(.act(player: "B", action: .call), by: "A", at: t0) }
    try g.apply(.act(player: "B", action: .fold), by: "A", at: t0)
    #expect(g.state.seat("B")?.folded == true)
}
@Test func nonHostMayNotActForOthers()        // after A calls: act(player "B") by "C" → .notYourTurn
@Test func riverCompletesToShowdown() throws {
    var g = try Game.started(); try g.act(.call); try g.act(.call); try g.act(.check)
    for _ in 0..<9 { try g.act(.check) }          // flop, turn, river
    #expect(g.state.phase == .showdown && g.state.street == .river)
    #expect(g.state.pots == [Pot(amount: 60, eligible: ["A", "B", "C"])])
}
@Test func actOutsideBettingRejected()        // after foldToOne: act → .invalidPhase
```

- [ ] **Step 2: Run** `swift test --filter BettingTests` → Expected: FAIL

- [ ] **Step 3: Implement**

Authorization in `Game.apply`, in this order: `phase != .betting` → `.invalidPhase`; `player` is not at `toActIndex` → `.notYourTurn`; `actor != player` and `actor != hostID` → `.notYourTurn`; `actor == hostID != player` with an action other than fold/check → `.illegalAction`. Rules:

- `check`: only if `roundBet == currentBet`, otherwise `.illegalAction`
- `call`: only if `currentBet > roundBet`; pays `min(diff, stack)`, stack 0 → all-in
- `raiseTo(x)`: only if `mayRaise`, otherwise `.illegalAction`; `minRaiseTo ≤ x ≤ roundBet + stack`, otherwise `.invalidAmount`; `x == roundBet + stack` → all-in
- full raise: `lastRaiseSize = x - currentBet`, `currentBet = x`, all other active seats `acted = false`, `mayRaise = true`
- `fold`: `folded = true`; if only one non-folded seat is left → it gets `potTotal`, `phase = .handComplete` (hand end logic in Task 7)
- Next to act: next seat that is not folded, not all-in, not eliminated and (`!acted` or `roundBet < currentBet`). If there is none, the round is over.
- Round end: river → showdown; otherwise next street with `currentBet = 0`, `lastRaiseSize = bigBlind`, `roundBet = 0`, `acted = false`, `mayRaise = true`; the first active seat after the button acts first.
- Entering the showdown: for now a single pot of `potTotal` with all non-folded players; Task 4 replaces this with `computePots`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): betting rounds, min-raise, fold to one"`

---

### Task 4: Pot calculation

**Files:**

- Create: `Sources/PokerCore/Pots.swift`
- Modify: `Sources/PokerCore/Hand.swift` (entering the showdown uses `computePots`)
- Test: `Tests/PokerCoreTests/PotTests.swift`

**Interfaces:**

- Produces: `func computePots(_ seats: [Seat]) -> [Pot]` (internal) – main pot first, `eligible` in seat order

- [ ] **Step 1: Failing tests** (helper `func seat(_ id: PlayerID, bet: Chips, allIn: Bool = false, folded: Bool = false) -> Seat` in the test file)

```swift
@Test func singlePot()            // A100 B100 C100 → [Pot(300, [A,B,C])]
@Test func sidePotFromShortAllIn() // A100 allIn, B300, C300 → [Pot(300,[A,B,C]), Pot(400,[B,C])]
@Test func foldedChipsStayInPots() // A50 folded, B100 allIn, C300 → [Pot(250,[B,C]), Pot(200,[C])]
@Test func twoAllInsSameLevel()    // A100 allIn, B100 allIn, C300, D300 → [Pot(400,[A,B,C,D]), Pot(400,[C,D])]
@Test func foldedBetsCreateNoLevel() // A50 folded, B100 folded, C300, D300 → [Pot(750,[C,D])]
```

- [ ] **Step 2: Run** `swift test --filter PotTests` → Expected: FAIL

- [ ] **Step 3: Implement**

```text
levels = sorted-unique(handBet of all non-folded all-in seats) ∪ {max handBet of the non-folded}
prev = 0
for level in levels:
    amount   = Σ over all seats (min(handBet, level) − min(handBet, prev))
    eligible = non-folded seats with handBet ≥ level
    prev = level
merge consecutive pots with the same eligible; drop pots with amount 0
```

- [ ] **Step 4: Run** `swift test` → Expected: PASS (including the Task 3 tests with the real calculation)

- [ ] **Step 5: Commit** `git commit -am "feat(core): side pot calculation"`

---

### Task 5: All-in and running out to the showdown

**Files:**

- Modify: `Sources/PokerCore/Hand.swift`
- Test: `Tests/PokerCoreTests/AllInTests.swift`

**Interfaces:**

- Consumes: Task 3, Task 4 (`computePots`)
- Produces: complete `allIn` action; behavior "no betting round possible → showdown"

- [ ] **Step 1: Failing tests**

```swift
@Test func incompleteAllInDoesNotReopenRaising() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 150])
    try g.act(.raiseTo(amount: 100)); try g.act(.call)        // A raises, B calls
    try g.act(.allIn)                                          // C: 150 total, raise by 50 < 80 → incomplete
    #expect(g.state.currentBet == 150 && g.toAct == "A")
    #expect(g.state.legalActions(for: "A")?.minRaiseTo == nil)
    #expect(throws: Rejection.illegalAction) { try g.act(.raiseTo(amount: 300)) }
    try g.act(.call)
}
@Test func fullAllInReopensRaising() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 300])
    try g.act(.raiseTo(amount: 100)); try g.act(.call); try g.act(.allIn)   // C: 300, raise by 200 ≥ 80
    #expect(g.state.minRaiseTo == 500)
    #expect(g.state.legalActions(for: "A")?.minRaiseTo == 500)
}
@Test func allInPreflopRunsOutToShowdown() throws {
    var g = try Game.started(); try g.act(.allIn); try g.act(.call); try g.act(.call)
    #expect(g.state.phase == .showdown && g.state.street == .preflop)
    #expect(g.state.pots == [Pot(amount: 3000, eligible: ["A", "B", "C"])])
}
@Test func onlyOnePlayerLeftToActRunsOut() throws {
    var g = try Game.started(["A": 1000, "B": 200, "C": 1000])
    try g.act(.allIn); try g.act(.call); try g.act(.fold)      // B calls all-in with 200, C folds
    #expect(g.state.phase == .showdown)
    #expect(g.state.seat("A")?.stack == 800)                    // uncalled excess returned
    #expect(g.state.pots == [Pot(amount: 420, eligible: ["A", "B"])])
}
@Test func allInWithMayRaiseFalseThatWouldRaiseRejected()   // incompleteAllIn scenario with A's stack > currentBet: A allIn → .illegalAction
```

- [ ] **Step 2: Run** `swift test --filter AllInTests` → Expected: FAIL

- [ ] **Step 3: Implement**

`allIn` sets `x = roundBet + stack`. If `x ≤ currentBet` → like a call. If `x > currentBet` → needs `mayRaise`, otherwise `.illegalAction`; with `x - currentBet ≥ lastRaiseSize` a full raise (as in Task 3), otherwise incomplete: `currentBet = x`, `lastRaiseSize` unchanged, all other active seats `acted = false`; whoever already had `acted == true` gets `mayRaise = false`. `legalActions.minRaiseTo/maxRaiseTo = nil` when `!mayRaise`.
After every action and every street change: if at most one non-folded, non-all-in seat can act and it has `roundBet ≥ currentBet` → straight to the showdown (`street` stays the last one reached, so the UI can show "deal the remaining cards").
On entering the showdown: pots with exactly one eligible player (uncalled bets) go straight back to that player; `pots` only contains contested pots.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): all-in rules, run out to showdown"`

---

### Task 6: Resolving the showdown

**Files:**

- Modify: `Sources/PokerCore/Pots.swift`, `Sources/PokerCore/Hand.swift`, `Sources/PokerCore/Game.swift`
- Test: `Tests/PokerCoreTests/ShowdownTests.swift`

**Interfaces:**

- Consumes: Task 4, Task 5
- Produces: `func split(_ amount: Chips, among winners: [PlayerID], seats: [Seat], buttonIndex: Int) -> [PlayerID: Chips]` (internal); dispatch `resolveShowdown`; test helper `mutating func checkDown() throws(Rejection)` (checks/calls until `phase != .betting`) in `Helpers.swift`

- [ ] **Step 1: Failing tests**

```swift
@Test func dealerAwardsSinglePot() throws {
    var g = try Game.started(); try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.resolveShowdown(winners: [["B"]]), by: "A", at: t0)
    #expect(g.state.phase == .handComplete && g.state.seat("B")?.stack == 1040)
}
@Test func splitPotOddChipGoesLeftOfButton() throws {
    var g = try Game.started(levels: [BlindLevel(smallBlind: 5, bigBlind: 10, duration: 600)])
    try g.act(.call); try g.act(.fold); try g.checkDown()       // pot 25, A and C in the showdown
    try g.apply(.resolveShowdown(winners: [["A", "C"]]), by: "A", at: t0)
    #expect(g.state.seat("A")?.stack == 1002 && g.state.seat("C")?.stack == 1003)
}
@Test func sidePotsResolvedSeparately() throws {
    var g = try Game.started(["A": 1000, "B": 300, "C": 1000])
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    #expect(g.state.pots == [Pot(amount: 900, eligible: ["A","B","C"]), Pot(amount: 1400, eligible: ["A","C"])])
    try g.apply(.resolveShowdown(winners: [["B"], ["C"]]), by: "A", at: t0)
    #expect(g.state.seat("B")?.stack == 900 && g.state.seat("C")?.stack == 1400 && g.state.seat("A")?.stack == 0)
}
@Test func onlyDealerMayResolve()        // resolve by "B" → .notDealer (the host is only the dealer when they have the button)
@Test func showdownWinnersValidated()    // side pot scenario: [["B"],["B"]] → .invalidShowdown (B not eligible);
                                         // [["B"]] → .invalidShowdown (count); [[],["C"]] → .invalidShowdown
@Test func resolveOutsideShowdownRejected() // in .betting → .invalidPhase
```

- [ ] **Step 2: Run** `swift test --filter ShowdownTests` → Expected: FAIL

- [ ] **Step 3: Implement**

`resolveShowdown`: only in `.showdown`, `actor == dealerID`; `winners.count == pots.count`, every list non-empty, without duplicates and ⊆ the pot's `eligible`. `split`: everyone gets `amount / n`; the remainder goes chip by chip to the winners in seat order, starting with the first seat left of the button. Then `pots = []`, `phase = .handComplete`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): showdown resolution with split and odd chip"`

---

### Task 7: Hand end, elimination, next hand, removing players

**Files:**

- Modify: `Sources/PokerCore/Hand.swift`, `Sources/PokerCore/Game.swift`
- Test: `Tests/PokerCoreTests/HandEndTests.swift`

**Interfaces:**

- Consumes: Task 6
- Produces: `extension GameState { mutating func finishHand() }` (elimination, tournament end); dispatch `startNextHand`, `removePlayer` during the game; `public var ranking: [Seat]` (by `eliminatedRank`, winner first)

- [ ] **Step 1: Failing tests**

```swift
@Test func eliminatedPlayerGetsRank()      // sidePotsResolvedSeparately scenario → A.eliminatedRank == 3, phase .handComplete
@Test func twoEliminatedSameHandRankedByStartingStack() throws {
    var g = try Game.started(["A": 500, "B": 300, "C": 1000])
    try g.act(.allIn); try g.act(.allIn); try g.act(.call)
    try g.apply(.resolveShowdown(winners: g.state.pots.map { _ in ["C"] }), by: "A", at: t0)
    #expect(g.state.phase == .finished)
    #expect(g.state.ranking.map(\.id) == ["C", "A", "B"])
    #expect(g.state.seat("C")?.eliminatedRank == nil)
}
@Test func nextHandMovesButtonAndPostsBlinds() throws {
    var g = try Game.started(); try g.act(.fold); try g.act(.fold)
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.state.dealerID == "B" && g.state.handNumber == 2 && g.toAct == "B")
    #expect(g.state.seat("C")?.roundBet == 10 && g.state.seat("A")?.roundBet == 20)
}
@Test func buttonSkipsEliminated() throws {
    var g = try Game.started(["A": 1000, "B": 100, "C": 1000, "D": 1000])
    try g.act(.call); try g.act(.call); try g.act(.allIn); try g.act(.call)  // D, A call, B all-in 100, C calls
    try g.act(.call); try g.act(.call); try g.checkDown()                     // D, A call the raise
    try g.apply(.resolveShowdown(winners: [["C"]]), by: "A", at: t0)
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.state.seat("B")?.eliminatedRank == 4 && g.state.dealerID == "C")
}
@Test func startNextHandOnlyByDealerOrHost()  // after hand 1 (dealer and host = A): by "C" → .notDealer; in .betting → .invalidPhase
@Test func removePlayerMidHandFoldsAndEliminates() throws {
    var g = try Game.started()
    try g.apply(.removePlayer(player: "B"), by: "A", at: t0)
    try g.act(.fold)                                            // A folds → C wins
    #expect(g.state.phase == .handComplete && g.state.seat("B")?.eliminatedRank == 3)
}
@Test func removePlayerOnTurnAdvancesTurn()   // remove "A" is the host → .illegalAction; after A calls: remove "B" (to act) → toAct == "C"
```

- [ ] **Step 2: Run** `swift test --filter HandEndTests` → Expected: FAIL

- [ ] **Step 3: Implement**

`finishHand()` runs on every transition to `.handComplete`: seats with `stack == 0` and no rank are eliminated. With `n` active seats before the hand and `k` eliminated ones, sorted by `stackAtHandStart` descending: rank = `n − k + 1 + index` (whoever had more places better). If one seat is left → `phase = .finished`. `startNextHand`: in `.handComplete`, `actor == dealerID || actor == hostID`, otherwise `.notDealer`; the button moves to the next non-eliminated seat; `handNumber += 1`; advance the clock (Task 8 – no clock logic until then); `startHand()`. `removePlayer` during the game (host only, not the host itself): seat `folded = true`, `stack = 0`; if it was their turn, the next player moves up; then the same check as after a fold.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): elimination, ranking, next hand, remove player"`

---

### Task 8: Blind clock

**Files:**

- Create: `Sources/PokerCore/Clock.swift`
- Modify: `Sources/PokerCore/Game.swift`, `Sources/PokerCore/Hand.swift`
- Test: `Tests/PokerCoreTests/ClockTests.swift`

**Interfaces:**

- Produces:

  ```swift
  extension BlindClock {
      mutating func advance(to now: Date, levels: [BlindLevel])
      mutating func pause(at now: Date)
      mutating func resume(at now: Date)
      public func remaining(at now: Date) -> TimeInterval   // pausedRemaining, otherwise max(0, levelEndsAt − now)
  }
  ```

  Dispatch `pauseClock`, `resumeClock` (host only).

- [ ] **Step 1: Failing tests** (`twoLevels = [BlindLevel(10, 20, 600), BlindLevel(20, 40, 600)]`, hand 1 finished by fold, fold)

```swift
@Test func levelAdvancesAtNextHandAfterExpiry() // startNextHand at t0+601 → levelIndex 1, BB seat roundBet 40, levelEndsAt t0+1200
@Test func levelDoesNotChangeMidHand()          // actions at t0+700 → levelIndex 0
@Test func lastLevelStays()                     // startNextHand at t0+99_999 → levelIndex 1
@Test func pauseFreezesRemaining() throws {
    var g = try Game.started(levels: twoLevels)
    try g.apply(.pauseClock, by: "A", at: t0 + 100)
    #expect(g.state.clock.remaining(at: t0 + 5000) == 500 && g.state.clock.levelEndsAt == nil)
    try g.apply(.resumeClock, by: "A", at: t0 + 1000)
    #expect(g.state.clock.levelEndsAt == t0 + 1500)
}
@Test func noAdvanceWhilePaused()               // pause, finish the hand, startNextHand at t0+5000 → levelIndex 0
@Test func clockCommandsHostOnly()              // pauseClock by "B" → .notHost; resume without pause → .invalidPhase; pause twice → .invalidPhase
```

- [ ] **Step 2: Run** `swift test --filter ClockTests` → Expected: FAIL

- [ ] **Step 3: Implement**

`advance`: do nothing while paused; otherwise while `levelIndex < levels.count − 1` and `now ≥ levelEndsAt`: `levelIndex += 1`, `levelEndsAt += levels[levelIndex].duration`. Called in `startNextHand` before `startHand()`. `pause`: `pausedRemaining = remaining(at:)`, `levelEndsAt = nil`. `resume`: `levelEndsAt = now + pausedRemaining`, `pausedRemaining = nil`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): blind level clock with pause"`

---

### Task 9: Undo and persistability

**Files:**

- Modify: `Sources/PokerCore/Game.swift`
- Test: `Tests/PokerCoreTests/UndoTests.swift`

**Interfaces:**

- Produces: dispatch `undo` (host only, `state = history.removeLast()`); `Game` serializes losslessly with `JSONEncoder`/`JSONDecoder` (the app's persistence file comes in plan 3)

- [ ] **Step 1: Failing tests**

```swift
@Test func undoRestoresPreviousState() throws {
    var g = try Game.started(); let before = g.state
    try g.act(.raiseTo(amount: 100)); try g.apply(.undo, by: "A", at: t0)
    #expect(g.state == before)
}
@Test func undoAfterShowdownRestoresChips() throws {
    var g = try Game.started(); try g.act(.call); try g.act(.call); try g.checkDown()
    let atShowdown = g.state
    try g.apply(.resolveShowdown(winners: [["B"]]), by: "A", at: t0)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state == atShowdown)
}
@Test func undoOnlyHost()                 // by "B" → .notHost
@Test func nothingToUndoOnFreshGame()     // Game(...) directly → .nothingToUndo
@Test func rejectedCommandDoesNotGrowHistory() // history.count equal before/after a rejected action
@Test func gameRoundTripsThroughJSON() throws {
    var g = try Game.started(); try g.act(.raiseTo(amount: 100))
    let data = try Wire.encoder.encode(g)
    #expect(try Wire.decoder.decode(Game.self, from: data) == g)
}
```

(`Wire.encoder/decoder` arrive in Task 10; until then use `JSONEncoder()`/`JSONDecoder()` in this test and switch in Task 10.)

- [ ] **Step 2: Run** `swift test --filter UndoTests` → Expected: FAIL

- [ ] **Step 3: Implement** – `undo` without history → `.nothingToUndo`; `undo` itself is not written to the history.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): host undo via state history"`

---

### Task 10: Wire protocol and PROTOCOL.md

**Files:**

- Create: `Sources/PokerCore/Wire.swift`, `docs/PROTOCOL.md`
- Modify: `docs/superpowers/specs/2026-11-11-pokerchipcase-design.md` (protocol section: client → host are `hello` and `command`)
- Test: `Tests/PokerCoreTests/WireTests.swift`

**Interfaces:**

- Produces:

  ```swift
  public struct Hello: Codable, Equatable, Sendable { public var protocolVersion: Int; public var name: String; public var token: String? }
  public struct Welcome: Codable, Equatable, Sendable { public var player: PlayerID; public var token: String }
  public enum AckResult: Codable, Equatable, Sendable { case ok, rejected(reason: Rejection) }
  public struct Ack: Codable, Equatable, Sendable { public var id: UUID; public var result: AckResult }
  public enum ClientMessage: Equatable, Sendable { case hello(Hello), command(Command) }
  public enum ServerMessage: Equatable, Sendable { case welcome(Welcome), ack(Ack), state(GameState), error(String) }
  public enum WireError: Error, Equatable { case versionMismatch(Int), unknownType(String) }
  public enum Wire {
      public static let version = 1
      public static let serviceType = "_pokerchipcase._tcp"
      public static var encoder: JSONEncoder { get }   // .millisecondsSince1970, .sortedKeys
      public static var decoder: JSONDecoder { get }
      public static func encode(_ message: ClientMessage, id: UUID) throws -> Data
      public static func encode(_ message: ServerMessage, id: UUID) throws -> Data
      public static func decodeClient(_ data: Data) throws -> (id: UUID, message: ClientMessage)
      public static func decodeServer(_ data: Data) throws -> (id: UUID, message: ServerMessage)
  }
  ```

  Envelope: `{"v": 1, "type": "<case>", "id": "<UUID>", "payload": <payload>}`; `type` is the case name (`hello`, `command`, `welcome`, `ack`, `state`, `error`).

- [ ] **Step 1: Failing tests**

```swift
let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
@Test func commandGoldenJSON() throws {
    let data = try Wire.encode(.command(.act(player: "B", action: .raiseTo(amount: 60))), id: id1)
    #expect(String(decoding: data, as: UTF8.self) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"act":{"action":{"raiseTo":{"amount":60}},"player":"B"}},"type":"command","v":1}"#)
}
@Test func ackGoldenJSON()      // .ack(Ack(id: id1, result: .rejected(reason: .notYourTurn))) → exact string with "rejected":{"reason":"notYourTurn"}
@Test func clientRoundTrip()    // hello and command encode → decodeClient == original, id preserved
@Test func serverRoundTrip()    // state(Game.started().state) encode → decodeServer == original
@Test func versionMismatchRejected() // JSON with "v":2 → WireError.versionMismatch(2)
@Test func unknownTypeRejected()     // "type":"bogus" → WireError.unknownType("bogus")
```

Also switch `UndoTests.gameRoundTripsThroughJSON` to `Wire.encoder/decoder`.

- [ ] **Step 2: Run** `swift test --filter WireTests` → Expected: FAIL

- [ ] **Step 3: Implement** – manual `Codable` only for the envelope (`type`/`payload` flat); `Command`, `Action`, `GameState` etc. stay synthesized (labeled associated values produce `{"case":{"label":…}}`, cases without values `{"fold":{}}`).

- [ ] **Step 4: Write `docs/PROTOCOL.md`** – audience: someone building a compatible client (e.g. Android). Content: transport (WebSocket over TLS 1.2 PSK, cipher suite `TLS_PSK_WITH_AES_128_GCM_SHA256`, PSK = HKDF-SHA256 over the 4-digit table code with salt `pokerchipcase-v1`, Bonjour `_pokerchipcase._tcp`), envelope, every message type with one JSON example each (from the golden tests), flow `hello → welcome → state`, `command → ack + state`, authorization rules (who may send which command), date format (milliseconds since 1970), version rule.

- [ ] **Step 5: Update the spec** – protocol section: client → host are `hello` and `command` (`command` carries `Command`; authorization happens in `PokerCore`).

- [ ] **Step 6: Run** `swift test` → Expected: all tests PASS

- [ ] **Step 7: Commit**

```bash
git add Sources Tests docs
git commit -m "feat(core): wire protocol types and PROTOCOL.md"
```
