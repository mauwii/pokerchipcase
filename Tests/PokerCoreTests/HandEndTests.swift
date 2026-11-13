import Foundation
import Testing
@testable import PokerCore

@Test func eliminatedPlayerGetsRank() throws {
    var g = try Game.started(["A": 1000, "B": 300, "C": 1000])
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    try g.apply(.resolveShowdown(winners: [["B"], ["C"]]), by: "A", at: t0)
    #expect(g.state.phase == .handComplete && g.state.seat("A")?.eliminatedRank == 3)
}

@Test func twoEliminatedSameHandRankedByStartingStack() throws {
    var g = try Game.started(["A": 500, "B": 300, "C": 1000])
    try g.act(.allIn); try g.act(.allIn); try g.act(.call)
    try g.apply(.resolveShowdown(winners: g.state.pots.map { _ in ["C"] }), by: "A", at: t0)
    #expect(g.state.phase == .finished)
    #expect(g.state.ranking.map(\.id) == ["C", "A", "B"])
    #expect(g.state.seat("C")?.eliminatedRank == nil)
}

@Test func nextHandMovesButtonAndPostsBlinds() throws {
    var g = try Game.started()
    try g.act(.fold); try g.act(.fold)
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.state.dealerID == "B" && g.state.handNumber == 2 && g.toAct == "B")
    #expect(g.state.seat("C")?.roundBet == 10 && g.state.seat("A")?.roundBet == 20)
}

@Test func buttonSkipsEliminated() throws {
    var g = try Game.started(["A": 1000, "B": 100, "C": 1000, "D": 1000])
    try g.act(.call); try g.act(.call); try g.act(.allIn); try g.act(.call)
    try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.resolveShowdown(winners: [["C"]]), by: "A", at: t0)
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.state.seat("B")?.eliminatedRank == 4 && g.state.dealerID == "C")
}

@Test func startNextHandOnlyByDealerOrHost() throws {
    var g = try Game.started()
    #expect(throws: Rejection.invalidPhase) { try g.apply(.startNextHand, by: "A", at: t0) }
    try g.act(.fold); try g.act(.fold)
    #expect(throws: Rejection.notDealer) { try g.apply(.startNextHand, by: "C", at: t0) }
}

@Test func removePlayerMidHandFoldsAndEliminates() throws {
    var g = try Game.started()
    try g.apply(.removePlayer(player: "B"), by: "A", at: t0)
    try g.act(.fold)
    #expect(g.state.phase == .handComplete && g.state.seat("B")?.eliminatedRank == 3)
}

@Test func removePlayerOnTurnAdvancesTurn() throws {
    var g = try Game.started()
    #expect(throws: Rejection.illegalAction) { try g.apply(.removePlayer(player: "A"), by: "A", at: t0) }
    try g.act(.call)
    try g.apply(.removePlayer(player: "B"), by: "A", at: t0)
    #expect(g.toAct == "C")
}

@Test func removedChipLeaderRanksBelowPlayerBustedInSameHand() throws {
    var g = try Game.started(["A": 1000, "B": 5000, "C": 300, "D": 1000])
    try g.apply(.removePlayer(player: "B"), by: "A", at: t0)
    try g.act(.allIn); try g.act(.fold); try g.act(.call)   // D all-in, A folds, C calls all-in
    try g.apply(.resolveShowdown(winners: [["D"]]), by: "A", at: t0)
    #expect(g.state.seat("C")?.eliminatedRank == 3 && g.state.seat("B")?.eliminatedRank == 4)
}

@Test func equalStartingStacksShareARank() throws {
    var g = try Game.started(["A": 1000, "B": 300, "C": 300])
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    try g.apply(.resolveShowdown(winners: [["A"]]), by: "A", at: t0)
    #expect(g.state.phase == .finished)
    #expect(g.state.seat("B")?.eliminatedRank == 2 && g.state.seat("C")?.eliminatedRank == 2)
}
