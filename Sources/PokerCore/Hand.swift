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
}
