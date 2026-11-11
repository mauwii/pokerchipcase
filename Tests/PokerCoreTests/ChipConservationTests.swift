import Foundation
import Testing
@testable import PokerCore

private func chipsInPlay(_ g: Game) -> Chips {
    g.state.seats.reduce(0) { $0 + $1.stack + $1.handBet }
}

@Test func lonePlayerWhoMatchedIsNotAskedToAct() throws {
    var g = try Game.started(["A": 5, "B": 15, "C": 1000])
    try g.act(.call); try g.act(.call)          // A all-in 5, B all-in 15; C has 20 in
    #expect(g.state.phase == .showdown)
    #expect(g.state.seat("C")?.stack == 985)    // 5 uncalled, returned
    #expect(chipsInPlay(g) == 1020)
}

@Test func sidePotPlayersCannotFoldAwayTheirChips() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 15, "D": 15])
    try g.act(.allIn); try g.act(.raiseTo(amount: 100)); try g.act(.call)   // D, A, B
    #expect(g.state.street == .flop && g.toAct == "B")
    try g.act(.fold)
    #expect(g.state.phase == .showdown)
    #expect(g.state.pots == [Pot(amount: 60, eligible: ["A", "C", "D"])])
    #expect(g.state.seat("A")?.stack == 1070)
    #expect(chipsInPlay(g) == 2030)
}

@Test func headsUpSmallBlindAllInFromPostingGoesToShowdown() throws {
    let g = try Game.started(["A": 10, "B": 1000])
    #expect(g.state.phase == .showdown)
    #expect(g.state.pots == [Pot(amount: 20, eligible: ["A", "B"])])
    #expect(g.state.seat("B")?.stack == 990)
}

@Test func deadChipsAboveLiveBetsGoToLastPot() {
    var a = Seat(id: "A", name: "A", stack: 500); a.handBet = 500; a.folded = true
    var b = Seat(id: "B", name: "B", stack: 0); b.handBet = 100; b.allIn = true
    var c = Seat(id: "C", name: "C", stack: 0); c.handBet = 200; c.allIn = true
    #expect(computePots([a, b, c]) == [Pot(amount: 300, eligible: ["B", "C"]), Pot(amount: 500, eligible: ["C"])])
}

/// SplitMix64: deterministic randomness for reproducible tournaments.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func chipsAreConservedInRandomTournaments() throws {
    for seed in 0..<300 {
        var rng = SeededRNG(state: UInt64(seed))
        let ids = ["A", "B", "C", "D", "E", "F"].prefix(Int.random(in: 2...6, using: &rng))
        var stacks: [(PlayerID, Chips)] = ids.map { ($0, Int.random(in: 1...1500, using: &rng)) }
        let host = stacks[0].0
        var g = Game(hostID: host, hostName: host, config: TournamentConfig(startingStack: 1000, levels: tenTwenty))
        for (id, _) in stacks.dropFirst() { try g.apply(.join(player: id, name: id), by: host, at: t0) }
        for (id, s) in stacks { g.state.seats[g.state.index(of: id)!].stack = s }
        try g.apply(.startTournament(button: host), by: host, at: t0)
        let total = stacks.reduce(0) { $0 + $1.1 }
        stacks = []

        for _ in 0..<3000 {
            let s = g.state
            switch s.phase {
            case .betting:
                let p = g.toAct!
                let la = s.legalActions(for: p)!
                var options: [Action] = [.fold, la.canCheck ? .check : .call, .allIn]
                if let lo = la.minRaiseTo, let hi = la.maxRaiseTo { options.append(.raiseTo(amount: Int.random(in: lo...hi, using: &rng))) }
                if !la.mayRaiseAllIn(s, p) { options.removeAll { $0 == .allIn } }
                try g.act(options.randomElement(using: &rng)!)
            case .showdown:
                #expect(s.pots.reduce(0) { $0 + $1.amount } == s.potTotal, "seed \(seed)")
                let winners = s.pots.map { [$0.eligible.randomElement(using: &rng)!] }
                try g.apply(.resolveShowdown(winners: winners), by: s.dealerID!, at: t0)
            case .handComplete:
                try g.apply(.startNextHand, by: host, at: t0)
            case .lobby, .finished:
                break
            }
            #expect(chipsInPlay(g) == total, "seed \(seed)")
            if g.state.phase == .finished { break }
        }
        #expect(g.state.phase == .finished, "seed \(seed)")
    }
}

private extension LegalActions {
    /// All-in is allowed if it is at most a call or raising is allowed.
    func mayRaiseAllIn(_ s: GameState, _ p: PlayerID) -> Bool {
        let seat = s.seat(p)!
        return seat.roundBet + seat.stack <= s.currentBet || minRaiseTo != nil
    }
}
