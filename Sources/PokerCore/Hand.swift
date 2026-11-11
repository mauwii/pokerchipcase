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
        case let .raiseTo(x):
            guard seats[i].mayRaise else { throw .illegalAction }
            guard x >= minRaiseTo, x <= seats[i].roundBet + seats[i].stack else { throw .invalidAmount }
            raise(to: x, seat: i)
        case .allIn:
            throw .illegalAction
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
        pots = [Pot(amount: potTotal, eligible: seats.filter { !$0.folded }.map(\.id))]
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
