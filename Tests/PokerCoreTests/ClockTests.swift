import Foundation
import Testing
@testable import PokerCore

private let twoLevels = [
    BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600),
    BlindLevel(smallBlind: 20, bigBlind: 40, duration: 600),
]

/// Hand 1 finished by fold, fold.
private func afterFirstHand() throws -> Game {
    var g = try Game.started(levels: twoLevels)
    try g.act(.fold); try g.act(.fold)
    return g
}

@Test func levelAdvancesAtNextHandAfterExpiry() throws {
    var g = try afterFirstHand()
    try g.apply(.startNextHand, by: "A", at: t0 + 601)
    #expect(g.state.clock.levelIndex == 1 && g.state.clock.levelEndsAt == t0 + 1200)
    #expect(g.state.seat("A")?.roundBet == 40)
}

@Test func levelDoesNotChangeMidHand() throws {
    var g = try Game.started(levels: twoLevels)
    try g.act(.call, at: t0 + 700); try g.act(.call, at: t0 + 700)
    #expect(g.state.clock.levelIndex == 0)
}

@Test func lastLevelStays() throws {
    var g = try afterFirstHand()
    try g.apply(.startNextHand, by: "A", at: t0 + 99_999)
    #expect(g.state.clock.levelIndex == 1)
}

@Test func pauseFreezesRemaining() throws {
    var g = try Game.started(levels: twoLevels)
    try g.apply(.pauseClock, by: "A", at: t0 + 100)
    #expect(g.state.clock.remaining(at: t0 + 5000) == 500 && g.state.clock.levelEndsAt == nil)
    try g.apply(.resumeClock, by: "A", at: t0 + 1000)
    #expect(g.state.clock.levelEndsAt == t0 + 1500)
}

@Test func noAdvanceWhilePaused() throws {
    var g = try Game.started(levels: twoLevels)
    try g.apply(.pauseClock, by: "A", at: t0 + 100)
    try g.act(.fold); try g.act(.fold)
    try g.apply(.startNextHand, by: "A", at: t0 + 5000)
    #expect(g.state.clock.levelIndex == 0)
}

@Test func clockCommandsHostOnly() throws {
    var g = try Game.started(levels: twoLevels)
    #expect(throws: Rejection.notHost) { try g.apply(.pauseClock, by: "B", at: t0) }
    #expect(throws: Rejection.invalidPhase) { try g.apply(.resumeClock, by: "A", at: t0) }
    try g.apply(.pauseClock, by: "A", at: t0)
    #expect(throws: Rejection.invalidPhase) { try g.apply(.pauseClock, by: "A", at: t0) }
}
