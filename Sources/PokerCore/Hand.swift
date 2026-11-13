extension GameState {
    public var dealerID: PlayerID? { buttonIndex.map { seats[$0].id } }
    public var currentLevel: BlindLevel { config.levels[clock.levelIndex] }
    public var potTotal: Chips { seats.reduce(0) { $0 + $1.handBet } }
    public var minRaiseTo: Chips { currentBet + lastRaiseSize }

    /// Seats still in the tournament, in seat order, starting at `viewer`
    /// (or at the first remaining seat if `viewer` is nil, eliminated or unknown).
    public func tableOrder(viewer: PlayerID?) -> [Seat] {
        let remaining = seats.filter { !$0.isEliminated }
        let start = remaining.firstIndex { $0.id == viewer } ?? 0
        return Array(remaining[start...] + remaining[..<start])
    }

    var activeSeatCount: Int { seats.count { !$0.isEliminated } }

    /// Next seat after `i` (clockwise, `i` itself last) that satisfies `where`.
    func next(after i: Int, where predicate: (Seat) -> Bool) -> Int? {
        (1...seats.count).lazy.map { (i + $0) % seats.count }.first { predicate(seats[$0]) }
    }

    func nextActive(after i: Int) -> Int {
        next(after: i) { !$0.isEliminated }!
    }

    /// Eliminated seats count as folded, so all hand logic only has to check `folded`.
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

    /// nil when nobody has to act anymore – including when only one player could still bet and has already matched.
    func nextToAct(after i: Int) -> Int? {
        guard let n = next(after: i, where: needsToAct) else { return nil }
        if seats.count(where: canAct) == 1, seats[n].roundBet >= currentBet { return nil }
        return n
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

    /// Full raise: reopens the betting round for everyone else.
    mutating func raise(to x: Chips, seat i: Int) {
        post(x - seats[i].roundBet, seat: i)
        lastRaiseSize = x - currentBet
        currentBet = x
        for j in seats.indices where j != i && canAct(seats[j]) {
            seats[j].acted = false
            seats[j].mayRaise = true
        }
    }

    /// All-in as a call, a full raise or an incomplete raise. An incomplete raise reopens raising only for players
    /// who now face at least a full raise since they last acted (TDA Rule 43: several short all-ins can add up).
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
            // A player who acted has matched the bet they faced, so `roundBet` is that bet.
            if seats[j].acted || !seats[j].mayRaise { seats[j].mayRaise = x - seats[j].roundBet >= lastRaiseSize }
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
        // At most one player can still bet: no more betting, the remaining cards are dealt without betting.
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
                // Uncalled bet goes back, with folded players' chips above the highest call.
                // This pot is the top one, so every bet is cut to that call.
                let called = seats.filter { !$0.folded && $0.id != seats[j].id }.map(\.handBet).max() ?? 0
                seats[j].stack += pot.amount
                for k in seats.indices { seats[k].handBet = min(seats[k].handBet, called) }
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

    /// Bets are paid out: finish the hand.
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

    /// Players without chips are eliminated. Among several, players removed by the host (folded with no chips)
    /// place last, then whoever had more at hand start places better; equal players share a rank.
    mutating func eliminateBusted() {
        let remaining = activeSeatCount
        let busted = seats.indices.filter { !seats[$0].isEliminated && seats[$0].stack == 0 }
        let keys = busted.map { (seats[$0].folded ? 0 : 1, seats[$0].stackAtHandStart) }
        let ranks = keys.map { k in remaining - busted.count + 1 + keys.count { $0 > k } }
        for (j, rank) in zip(busted, ranks) {
            seats[j].eliminatedRank = rank
        }
        if activeSeatCount <= 1 { phase = .finished }
    }

    /// Winner or players still in first (by stack), then eliminated players by rank.
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

    /// Removes a player from the running tournament; their chips are forfeited.
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
    /// Additional chips needed to call; 0 when checking is possible.
    public var callAmount: Chips
    /// nil = raising not allowed.
    public var minRaiseTo: Chips?
    public var maxRaiseTo: Chips?
}
