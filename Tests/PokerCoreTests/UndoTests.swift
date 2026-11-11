import Foundation
import Testing
@testable import PokerCore

@Test func undoRestoresPreviousState() throws {
    var g = try Game.started()
    let before = g.state
    try g.act(.raiseTo(amount: 100))
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.ignoringVersion == before.ignoringVersion)
}

@Test func undoAfterShowdownRestoresChips() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call); try g.checkDown()
    let atShowdown = g.state
    try g.apply(.resolveShowdown(winners: [["B"]]), by: "A", at: t0)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.ignoringVersion == atShowdown.ignoringVersion)
}

private extension GameState {
    var ignoringVersion: GameState {
        var s = self
        s.version = 0
        return s
    }
}

@Test func undoOnlyHost() throws {
    var g = try Game.started()
    #expect(throws: Rejection.notHost) { try g.apply(.undo, by: "B", at: t0) }
}

@Test func nothingToUndoOnFreshGame() {
    var g = Game(hostID: "A", hostName: "A", config: .relaxed)
    #expect(throws: Rejection.nothingToUndo) { try g.apply(.undo, by: "A", at: t0) }
}

@Test func rejectedCommandDoesNotGrowHistory() throws {
    var g = try Game.started()
    let count = g.history.count
    #expect(throws: Rejection.illegalAction) { try g.act(.check) }
    #expect(g.history.count == count)
}

@Test func gameRoundTripsThroughJSON() throws {
    var g = try Game.started()
    try g.act(.raiseTo(amount: 100))
    let data = try Wire.encoder.encode(g)
    #expect(try Wire.decoder.decode(Game.self, from: data) == g)
}
