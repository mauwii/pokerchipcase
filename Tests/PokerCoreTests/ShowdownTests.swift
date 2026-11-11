import Foundation
import Testing
@testable import PokerCore

@Test func dealerAwardsSinglePot() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.resolveShowdown(winners: [["B"]]), by: "A", at: t0)
    #expect(g.state.phase == .handComplete && g.state.seat("B")?.stack == 1040)
}

@Test func splitPotOddChipGoesLeftOfButton() throws {
    var g = try Game.started(levels: [BlindLevel(smallBlind: 5, bigBlind: 10, duration: 600)])
    try g.act(.call); try g.act(.fold); try g.checkDown()
    try g.apply(.resolveShowdown(winners: [["A", "C"]]), by: "A", at: t0)
    #expect(g.state.seat("A")?.stack == 1002 && g.state.seat("C")?.stack == 1003)
}

@Test func sidePotsResolvedSeparately() throws {
    var g = try Game.started(["A": 1000, "B": 300, "C": 1000])
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    #expect(g.state.pots == [Pot(amount: 900, eligible: ["A", "B", "C"]), Pot(amount: 1400, eligible: ["A", "C"])])
    try g.apply(.resolveShowdown(winners: [["B"], ["C"]]), by: "A", at: t0)
    #expect(g.state.seat("B")?.stack == 900 && g.state.seat("C")?.stack == 1400 && g.state.seat("A")?.stack == 0)
}

@Test func onlyDealerOrHostMayResolve() throws {
    var g = try Game.started(["B": 1000, "A": 1000, "C": 1000])   // Host B, Dealer A
    try g.act(.call); try g.act(.call); try g.checkDown()
    #expect(throws: Rejection.notDealer) { try g.apply(.resolveShowdown(winners: [["C"]]), by: "C", at: t0) }
}

@Test func hostResolvesWhenDealerWasRemoved() throws {
    var g = try Game.started(["B": 1000, "A": 1000, "C": 1000])   // Host B, Dealer A
    try g.apply(.removePlayer(player: "A"), by: "B", at: t0)
    try g.checkDown()
    try g.apply(.resolveShowdown(winners: [["C"]]), by: "B", at: t0)
    #expect(g.state.phase == .handComplete)
}

@Test func showdownWinnersValidated() throws {
    var g = try Game.started(["A": 1000, "B": 300, "C": 1000])
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    #expect(throws: Rejection.invalidShowdown) { try g.apply(.resolveShowdown(winners: [["B"], ["B"]]), by: "A", at: t0) }
    #expect(throws: Rejection.invalidShowdown) { try g.apply(.resolveShowdown(winners: [["B"]]), by: "A", at: t0) }
    #expect(throws: Rejection.invalidShowdown) { try g.apply(.resolveShowdown(winners: [[], ["C"]]), by: "A", at: t0) }
    #expect(throws: Rejection.invalidShowdown) { try g.apply(.resolveShowdown(winners: [["A", "A"], ["C"]]), by: "A", at: t0) }
}

@Test func resolveOutsideShowdownRejected() throws {
    var g = try Game.started()
    #expect(throws: Rejection.invalidPhase) { try g.apply(.resolveShowdown(winners: [["A"]]), by: "A", at: t0) }
}
