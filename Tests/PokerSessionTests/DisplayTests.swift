import Testing
@testable import PokerCore
@testable import PokerSession

@Test func dealerHintsFollowTheStreets() throws {
    var g = try started()
    #expect(g.state.dealerHint == .dealHand)
    try g.act(.call)
    #expect(g.state.dealerHint == nil)
    try g.act(.call); try g.act(.check)
    #expect(g.state.street == .flop && g.state.dealerHint == .dealFlop)
    try g.act(.check)
    #expect(g.state.dealerHint == nil)
    try g.act(.check); try g.act(.check)
    #expect(g.state.dealerHint == .dealTurn)
    for _ in 0..<3 { try g.act(.check) }
    #expect(g.state.dealerHint == .dealRiver)
    for _ in 0..<3 { try g.act(.check) }
    #expect(g.state.phase == .showdown && g.state.dealerHint == nil)
}

@Test func allInBeforeTheRiverAsksToDealTheRest() throws {
    var g = try started()
    try g.act(.allIn); try g.act(.call); try g.act(.fold)
    #expect(g.state.phase == .showdown && g.state.street == .preflop && g.state.dealerHint == .dealRest)
}

@Test func noHintWhenTheHandIsWonByFolds() throws {
    var g = try started()
    try g.act(.fold); try g.act(.fold)
    #expect(g.state.phase == .handComplete && g.state.dealerHint == nil)
}

@Test func quickPicksPreflop() throws {
    #expect(try started().state.quickPicks(for: "A") == [
        QuickPick(kind: .halfPot, raiseTo: 45), QuickPick(kind: .pot, raiseTo: 70), QuickPick(kind: .allIn, raiseTo: 1000),
    ])
}

@Test func quickPicksClampedToTheStack() throws {
    #expect(try started(stacks: ["A": 50]).state.quickPicks(for: "A") == [
        QuickPick(kind: .halfPot, raiseTo: 45), QuickPick(kind: .allIn, raiseTo: 50),
    ])
}

@Test func noQuickPicksWhenRaisingIsImpossible() throws {
    #expect(try started().state.quickPicks(for: "B").isEmpty)
    #expect(try started(stacks: ["A": 15]).state.quickPicks(for: "A").isEmpty)
}

@Test func lastChipsCountAsAllIn() throws {
    let s = try started().state
    #expect(!s.commitsAllChips(.call, by: "A") && !s.commitsAllChips(.raiseTo(amount: 500), by: "A"))
    #expect(s.commitsAllChips(.raiseTo(amount: 1000), by: "A") && s.commitsAllChips(.allIn, by: "A"))
    #expect(!s.commitsAllChips(.fold, by: "A") && !s.commitsAllChips(.check, by: "A"))
    #expect(try started(stacks: ["A": 20]).state.commitsAllChips(.call, by: "A"))
}

// A button, B/C blinds with 1 chip each, D acts first.
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
    #expect(try !started(stacks: ["B": 30]).state.commitsAllChips(.call, by: "B"))  // posts 10, 20 left
    #expect(try !started(stacks: ["B": 40]).state.commitsAllChips(.raiseTo(amount: 35), by: "B"))
}
