import Foundation
import Testing
@testable import PokerCore

@Test func hostIsSeatedOnCreation() {
    let g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    #expect(g.state.phase == .lobby)
    #expect(g.state.seats.map(\.id) == ["A"])
    #expect(g.state.seat("A")?.stack == 1000)
}

@Test func hostAddsPlayers() throws {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    try g.apply(.join(player: "B", name: "Ben"), by: "A", at: t0)
    #expect(g.state.seats.map(\.id) == ["A", "B"])
}

@Test func onlyHostMayAddPlayers() {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    #expect(throws: Rejection.notHost) { try g.apply(.join(player: "B", name: "Ben"), by: "B", at: t0) }
}

@Test func duplicatePlayerRejected() {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    #expect(throws: Rejection.duplicatePlayer) { try g.apply(.join(player: "A", name: "Anna"), by: "A", at: t0) }
}

@Test func tableFullAtTen() throws {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    for i in 1..<10 { try g.apply(.join(player: "P\(i)", name: "P\(i)"), by: "A", at: t0) }
    #expect(g.state.seats.count == 10)
    #expect(throws: Rejection.tableFull) { try g.apply(.join(player: "X", name: "X"), by: "A", at: t0) }
}

@Test func arrangeSeatsReorders() throws {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    try g.apply(.join(player: "B", name: "Ben"), by: "A", at: t0)
    try g.apply(.arrangeSeats(order: ["B", "A"]), by: "A", at: t0)
    #expect(g.state.seats.map(\.id) == ["B", "A"])
    #expect(throws: Rejection.unknownPlayer) { try g.apply(.arrangeSeats(order: ["B", "Z"]), by: "A", at: t0) }
    #expect(throws: Rejection.unknownPlayer) { try g.apply(.arrangeSeats(order: ["B"]), by: "A", at: t0) }
}

@Test func removePlayerInLobby() throws {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    try g.apply(.join(player: "B", name: "Ben"), by: "A", at: t0)
    try g.apply(.removePlayer(player: "B"), by: "A", at: t0)
    #expect(g.state.seats.map(\.id) == ["A"])
    #expect(throws: Rejection.illegalAction) { try g.apply(.removePlayer(player: "A"), by: "A", at: t0) }
}

@Test func presetsStartAtTenTwenty() {
    #expect(TournamentConfig.relaxed.levels.first == BlindLevel(smallBlind: 10, bigBlind: 20, duration: 1200))
    #expect(TournamentConfig.quick.levels.first?.duration == 600)
    #expect(TournamentConfig.presets.map(\.name) == ["Relaxed – 20 min", "Quick – 10 min"])
}
