import Foundation
import Testing
@testable import PokerCore

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

@Test func startRequiresTwoPlayers() {
    var g = Game(hostID: "A", hostName: "A", config: .relaxed)
    #expect(throws: Rejection.tooFewPlayers) { try g.apply(.startTournament(button: "A"), by: "A", at: t0) }
}

@Test func startRequiresHost() throws {
    var g = Game(hostID: "A", hostName: "A", config: .relaxed)
    try g.apply(.join(player: "B", name: "B"), by: "A", at: t0)
    #expect(throws: Rejection.notHost) { try g.apply(.startTournament(button: "A"), by: "B", at: t0) }
}

@Test func startWithUnknownButton() throws {
    var g = Game(hostID: "A", hostName: "A", config: .relaxed)
    try g.apply(.join(player: "B", name: "B"), by: "A", at: t0)
    #expect(throws: Rejection.unknownPlayer) { try g.apply(.startTournament(button: "Z"), by: "A", at: t0) }
}

@Test func clockStartsAtTournamentStart() throws {
    let g = try Game.started()
    #expect(g.state.clock.levelIndex == 0 && g.state.clock.levelEndsAt == t0 + 600)
}
