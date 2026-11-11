import Foundation
import Testing
@testable import PokerCore

@Test func legalActionsAtStart() throws {
    let g = try Game.started()
    #expect(g.state.legalActions(for: "A") == LegalActions(canCheck: false, callAmount: 20, minRaiseTo: 40, maxRaiseTo: 1000))
    #expect(g.state.legalActions(for: "B") == nil)
}

@Test func bigBlindHasOptionPreflop() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call)
    #expect(g.state.street == .preflop && g.toAct == "C")
    #expect(g.state.legalActions(for: "C")?.canCheck == true)
}

@Test func callCheckAdvancesToFlop() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call); try g.act(.check)
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
    var g = try Game.started()
    try g.act(.raiseTo(amount: 100))
    #expect(g.state.minRaiseTo == 180)
}

@Test func raiseAboveStackRejected() throws {
    var g = try Game.started()
    #expect(throws: Rejection.invalidAmount) { try g.act(.raiseTo(amount: 1001)) }
}

@Test func checkNotAllowedFacingBet() throws {
    var g = try Game.started()
    #expect(throws: Rejection.illegalAction) { try g.act(.check) }
}

@Test func foldToOneAwardsPot() throws {
    var g = try Game.started()
    try g.act(.fold); try g.act(.fold)
    #expect(g.state.phase == .handComplete)
    #expect(g.state.seat("C")?.stack == 1010 && g.state.seat("B")?.stack == 990)
}

@Test func outOfTurnRejectedAndStateUnchanged() throws {
    var g = try Game.started()
    let before = g
    #expect(throws: Rejection.notYourTurn) { try g.apply(.act(player: "B", action: .call), by: "B", at: t0) }
    #expect(g == before)
}

@Test func doubleTapRejected() throws {
    var g = try Game.started()
    try g.apply(.act(player: "A", action: .call), by: "A", at: t0)
    #expect(throws: Rejection.notYourTurn) { try g.apply(.act(player: "A", action: .call), by: "A", at: t0) }
}

@Test func hostMayFoldOrCheckForOthersOnly() throws {
    var g = try Game.started()
    try g.act(.call)
    #expect(throws: Rejection.illegalAction) { try g.apply(.act(player: "B", action: .call), by: "A", at: t0) }
    try g.apply(.act(player: "B", action: .fold), by: "A", at: t0)
    #expect(g.state.seat("B")?.folded == true)
}

@Test func nonHostMayNotActForOthers() throws {
    var g = try Game.started()
    try g.act(.call)
    #expect(throws: Rejection.notYourTurn) { try g.apply(.act(player: "B", action: .fold), by: "C", at: t0) }
}

@Test func riverCompletesToShowdown() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call); try g.act(.check)
    for _ in 0..<9 { try g.act(.check) }
    #expect(g.state.phase == .showdown && g.state.street == .river)
    #expect(g.state.pots == [Pot(amount: 60, eligible: ["A", "B", "C"])])
}

@Test func actOutsideBettingRejected() throws {
    var g = try Game.started()
    try g.act(.fold); try g.act(.fold)
    #expect(throws: Rejection.invalidPhase) { try g.apply(.act(player: "A", action: .check), by: "A", at: t0) }
}
