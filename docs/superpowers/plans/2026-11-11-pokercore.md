# PokerCore Implementation Plan (Plan 1 von 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swift Package `PokerChipCase` mit dem Target `PokerCore`: vollständige, getestete Turnier-Spiellogik für No-Limit Texas Hold'em plus die Wire-Protokoll-Typen, gebaut in CI.

**Architecture:** `Game` ist ein `Codable`-Werttyp mit dem aktuellen `GameState` und der Historie. Jede Änderung läuft über `Game.apply(_:by:at:)`: der Befehl wird autorisiert und validiert und dann atomar angewendet, oder er wirft eine `Rejection` und der Zustand bleibt unverändert. Zeit kommt als Parameter herein, Zufall gibt es im Kern nicht – damit sind alle Tests deterministisch.

**Tech Stack:** Swift 6 (Language Mode 6), Swift Package Manager, Swift Testing (`import Testing`), Foundation. Keine externen Abhängigkeiten.

**Spec:** `docs/superpowers/specs/2026-11-11-pokerchipcase-design.md`

**Folgepläne:** Plan 2 `PokerNet` (Host/Client, TLS-PSK, Bonjour), Plan 3 App (SwiftUI, XcodeGen, App-Build in CI).

## Global Constraints

- Plattformen im Package: `.iOS(.v17)`, `.macOS(.v14)`; `swift-tools-version: 6.0`
- Keine externen Dependencies
- Alle öffentlichen Typen sind `Sendable`, `Codable`, `Equatable`
- Beträge sind ganzzahlige Chips (`Int`), keine Stückelung
- Max. 10 Spieler pro Tisch, min. 2 zum Start
- Lizenz MIT
- Kein Zufall und keine Systemuhr in `PokerCore`

## Review Focus

1. **Short-Stack im Big Blind:** Spieler mit weniger als dem Big Blind ist nach dem Posten all-in; die anderen müssen trotzdem den vollen Big Blind callen → Test `shortStackedBigBlindIsAllIn` (Task 2).
2. **Doppeltipp / Aktion außer der Reihe:** gleiche Aktion zweimal gesendet → zweite wird mit `notYourTurn` abgelehnt, Zustand unverändert → `outOfTurnRejectedAndStateUnchanged`, `doubleTapRejected` (Task 3).
3. **Alle all-in vor dem River:** keine Setzrunde mehr möglich → sofort Showdown, ungecallter Überschuss zurück → `onlyOnePlayerLeftToActRunsOut` (Task 5).
4. **Zwei Spieler scheiden in derselben Hand aus:** wer zu Handbeginn mehr Chips hatte, platziert sich besser → `twoEliminatedSameHandRankedByStartingStack` (Task 7).
5. **Vertippt beim Showdown:** Rückgängig nach der Auszahlung stellt alle Stacks exakt wieder her → `undoAfterShowdownRestoresChips` (Task 9).

---

## Dateistruktur

```
Package.swift
LICENSE
.gitignore
.github/workflows/ci.yml
Sources/PokerCore/
  Types.swift       Chips, PlayerID, BlindLevel, TournamentConfig, Seat, Phase, Street, Pot, BlindClock, GameState
  Command.swift     Command, Action, Rejection
  Game.swift        Game, apply-Dispatch, Autorisierung, Lobby-Befehle, Historie/Undo
  Hand.swift        Hand starten, Blinds, Setzrunden, Straßenwechsel, Showdown, Handende  (extension GameState)
  Pots.swift        computePots, Verteilung mit Restchip
  Clock.swift       Blind-Level-Uhr
  Wire.swift        Protokoll-Nachrichten, Encoder/Decoder
Tests/PokerCoreTests/
  Helpers.swift
  LobbyTests.swift  HandStartTests.swift  BettingTests.swift  AllInTests.swift
  PotTests.swift    ShowdownTests.swift   HandEndTests.swift  ClockTests.swift
  UndoTests.swift   WireTests.swift
docs/PROTOCOL.md
```

---

### Task 1: Package-Gerüst, Typen, Lobby, CI

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
      public static let relaxed: TournamentConfig   // "Gemütlich – 20 Min"
      public static let quick: TournamentConfig     // "Schnell – 10 Min"
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
  Alle Typen: `Codable, Equatable, Sendable`.

- [ ] **Step 1: Package anlegen**

`Package.swift`: Package `PokerChipCase`, Library-Produkt `PokerCore`, Target `PokerCore`, Test-Target `PokerCoreTests`, Plattformen laut Global Constraints. `.gitignore`: `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcodeproj`, `.DS_Store`. `LICENSE`: MIT, Jahr 2026, Inhaber = `git config user.name`.

- [ ] **Step 2: Failing Tests schreiben** (`LobbyTests.swift`, `@testable import PokerCore`, `let t0 = Date(timeIntervalSince1970: 0)`)

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
@Test func tableFullAtTen()              // 10 Sitze, 11. join → .tableFull
@Test func arrangeSeatsReorders()        // order ["B","A"] → seats ["B","A"]; order mit fremder/fehlender ID → .unknownPlayer
@Test func removePlayerInLobby()         // remove "B" → seats ["A"]; remove "A" (Host) → .illegalAction
@Test func presetsStartAtTenTwenty() {
    #expect(TournamentConfig.relaxed.levels.first == BlindLevel(smallBlind: 10, bigBlind: 20, duration: 1200))
    #expect(TournamentConfig.quick.levels.first?.duration == 600)
    #expect(TournamentConfig.presets.map(\.name) == ["Gemütlich – 20 Min", "Schnell – 10 Min"])
}
```

- [ ] **Step 3: Run** `swift test` → Expected: Compile-Fehler (Typen fehlen)

- [ ] **Step 4: Implementieren**

Typen und Enums wie oben. Presets: `startingStack` 1000, Levels SB/BB `10/20, 15/30, 25/50, 50/100, 75/150, 100/200, 150/300, 200/400, 300/600, 500/1000`; `relaxed` je 1200 s, `quick` je 600 s. `join` setzt `stack = config.startingStack`. `apply` arbeitet auf einer Kopie und weist erst bei Erfolg zu; vor jedem erfolgreichen Befehl außer `.undo` wird der alte `state` an `history` angehängt (Undo-Logik selbst kommt in Task 9 – hier reicht das Anhängen). Lobby-Befehle nur in `.lobby`, sonst `.invalidPhase` (Ausnahme `removePlayer`, siehe Task 7). Noch nicht implementierte Befehle werfen vorerst `.invalidPhase`.

- [ ] **Step 5: Run** `swift test` → Expected: alle Tests PASS

- [ ] **Step 6: CI**

`.github/workflows/ci.yml`: Trigger `push` und `pull_request`, Job auf `macos-latest`, Steps `actions/checkout@v4`, `swift test`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift LICENSE .gitignore .github Sources Tests
git commit -m "feat(core): package scaffold, types, lobby commands, CI"
```

---

### Task 2: Turnierstart und Handbeginn

**Files:**
- Create: `Sources/PokerCore/Hand.swift`, `Tests/PokerCoreTests/Helpers.swift`
- Modify: `Sources/PokerCore/Game.swift` (Dispatch `startTournament`)
- Test: `Tests/PokerCoreTests/HandStartTests.swift`

**Interfaces:**
- Consumes: Task 1
- Produces:
  - `extension GameState { mutating func startHand() }` – setzt Hand-Felder zurück, postet Blinds, bestimmt `toActIndex`
  - `public var dealerID: PlayerID?` (Spieler auf `buttonIndex`)
  - `public var currentLevel: BlindLevel`
  - `public var potTotal: Chips` (Summe aller `handBet`)
  - `public var minRaiseTo: Chips { currentBet + lastRaiseSize }`
  - Test-Helper in `Helpers.swift`:
    ```swift
    let t0 = Date(timeIntervalSince1970: 0)
    let tenTwenty = [BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600)]
    extension Game {
        /// Host = erster Spieler. Stacks werden in der Lobby gesetzt, dann startTournament(button:) bei t0.
        static func started(_ stacks: KeyValuePairs<PlayerID, Chips> = ["A": 1000, "B": 1000, "C": 1000],
                            levels: [BlindLevel] = tenTwenty, button: PlayerID = "A") throws -> Game
        /// Wendet act(player: toAct, action:) an.
        mutating func act(_ action: Action, at now: Date = t0) throws(Rejection)
        var toAct: PlayerID? { get }
    }
    ```

- [ ] **Step 1: Failing Tests**

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
@Test func startRequiresTwoPlayers()     // nur Host → .tooFewPlayers
@Test func startRequiresHost()           // startTournament by "B" → .notHost
@Test func startWithUnknownButton()      // button "Z" → .unknownPlayer
@Test func clockStartsAtTournamentStart() throws {
    let g = try Game.started()
    #expect(g.state.clock.levelIndex == 0 && g.state.clock.levelEndsAt == t0 + 600)
}
```

- [ ] **Step 2: Run** `swift test --filter HandStartTests` → Expected: FAIL

- [ ] **Step 3: Implementieren**

Positionsregeln: Bei ≥3 aktiven Spielern ist SB der nächste nicht ausgeschiedene Sitz nach dem Button, BB der nächste danach, zuerst handelt der nächste nach dem BB. Heads-up: Button = SB und handelt preflop zuerst. Blind posten = `min(blind, stack)`; Stack 0 → `allIn = true`. `currentBet = currentLevel.bigBlind` (nominal, auch bei Short-BB), `lastRaiseSize = bigBlind`. Alle Sitze: `acted = false`, `mayRaise = true`, `folded = false`, `stackAtHandStart = stack` (vor dem Posten). `toActIndex` überspringt All-in-Sitze. `startTournament`: Host-only, `.lobby`, ≥2 Sitze, Button muss existieren; setzt `clock.levelEndsAt = now + levels[0].duration`, `handNumber = 1`, ruft `startHand()`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): tournament start, blinds, first to act"` (neue Dateien vorher `git add`)

---

### Task 3: Setzrunden

**Files:**
- Modify: `Sources/PokerCore/Hand.swift`, `Sources/PokerCore/Game.swift` (Dispatch `act`)
- Test: `Tests/PokerCoreTests/BettingTests.swift`

**Interfaces:**
- Consumes: Task 2 (`startHand`, Helpers)
- Produces:
  ```swift
  public struct LegalActions: Equatable, Sendable {
      public var canCheck: Bool; public var callAmount: Chips   // zusätzliche Chips zum Callen, 0 wenn check möglich
      public var minRaiseTo: Chips?; public var maxRaiseTo: Chips?   // nil = Raise nicht erlaubt
  }
  extension GameState { public func legalActions(for player: PlayerID) -> LegalActions? }  // nil wenn nicht dran
  extension GameState { mutating func perform(_ action: Action, by seat: Int) throws(Rejection) }
  ```

- [ ] **Step 1: Failing Tests** (Standard: A, B, C je 1000, Button A, SB B, BB C)

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
    var g = try Game.started(); try g.act(.call)          // A callt, B ist dran
    #expect(throws: Rejection.illegalAction) { try g.apply(.act(player: "B", action: .call), by: "A", at: t0) }
    try g.apply(.act(player: "B", action: .fold), by: "A", at: t0)
    #expect(g.state.seat("B")?.folded == true)
}
@Test func nonHostMayNotActForOthers()        // nach A call: act(player "B") by "C" → .notYourTurn
@Test func riverCompletesToShowdown() throws {
    var g = try Game.started(); try g.act(.call); try g.act(.call); try g.act(.check)
    for _ in 0..<9 { try g.act(.check) }          // Flop, Turn, River
    #expect(g.state.phase == .showdown && g.state.street == .river)
    #expect(g.state.pots == [Pot(amount: 60, eligible: ["A", "B", "C"])])
}
@Test func actOutsideBettingRejected()        // nach foldToOne: act → .invalidPhase
```

- [ ] **Step 2: Run** `swift test --filter BettingTests` → Expected: FAIL

- [ ] **Step 3: Implementieren**

Autorisierung in `Game.apply`, in dieser Reihenfolge: `phase != .betting` → `.invalidPhase`; `player` sitzt nicht auf `toActIndex` → `.notYourTurn`; `actor != player` und `actor != hostID` → `.notYourTurn`; `actor == hostID != player` mit Aktion außer fold/check → `.illegalAction`. Regeln:
- `check`: nur wenn `roundBet == currentBet`, sonst `.illegalAction`
- `call`: nur wenn `currentBet > roundBet`; zahlt `min(diff, stack)`, Stack 0 → all-in
- `raiseTo(x)`: nur wenn `mayRaise`, sonst `.illegalAction`; `minRaiseTo ≤ x ≤ roundBet + stack`, sonst `.invalidAmount`; `x == roundBet + stack` → all-in
- volles Raise: `lastRaiseSize = x - currentBet`, `currentBet = x`, alle anderen aktiven Sitze `acted = false`, `mayRaise = true`
- `fold`: `folded = true`; bleibt nur ein nicht gefoldeter Sitz übrig → er bekommt `potTotal`, `phase = .handComplete` (Handende-Logik Task 7)
- Nächster am Zug: nächster Sitz, der nicht gefoldet, nicht all-in, nicht ausgeschieden ist und (`!acted` oder `roundBet < currentBet`). Gibt es keinen, ist die Runde vorbei.
- Rundenende: River → Showdown; sonst nächste Straße mit `currentBet = 0`, `lastRaiseSize = bigBlind`, `roundBet = 0`, `acted = false`, `mayRaise = true`; zuerst handelt der erste aktive Sitz nach dem Button.
- Showdown-Eintritt: vorerst ein einzelner Pot aus `potTotal` mit allen nicht gefoldeten Spielern; Task 4 ersetzt das durch `computePots`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): betting rounds, min-raise, fold to one"`

---

### Task 4: Pot-Berechnung

**Files:**
- Create: `Sources/PokerCore/Pots.swift`
- Modify: `Sources/PokerCore/Hand.swift` (Showdown-Eintritt nutzt `computePots`)
- Test: `Tests/PokerCoreTests/PotTests.swift`

**Interfaces:**
- Produces: `func computePots(_ seats: [Seat]) -> [Pot]` (internal) – Reihenfolge Hauptpot zuerst, `eligible` in Sitzreihenfolge

- [ ] **Step 1: Failing Tests** (Helper `func seat(_ id: PlayerID, bet: Chips, allIn: Bool = false, folded: Bool = false) -> Seat` in der Testdatei)

```swift
@Test func singlePot()            // A100 B100 C100 → [Pot(300, [A,B,C])]
@Test func sidePotFromShortAllIn() // A100 allIn, B300, C300 → [Pot(300,[A,B,C]), Pot(400,[B,C])]
@Test func foldedChipsStayInPots() // A50 folded, B100 allIn, C300 → [Pot(250,[B,C]), Pot(200,[C])]
@Test func twoAllInsSameLevel()    // A100 allIn, B100 allIn, C300, D300 → [Pot(400,[A,B,C,D]), Pot(400,[C,D])]
@Test func foldedBetsCreateNoLevel() // A50 folded, B100 folded, C300, D300 → [Pot(750,[C,D])]
```

- [ ] **Step 2: Run** `swift test --filter PotTests` → Expected: FAIL

- [ ] **Step 3: Implementieren**

```
levels = sortiert-eindeutig(handBet aller nicht gefoldeten All-in-Sitze) ∪ {max handBet der nicht gefoldeten}
prev = 0
für level in levels:
    amount   = Σ über alle Sitze (min(handBet, level) − min(handBet, prev))
    eligible = nicht gefoldete Sitze mit handBet ≥ level
    prev = level
aufeinanderfolgende Pots mit gleichem eligible zusammenfassen; Pots mit amount 0 verwerfen
```

- [ ] **Step 4: Run** `swift test` → Expected: PASS (inkl. Task-3-Tests mit echter Berechnung)

- [ ] **Step 5: Commit** `git commit -am "feat(core): side pot calculation"`

---

### Task 5: All-in und Durchlaufen bis zum Showdown

**Files:**
- Modify: `Sources/PokerCore/Hand.swift`
- Test: `Tests/PokerCoreTests/AllInTests.swift`

**Interfaces:**
- Consumes: Task 3, Task 4 (`computePots`)
- Produces: `allIn`-Aktion vollständig; Verhalten "keine Setzrunde mehr möglich → Showdown"

- [ ] **Step 1: Failing Tests**

```swift
@Test func incompleteAllInDoesNotReopenRaising() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 150])
    try g.act(.raiseTo(amount: 100)); try g.act(.call)        // A raist, B callt
    try g.act(.allIn)                                          // C: 150 gesamt, Raise um 50 < 80 → unvollständig
    #expect(g.state.currentBet == 150 && g.toAct == "A")
    #expect(g.state.legalActions(for: "A")?.minRaiseTo == nil)
    #expect(throws: Rejection.illegalAction) { try g.act(.raiseTo(amount: 300)) }
    try g.act(.call)
}
@Test func fullAllInReopensRaising() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 300])
    try g.act(.raiseTo(amount: 100)); try g.act(.call); try g.act(.allIn)   // C: 300, Raise um 200 ≥ 80
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
    try g.act(.allIn); try g.act(.call); try g.act(.fold)      // B callt all-in mit 200, C foldet
    #expect(g.state.phase == .showdown)
    #expect(g.state.seat("A")?.stack == 800)                    // ungecallter Überschuss zurück
    #expect(g.state.pots == [Pot(amount: 420, eligible: ["A", "B"])])
}
@Test func allInWithMayRaiseFalseThatWouldRaiseRejected()   // in incompleteAllIn-Szenario mit A Stack > currentBet: A allIn → .illegalAction
```

- [ ] **Step 2: Run** `swift test --filter AllInTests` → Expected: FAIL

- [ ] **Step 3: Implementieren**

`allIn` setzt `x = roundBet + stack`. Ist `x ≤ currentBet` → wie Call. Ist `x > currentBet` → braucht `mayRaise`, sonst `.illegalAction`; mit `x - currentBet ≥ lastRaiseSize` volles Raise (wie Task 3), sonst unvollständig: `currentBet = x`, `lastRaiseSize` unverändert, alle anderen aktiven Sitze `acted = false`; wer vorher schon `acted == true` war, bekommt `mayRaise = false`. `legalActions.minRaiseTo/maxRaiseTo = nil`, wenn `!mayRaise`.
Nach jeder Aktion und jedem Straßenwechsel: Können höchstens ein nicht gefoldeter, nicht all-in Sitz handeln und hat dieser `roundBet ≥ currentBet` → direkt Showdown (`street` bleibt die zuletzt erreichte, damit die UI "restliche Karten aufdecken" anzeigen kann).
Beim Showdown-Eintritt: Pots mit genau einem berechtigten Spieler (ungecallte Einsätze) sofort an diesen zurück, `pots` enthält nur umkämpfte Pots.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): all-in rules, run out to showdown"`

---

### Task 6: Showdown auflösen

**Files:**
- Modify: `Sources/PokerCore/Pots.swift`, `Sources/PokerCore/Hand.swift`, `Sources/PokerCore/Game.swift`
- Test: `Tests/PokerCoreTests/ShowdownTests.swift`

**Interfaces:**
- Consumes: Task 4, Task 5
- Produces: `func split(_ amount: Chips, among winners: [PlayerID], seats: [Seat], buttonIndex: Int) -> [PlayerID: Chips]` (internal); Dispatch `resolveShowdown`; Test-Helper `mutating func checkDown() throws(Rejection)` (checkt/callt bis `phase != .betting`) in `Helpers.swift`

- [ ] **Step 1: Failing Tests**

```swift
@Test func dealerAwardsSinglePot() throws {
    var g = try Game.started(); try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.resolveShowdown(winners: [["B"]]), by: "A", at: t0)
    #expect(g.state.phase == .handComplete && g.state.seat("B")?.stack == 1040)
}
@Test func splitPotOddChipGoesLeftOfButton() throws {
    var g = try Game.started(levels: [BlindLevel(smallBlind: 5, bigBlind: 10, duration: 600)])
    try g.act(.call); try g.act(.fold); try g.checkDown()       // Pot 25, A und C im Showdown
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
@Test func onlyDealerMayResolve()        // resolve by "B" → .notDealer (auch Host ist nur Dealer, wenn er den Button hat)
@Test func showdownWinnersValidated()    // im Side-Pot-Szenario: [["B"],["B"]] → .invalidShowdown (B nicht berechtigt);
                                         // [["B"]] → .invalidShowdown (Anzahl); [[],["C"]] → .invalidShowdown
@Test func resolveOutsideShowdownRejected() // in .betting → .invalidPhase
```

- [ ] **Step 2: Run** `swift test --filter ShowdownTests` → Expected: FAIL

- [ ] **Step 3: Implementieren**

`resolveShowdown`: nur in `.showdown`, `actor == dealerID`; `winners.count == pots.count`, jede Liste nicht leer, ohne Duplikate und ⊆ `eligible` des Pots. `split`: jeder bekommt `amount / n`; der Rest geht chipweise an die Gewinner in Sitzreihenfolge, beginnend beim ersten Sitz links vom Button. Danach `pots = []`, `phase = .handComplete`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): showdown resolution with split and odd chip"`

---

### Task 7: Handende, Ausscheiden, nächste Hand, Spieler entfernen

**Files:**
- Modify: `Sources/PokerCore/Hand.swift`, `Sources/PokerCore/Game.swift`
- Test: `Tests/PokerCoreTests/HandEndTests.swift`

**Interfaces:**
- Consumes: Task 6
- Produces: `extension GameState { mutating func finishHand() }` (Ausscheiden, Turnierende); Dispatch `startNextHand`, `removePlayer` im Spiel; `public var ranking: [Seat]` (nach `eliminatedRank`, Sieger zuerst)

- [ ] **Step 1: Failing Tests**

```swift
@Test func eliminatedPlayerGetsRank()      // sidePotsResolvedSeparately-Szenario → A.eliminatedRank == 3, phase .handComplete
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
    try g.act(.call); try g.act(.call); try g.act(.allIn); try g.act(.call)  // D, A callen, B all-in 100, C callt
    try g.act(.call); try g.act(.call); try g.checkDown()                     // D, A callen nach
    try g.apply(.resolveShowdown(winners: [["C"]]), by: "A", at: t0)
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.state.seat("B")?.eliminatedRank == 4 && g.state.dealerID == "C")
}
@Test func startNextHandOnlyByDealerOrHost()  // nach Hand 1 (Dealer und Host = A): by "C" → .notDealer; in .betting → .invalidPhase
@Test func removePlayerMidHandFoldsAndEliminates() throws {
    var g = try Game.started()
    try g.apply(.removePlayer(player: "B"), by: "A", at: t0)
    try g.act(.fold)                                            // A foldet → C gewinnt
    #expect(g.state.phase == .handComplete && g.state.seat("B")?.eliminatedRank == 3)
}
@Test func removePlayerOnTurnAdvancesTurn()   // remove "A" ist Host → .illegalAction; nach A call: remove "B" (am Zug) → toAct == "C"
```

- [ ] **Step 2: Run** `swift test --filter HandEndTests` → Expected: FAIL

- [ ] **Step 3: Implementieren**

`finishHand()` läuft bei jedem Übergang nach `.handComplete`: Sitze mit `stack == 0` und ohne Rang scheiden aus; Bei `n` noch aktiven Sitzen vor der Hand und `k` Ausgeschiedenen, sortiert nach `stackAtHandStart` absteigend: Rang = `n − k + 1 + index` (wer mehr hatte, platziert sich besser). Bleibt ein Sitz übrig → `phase = .finished`. `startNextHand`: in `.handComplete`, `actor == dealerID || actor == hostID`, sonst `.notDealer`; Button wandert zum nächsten nicht ausgeschiedenen Sitz; `handNumber += 1`; Uhr fortschreiben (Task 8 – bis dahin keine Uhr-Logik); `startHand()`. `removePlayer` im Spiel (Host-only, nicht der Host selbst): Sitz `folded = true`, `stack = 0`; war er am Zug, rückt der nächste nach; danach dieselbe Prüfung wie nach einem Fold.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): elimination, ranking, next hand, remove player"`

---

### Task 8: Blind-Uhr

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
      public func remaining(at now: Date) -> TimeInterval   // pausedRemaining, sonst max(0, levelEndsAt − now)
  }
  ```
  Dispatch `pauseClock`, `resumeClock` (Host-only).

- [ ] **Step 1: Failing Tests** (`twoLevels = [BlindLevel(10, 20, 600), BlindLevel(20, 40, 600)]`, Hand 1 per Fold-Fold beenden)

```swift
@Test func levelAdvancesAtNextHandAfterExpiry() // startNextHand at t0+601 → levelIndex 1, BB-Sitz roundBet 40, levelEndsAt t0+1200
@Test func levelDoesNotChangeMidHand()          // Aktionen bei t0+700 → levelIndex 0
@Test func lastLevelStays()                     // startNextHand at t0+99_999 → levelIndex 1
@Test func pauseFreezesRemaining() throws {
    var g = try Game.started(levels: twoLevels)
    try g.apply(.pauseClock, by: "A", at: t0 + 100)
    #expect(g.state.clock.remaining(at: t0 + 5000) == 500 && g.state.clock.levelEndsAt == nil)
    try g.apply(.resumeClock, by: "A", at: t0 + 1000)
    #expect(g.state.clock.levelEndsAt == t0 + 1500)
}
@Test func noAdvanceWhilePaused()               // pause, Hand beenden, startNextHand at t0+5000 → levelIndex 0
@Test func clockCommandsHostOnly()              // pauseClock by "B" → .notHost; resume ohne Pause → .invalidPhase; pause doppelt → .invalidPhase
```

- [ ] **Step 2: Run** `swift test --filter ClockTests` → Expected: FAIL

- [ ] **Step 3: Implementieren**

`advance`: bei Pause nichts tun; sonst solange `levelIndex < levels.count − 1` und `now ≥ levelEndsAt`: `levelIndex += 1`, `levelEndsAt += levels[levelIndex].duration`. Aufruf in `startNextHand` vor `startHand()`. `pause`: `pausedRemaining = remaining(at:)`, `levelEndsAt = nil`. `resume`: `levelEndsAt = now + pausedRemaining`, `pausedRemaining = nil`.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): blind level clock with pause"`

---

### Task 9: Rückgängig und Persistenz-Fähigkeit

**Files:**
- Modify: `Sources/PokerCore/Game.swift`
- Test: `Tests/PokerCoreTests/UndoTests.swift`

**Interfaces:**
- Produces: Dispatch `undo` (Host-only, `state = history.removeLast()`); `Game` per `JSONEncoder`/`JSONDecoder` verlustfrei serialisierbar (Persistenz-Datei der App in Plan 3)

- [ ] **Step 1: Failing Tests**

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
@Test func nothingToUndoOnFreshGame()     // Game(...) direkt → .nothingToUndo
@Test func rejectedCommandDoesNotGrowHistory() // history.count vor/nach abgelehnter Aktion gleich
@Test func gameRoundTripsThroughJSON() throws {
    var g = try Game.started(); try g.act(.raiseTo(amount: 100))
    let data = try Wire.encoder.encode(g)
    #expect(try Wire.decoder.decode(Game.self, from: data) == g)
}
```
(`Wire.encoder/decoder` kommen in Task 10; bis dahin in diesem Test `JSONEncoder()`/`JSONDecoder()` verwenden und in Task 10 umstellen.)

- [ ] **Step 2: Run** `swift test --filter UndoTests` → Expected: FAIL

- [ ] **Step 3: Implementieren** – `undo` ohne Historie → `.nothingToUndo`; `undo` selbst wird nicht in die Historie geschrieben.

- [ ] **Step 4: Run** `swift test` → Expected: PASS

- [ ] **Step 5: Commit** `git commit -am "feat(core): host undo via state history"`

---

### Task 10: Wire-Protokoll und PROTOCOL.md

**Files:**
- Create: `Sources/PokerCore/Wire.swift`, `docs/PROTOCOL.md`
- Modify: `docs/superpowers/specs/2026-11-11-pokerchipcase-design.md` (Abschnitt Protokoll: Client → Host sind `hello` und `command`)
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
  Umschlag: `{"v": 1, "type": "<case>", "id": "<UUID>", "payload": <Nutzlast>}`; `type` ist der Case-Name (`hello`, `command`, `welcome`, `ack`, `state`, `error`).

- [ ] **Step 1: Failing Tests**

```swift
let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
@Test func commandGoldenJSON() throws {
    let data = try Wire.encode(.command(.act(player: "B", action: .raiseTo(amount: 60))), id: id1)
    #expect(String(decoding: data, as: UTF8.self) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"act":{"action":{"raiseTo":{"amount":60}},"player":"B"}},"type":"command","v":1}"#)
}
@Test func ackGoldenJSON()      // .ack(Ack(id: id1, result: .rejected(reason: .notYourTurn))) → exakter String mit "rejected":{"reason":"notYourTurn"}
@Test func clientRoundTrip()    // hello und command encode → decodeClient == Original, id erhalten
@Test func serverRoundTrip()    // state(Game.started().state) encode → decodeServer == Original
@Test func versionMismatchRejected() // JSON mit "v":2 → WireError.versionMismatch(2)
@Test func unknownTypeRejected()     // "type":"bogus" → WireError.unknownType("bogus")
```
Dazu in `UndoTests.gameRoundTripsThroughJSON` auf `Wire.encoder/decoder` umstellen.

- [ ] **Step 2: Run** `swift test --filter WireTests` → Expected: FAIL

- [ ] **Step 3: Implementieren** – manuelles `Codable` nur für den Umschlag (`type`/`payload` flach); `Command`, `Action`, `GameState` usw. bleiben synthetisiert (gelabelte Associated Values ergeben `{"case":{"label":…}}`, Cases ohne Werte `{"fold":{}}`).

- [ ] **Step 4: `docs/PROTOCOL.md` schreiben** – Zielgruppe: jemand, der einen kompatiblen Client (z. B. Android) baut. Inhalt: Transport (WebSocket über TLS 1.2 PSK, Cipher Suite `TLS_PSK_WITH_AES_128_GCM_SHA256`, PSK = HKDF-SHA256 über den 4-stelligen Tisch-Code mit Salt `pokerchipcase-v1`, Bonjour `_pokerchipcase._tcp`), Umschlag, alle Nachrichtentypen mit einem JSON-Beispiel je Typ (aus den Golden-Tests), Ablauf `hello → welcome → state`, `command → ack + state`, Autorisierungsregeln (wer darf welchen Befehl), Datumsformat (Millisekunden seit 1970), Versionsregel.

- [ ] **Step 5: Spec anpassen** – Protokoll-Abschnitt: Client → Host sind `hello` und `command` (`command` trägt `Command`; Autorisierung erfolgt in `PokerCore`).

- [ ] **Step 6: Run** `swift test` → Expected: alle Tests PASS

- [ ] **Step 7: Commit**

```bash
git add Sources Tests docs
git commit -m "feat(core): wire protocol types and PROTOCOL.md"
```
