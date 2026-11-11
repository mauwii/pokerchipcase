import Foundation
import Testing
@testable import PokerCore

@Test func doubleTapOnNextStreetRejected() throws {
    var g = try Game.started(["A": 1000, "B": 1000])
    try g.act(.call)
    let seen = g.state.version
    try g.apply(.act(player: "B", action: .check), by: "B", at: t0, expectedVersion: seen)
    #expect(g.state.street == .flop && g.toAct == "B")
    #expect(throws: Rejection.staleState) {
        try g.apply(.act(player: "B", action: .check), by: "B", at: t0, expectedVersion: seen)
    }
    #expect(g.state.street == .flop && g.toAct == "B")
}

@Test func doubleTapUndoRejected() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call)
    let seen = g.state.version
    try g.apply(.undo, by: "A", at: t0, expectedVersion: seen)
    #expect(throws: Rejection.staleState) { try g.apply(.undo, by: "A", at: t0, expectedVersion: seen) }
}

@Test func versionIncreasesMonotonicallyAcrossUndo() throws {
    var g = try Game.started()
    let start = g.state.version
    try g.act(.call)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.version == start + 2)
}
