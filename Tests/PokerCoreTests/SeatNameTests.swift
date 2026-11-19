import Foundation
import Testing
@testable import PokerCore

@Test func renamingSeatPreservesGameAndUndoSteps() throws {
    var game = Game(hostID: "host", hostName: "Anna", config: .relaxed)
    let now = Date(timeIntervalSince1970: 0)
    try game.apply(.join(player: "guest", name: "Guest"), by: "host", at: now)
    try game.apply(.startTournament(button: "host"), by: "host", at: now)
    var expected = game
    expected.state.seats[1].name = "New name"
    expected.history[1].seats[1].name = "New name"

    game.renameSeat("guest", to: "New name")

    #expect(game == expected)
    try game.apply(.undo, by: "host", at: now)
    #expect(game.state.seat("guest")?.name == "New name")
}

@Test func renamingUnknownSeatLeavesGameUnchanged() {
    var game = Game(hostID: "host", hostName: "Anna", config: .relaxed)
    let original = game
    game.renameSeat("unknown", to: "New name")
    #expect(game == original)
}
