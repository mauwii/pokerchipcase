import Foundation
import Testing
@testable import PokerCore

@Test func tableOrderStartsAtViewer() throws {
    let g = try Game.started(["A": 1000, "B": 1000, "C": 1000, "D": 1000])
    #expect(g.state.tableOrder(viewer: "C").map(\.id) == ["C", "D", "A", "B"])
}

/// A goes all-in, B and C call, B wins the main pot and C the side pot: A is out (see HandEndTests).
private func gameWithAOut() throws -> Game {
    var g = try Game.started(["A": 1000, "B": 300, "C": 1000])
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    try g.apply(.resolveShowdown(winners: [["B"], ["C"]]), by: "A", at: t0)
    return g
}

@Test func tableOrderSkipsEliminatedSeats() throws {
    let g = try gameWithAOut()
    #expect(g.state.tableOrder(viewer: "C").map(\.id) == ["C", "B"])
}

@Test func tableOrderWithoutViewerStartsAtFirstRemainingSeat() throws {
    let g = try gameWithAOut()
    #expect(g.state.tableOrder(viewer: nil).map(\.id) == ["B", "C"])
    #expect(g.state.tableOrder(viewer: "A").map(\.id) == ["B", "C"])
}
