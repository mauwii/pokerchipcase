import Foundation
import Network
import PokerNet
import Testing
@testable import PokerSession
@testable import PokerCore

let t0 = Date(timeIntervalSince1970: 0)
let code4711 = TableCode("4711")!

/// A (host), B, C with 1000 chips each unless `stacks` says otherwise; blinds 10/20; button A, started at t0.
/// B posts 10, C posts 20, A acts first.
func started(stacks: [PlayerID: Chips] = [:]) throws -> Game {
    var g = Game(
        hostID: "A", hostName: "A",
        config: TournamentConfig(startingStack: 1000, levels: [BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600)]))
    try g.apply(.join(player: "B", name: "B"), by: "A", at: t0)
    try g.apply(.join(player: "C", name: "C"), by: "A", at: t0)
    for (id, stack) in stacks {
        g.state.seats[g.state.index(of: id)!].stack = stack
    }
    try g.apply(.startTournament(button: "A"), by: "A", at: t0)
    return g
}

extension Game {
    /// The player to act, by themselves, at t0.
    mutating func act(_ action: Action) throws {
        guard let i = state.toActIndex else { throw Rejection.notYourTurn }
        let p = state.seats[i].id
        try apply(.act(player: p, action: action), by: p, at: t0)
    }
}

/// A save file in a fresh, not yet existing temporary directory.
func tempFile<V>(_ name: String = "save.json") -> SaveFile<V> {
    SaveFile(url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: name))
}

/// Makes the file's directory read-only (saving and deleting in it fail) or writable again.
func setReadOnly<V>(_ file: SaveFile<V>, _ readOnly: Bool) throws {
    try FileManager.default.setAttributes([.posixPermissions: readOnly ? 0o555 : 0o755],
                                          ofItemAtPath: file.url.deletingLastPathComponent().path)
}

struct TimeoutError: Error { var location: SourceLocation }

/// Waits until `condition` is true (at most `timeout`).
func eventually(timeout: Duration = .seconds(5), sourceLocation: SourceLocation = #_sourceLocation,
                _ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TimeoutError(location: sourceLocation)
}

/// Hosts a new table "Test" (Anna, code 4711, .relaxed) and waits for the first state.
@MainActor func hostSession(_ file: SaveFile<HostSnapshot> = tempFile()) async throws -> TableSession {
    let s = try await TableSession.host(
        .newTable(hostName: "Anna", tableName: "Test", code: code4711, config: .relaxed), saveFile: file)
    try await eventually { s.state != nil }
    return s
}

/// Joins `host` over loopback (host.port).
@MainActor func guestSession(_ host: TableSession, name: String = "Ben", token: String? = nil,
                             code: TableCode = code4711, ticketFile: SaveFile<SeatTicket> = tempFile()) async -> TableSession {
    await TableSession.join(endpoint: .hostPort(host: "127.0.0.1", port: host.port!), tableName: host.tableName,
                            code: code, name: name, token: token, ticketFile: ticketFile)
}
