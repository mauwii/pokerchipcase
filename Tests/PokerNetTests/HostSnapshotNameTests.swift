import Foundation
import Testing
@testable import PokerCore
@testable import PokerNet

@Test(arguments: [
    (String(repeating: "a", count: 40), String(repeating: "a", count: 32)),
    (String(repeating: "e\u{301}", count: 40), String(repeating: "e\u{301}", count: 32)),
    (String(repeating: "👨‍👩‍👧‍👦", count: 12), String(repeating: "👨‍👩‍👧‍👦", count: 10)),
    (" \n\t ", "Player"),
    ("  Anna  ", "Anna"),
    ("Anna", "Anna"),
])
func restoredHostNamesUseTheExistingLimits(_ name: String, _ normalized: String) throws {
    let legacy = try legacySnapshot(hostName: name)
    let data = try JSONEncoder().encode(legacy)
    let restored = try JSONDecoder().decode(HostSnapshot.self, from: data)

    var expected = legacy
    try #require(expected.game.history.count == 2)
    expected.game.state.seats[0].name = normalized
    expected.game.history[0].seats[0].name = normalized
    expected.game.history[1].seats[0].name = normalized
    #expect(restored == expected)
}

@Test func undoDoesNotRestoreAnOverlongHostName() throws {
    let name = String(repeating: "a", count: 40)
    let legacy = try legacySnapshot(hostName: name)
    var restored = try JSONDecoder().decode(HostSnapshot.self, from: JSONEncoder().encode(legacy))

    try restored.game.apply(.undo, by: "host", at: Date(timeIntervalSince1970: 1))

    #expect(restored.game.state.seat("host")?.name == String(repeating: "a", count: 32))
    #expect(restored.game.state.seat("guest")?.name == "Guest")
    #expect(restored.game.state.phase == .lobby)
    #expect(restored.game.state.version == legacy.game.state.version + 1)
    #expect(restored.tokens == legacy.tokens)
}

@Test(arguments: ["game", "tokens", "tableName", "code"])
func restoringNamesStillRequiresAllSnapshotFields(_ missing: String) throws {
    let data = try JSONEncoder().encode(legacySnapshot(hostName: "Anna"))
    var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    fields.removeValue(forKey: missing)
    let incomplete = try JSONSerialization.data(withJSONObject: fields)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(HostSnapshot.self, from: incomplete)
    }
}

private func legacySnapshot(hostName: String) throws -> HostSnapshot {
    var game = Game(hostID: "host", hostName: hostName, config: .relaxed)
    let now = Date(timeIntervalSince1970: 0)
    try game.apply(.join(player: "guest", name: "Guest"), by: "host", at: now)
    try game.apply(.startTournament(button: "host"), by: "host", at: now)
    return HostSnapshot(
        game: game, tokens: ["host-token": "host", "guest-token": "guest"],
        tableName: "Kitchen", code: code4711)
}
