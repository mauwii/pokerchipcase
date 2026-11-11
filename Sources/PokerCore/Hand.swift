extension GameState {
    public var dealerID: PlayerID? { buttonIndex.map { seats[$0].id } }
    public var currentLevel: BlindLevel { config.levels[clock.levelIndex] }
    public var potTotal: Chips { seats.reduce(0) { $0 + $1.handBet } }
    public var minRaiseTo: Chips { currentBet + lastRaiseSize }

    var activeSeatCount: Int { seats.count { !$0.isEliminated } }

    /// Nächster Sitz nach `i` (im Uhrzeigersinn, `i` selbst zuletzt), der `where` erfüllt.
    func next(after i: Int, where predicate: (Seat) -> Bool) -> Int? {
        (1...seats.count).lazy.map { (i + $0) % seats.count }.first { predicate(seats[$0]) }
    }

    func nextActive(after i: Int) -> Int {
        next(after: i) { !$0.isEliminated }!
    }

    /// Ausgeschiedene Sitze gelten als gefoldet, damit alle Hand-Logik nur `folded` prüfen muss.
    mutating func startHand() {
        phase = .betting
        street = .preflop
        pots = []
        for i in seats.indices {
            seats[i].roundBet = 0
            seats[i].handBet = 0
            seats[i].stackAtHandStart = seats[i].stack
            seats[i].folded = seats[i].isEliminated
            seats[i].allIn = false
            seats[i].acted = false
            seats[i].mayRaise = true
        }

        let button = buttonIndex!
        let level = currentLevel
        let sb = activeSeatCount == 2 ? button : nextActive(after: button)
        let bb = nextActive(after: sb)
        post(level.smallBlind, seat: sb)
        post(level.bigBlind, seat: bb)
        currentBet = level.bigBlind
        lastRaiseSize = level.bigBlind
        toActIndex = nextToAct(after: bb)
        if toActIndex == nil { endRound() }
    }

    mutating func post(_ amount: Chips, seat i: Int) {
        let paid = min(amount, seats[i].stack)
        seats[i].stack -= paid
        seats[i].roundBet += paid
        seats[i].handBet += paid
        if seats[i].stack == 0 { seats[i].allIn = true }
    }

    func canAct(_ s: Seat) -> Bool { !s.folded && !s.allIn }

    func needsToAct(_ s: Seat) -> Bool { canAct(s) && (!s.acted || s.roundBet < currentBet) }

    func nextToAct(after i: Int) -> Int? {
        next(after: i, where: needsToAct)
    }

    public func legalActions(for player: PlayerID) -> LegalActions? {
        guard phase == .betting, let i = toActIndex, seats[i].id == player else { return nil }
        let s = seats[i]
        let toCall = max(0, currentBet - s.roundBet)
        let allInTo = s.roundBet + s.stack
        let canRaise = s.mayRaise && allInTo > currentBet
        return LegalActions(
            canCheck: toCall == 0,
            callAmount: min(toCall, s.stack),
            minRaiseTo: canRaise ? min(minRaiseTo, allInTo) : nil,
            maxRaiseTo: canRaise ? allInTo : nil
        )
    }

    mutating func perform(_ action: Action, by i: Int) throws(Rejection) {
        switch action {
        case .fold:
            seats[i].folded = true
        case .check:
            guard seats[i].roundBet == currentBet else { throw .illegalAction }
        case .call:
            guard currentBet > seats[i].roundBet else { throw .illegalAction }
            post(min(currentBet - seats[i].roundBet, seats[i].stack), seat: i)
        case let .raiseTo(x) where x == seats[i].roundBet + seats[i].stack:
            try goAllIn(seat: i)
        case let .raiseTo(x):
            guard seats[i].mayRaise else { throw .illegalAction }
            guard x >= minRaiseTo, x <= seats[i].roundBet + seats[i].stack else { throw .invalidAmount }
            raise(to: x, seat: i)
        case .allIn:
            try goAllIn(seat: i)
        }
        seats[i].acted = true
        afterAction(by: i)
    }

    /// Volles Raise: öffnet die Setzrunde für alle anderen erneut.
    mutating func raise(to x: Chips, seat i: Int) {
        post(x - seats[i].roundBet, seat: i)
        lastRaiseSize = x - currentBet
        currentBet = x
        for j in seats.indices where j != i && canAct(seats[j]) {
            seats[j].acted = false
            seats[j].mayRaise = true
        }
    }

    /// All-in als Call, volles Raise oder unvollständiges Raise (öffnet Raises nicht für Spieler, die schon gehandelt haben).
    mutating func goAllIn(seat i: Int) throws(Rejection) {
        let x = seats[i].roundBet + seats[i].stack
        if x <= currentBet {
            post(seats[i].stack, seat: i)
            return
        }
        guard seats[i].mayRaise else { throw .illegalAction }
        if x - currentBet >= lastRaiseSize {
            raise(to: x, seat: i)
            return
        }
        post(seats[i].stack, seat: i)
        currentBet = x
        for j in seats.indices where j != i && canAct(seats[j]) {
            if seats[j].acted { seats[j].mayRaise = false }
            seats[j].acted = false
        }
    }

    mutating func afterAction(by i: Int) {
        let inHand = seats.indices.filter { !seats[$0].folded }
        if inHand.count == 1 {
            seats[inHand[0]].stack += potTotal
            completeHand()
        } else if let n = nextToAct(after: i) {
            toActIndex = n
        } else {
            endRound()
        }
    }

    mutating func endRound() {
        // Höchstens einer kann noch setzen: keine Setzrunde mehr, restliche Karten werden ohne Setzen aufgedeckt.
        if seats.count(where: canAct) <= 1 { return enterShowdown() }
        let nextStreet: Street
        switch street {
        case .preflop: nextStreet = .flop
        case .flop: nextStreet = .turn
        case .turn: nextStreet = .river
        case .river: return enterShowdown()
        }
        street = nextStreet
        currentBet = 0
        lastRaiseSize = currentLevel.bigBlind
        for j in seats.indices {
            seats[j].roundBet = 0
            seats[j].acted = false
            seats[j].mayRaise = true
        }
        toActIndex = nextToAct(after: buttonIndex!)
    }

    mutating func enterShowdown() {
        phase = .showdown
        toActIndex = nil
        pots = []
        for pot in computePots(seats) {
            if pot.eligible.count == 1, let j = index(of: pot.eligible[0]) {
                // Ungecallter Einsatz geht zurück.
                seats[j].stack += pot.amount
                seats[j].handBet -= pot.amount
            } else {
                pots.append(pot)
            }
        }
    }

    mutating func resolveShowdown(_ winners: [[PlayerID]]) throws(Rejection) {
        guard winners.count == pots.count else { throw .invalidShowdown }
        for (pot, ws) in zip(pots, winners) {
            guard !ws.isEmpty, Set(ws).count == ws.count, ws.allSatisfy(pot.eligible.contains) else {
                throw .invalidShowdown
            }
        }
        for (pot, ws) in zip(pots, winners) {
            for (id, chips) in split(pot.amount, among: ws, seats: seats, buttonIndex: buttonIndex!) {
                seats[index(of: id)!].stack += chips
            }
        }
        completeHand()
    }

    /// Einsätze sind verteilt: Hand abschließen.
    mutating func completeHand() {
        for j in seats.indices {
            seats[j].roundBet = 0
            seats[j].handBet = 0
        }
        pots = []
        toActIndex = nil
        phase = .handComplete
        eliminateBusted()
    }

    /// Spieler ohne Chips scheiden aus; bei mehreren platziert sich besser, wer zu Handbeginn mehr hatte.
    mutating func eliminateBusted() {
        let remaining = activeSeatCount
        let busted = seats.indices
            .filter { !seats[$0].isEliminated && seats[$0].stack == 0 }
            .sorted { seats[$0].stackAtHandStart > seats[$1].stackAtHandStart }
        for (k, j) in busted.enumerated() {
            seats[j].eliminatedRank = remaining - busted.count + 1 + k
        }
        if activeSeatCount <= 1 { phase = .finished }
    }

    /// Sieger bzw. noch Spielende zuerst (nach Stack), dann Ausgeschiedene nach Platzierung.
    public var ranking: [Seat] {
        seats.sorted {
            switch ($0.eliminatedRank, $1.eliminatedRank) {
            case (nil, nil): $0.stack > $1.stack
            case (nil, _): true
            case (_, nil): false
            case let (a?, b?): a < b
            }
        }
    }

    mutating func startNextHand() {
        buttonIndex = nextActive(after: buttonIndex!)
        handNumber += 1
        startHand()
    }

    /// Entfernt einen Spieler aus dem laufenden Turnier; seine Chips verfallen.
    mutating func removeFromGame(seat i: Int) throws(Rejection) {
        switch phase {
        case .betting:
            seats[i].folded = true
            seats[i].stack = 0
            if toActIndex == i || seats.count(where: { !$0.folded }) == 1 {
                afterAction(by: i)
            }
        case .handComplete:
            seats[i].stack = 0
            eliminateBusted()
        default:
            throw .invalidPhase
        }
    }
}

public struct LegalActions: Equatable, Sendable {
    public var canCheck: Bool
    /// Zusätzliche Chips zum Callen; 0, wenn Check möglich ist.
    public var callAmount: Chips
    /// nil = Raise nicht erlaubt.
    public var minRaiseTo: Chips?
    public var maxRaiseTo: Chips?

    public init(canCheck: Bool, callAmount: Chips, minRaiseTo: Chips?, maxRaiseTo: Chips?) {
        self.canCheck = canCheck
        self.callAmount = callAmount
        self.minRaiseTo = minRaiseTo
        self.maxRaiseTo = maxRaiseTo
    }
}
