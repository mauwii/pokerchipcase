import Foundation
import Testing
@testable import PokerCore

@Test func incompleteAllInDoesNotReopenRaising() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 150])
    try g.act(.raiseTo(amount: 100)); try g.act(.call)
    try g.act(.allIn)
    #expect(g.state.currentBet == 150 && g.toAct == "A")
    #expect(g.state.legalActions(for: "A")?.minRaiseTo == nil)
    #expect(throws: Rejection.illegalAction) { try g.act(.raiseTo(amount: 300)) }
    try g.act(.call)
}

@Test func fullAllInReopensRaising() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 300])
    try g.act(.raiseTo(amount: 100)); try g.act(.call); try g.act(.allIn)
    #expect(g.state.minRaiseTo == 500)
    #expect(g.state.legalActions(for: "A")?.minRaiseTo == 500)
}

@Test func allInPreflopRunsOutToShowdown() throws {
    var g = try Game.started()
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    #expect(g.state.phase == .showdown && g.state.street == .preflop)
    #expect(g.state.pots == [Pot(amount: 3000, eligible: ["A", "B", "C"])])
}

@Test func onlyOnePlayerLeftToActRunsOut() throws {
    var g = try Game.started(["A": 1000, "B": 200, "C": 1000])
    try g.act(.allIn); try g.act(.call); try g.act(.fold)
    #expect(g.state.phase == .showdown)
    #expect(g.state.seat("A")?.stack == 800)
    #expect(g.state.pots == [Pot(amount: 420, eligible: ["A", "B"])])
}

@Test func allInWithMayRaiseFalseThatWouldRaiseRejected() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 150])
    try g.act(.raiseTo(amount: 100)); try g.act(.call); try g.act(.allIn)
    #expect(throws: Rejection.illegalAction) { try g.act(.allIn) }
}

@Test func raiseToFullStackIsAllIn() throws {
    var g = try Game.started(["A": 1000, "B": 1000, "C": 150])
    try g.act(.raiseTo(amount: 100)); try g.act(.call)
    try g.act(.raiseTo(amount: 150))     // C' gesamter Stack, unter minRaiseTo 180
    #expect(g.state.seat("C")?.allIn == true && g.state.currentBet == 150)
}
