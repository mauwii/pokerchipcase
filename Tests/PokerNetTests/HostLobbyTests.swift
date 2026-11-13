import Foundation
import Network
import PokerCore
import Testing
@testable import PokerNet

/// Snapshot with `guests` additional players (IDs "G0"…).
private func snapshot(guests: Int, started: Bool = false) throws -> HostSnapshot {
    var snap = testSnapshot()
    let hostID = snap.game.state.hostID
    for i in 0..<guests {
        try snap.game.apply(.join(player: "G\(i)", name: "G\(i)"), by: hostID, at: .now)
    }
    if started { try snap.game.apply(.startTournament(button: hostID), by: hostID, at: .now) }
    return snap
}

@Suite(.timeLimit(.minutes(1)))
struct HostLobbyTests {
    @Test func helloJoinsLobbyAndBroadcastsState() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        let w = try await ben.welcome()
        let s = try await ben.state()
        #expect(s.seats.map(\.name) == ["Anna", "Ben"] && s.seat(w.player) != nil)
        #expect(await host.snapshot.tokens[w.token] == w.player)
        await host.stop()
    }

    @Test func hostTokenIdentifiesHost() async throws {
        let (host, port) = try await startHost()
        let anna = try await RawClient.connect(port)
        anna.send(hello("whatever", token: await host.snapshot.hostToken))
        let w = try await anna.welcome()
        #expect(w.player == (await host.snapshot.game.state.hostID))
        #expect(try await anna.state().seats.count == 1)
        await host.stop()
    }

    @Test func reconnectWithTokenKeepsSeat() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        let w = try await ben.welcome()
        ben.close()
        let again = try await RawClient.connect(port)
        again.send(hello("Ben", token: w.token))
        #expect(try await again.welcome().player == w.player)
        #expect(try await again.state().seats.count == 2)
        await host.stop()
    }

    @Test func unknownTokenJoinsAsNewPlayer() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben", token: "unknown"))
        _ = try await ben.welcome()
        #expect(try await ben.state().seats.count == 2)
        await host.stop()
    }

    @Test func secondConnectionWithSameTokenReplacesFirst() async throws {
        let (host, port) = try await startHost()
        let first = try await RawClient.connect(port)
        first.send(hello("Ben"))
        let w = try await first.welcome()
        let second = try await RawClient.connect(port)
        second.send(hello("Ben", token: w.token))
        _ = try await second.welcome()
        #expect(try await first.error() == WireErrorCode.replaced.rawValue)
        try await first.waitForClose()
        #expect(await host.connectedPlayers.contains(w.player))
        #expect(try await second.state().seats.count == 2)
        await host.stop()
    }

    @Test func connectionWithoutHelloIsClosedAfterTimeout() async throws {
        let (host, port) = try await startHost(helloTimeout: .milliseconds(300))
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        let w = try await ben.welcome()
        let silent = try await RawClient.connect(port)
        try await silent.waitForClose()
        // A bound connection outlives the timeout.
        let id = UUID()
        ben.send(hello("Ben"), id: id)
        #expect(try await ben.nextEnvelope { $0.error != nil }.id == id)
        #expect(await host.connectedPlayers == [w.player])
        await host.stop()
    }

    @Test func versionMismatchSendsErrorAndCloses() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.sendRaw(Data(#"{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Ben"},"type":"hello","v":2}"#.utf8))
        #expect(try await ben.error() == WireErrorCode.versionMismatch.rawValue)
        try await ben.waitForClose()
        await host.stop()
    }

    @Test func messagesAfterRejectionAreIgnored() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.sendRaw(Data(#"{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Ben"},"type":"hello","v":2}"#.utf8))
        ben.send(hello("Cem"))
        try await ben.waitForClose()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await host.snapshot.game.state.seats.map(\.name) == ["Anna"])
        await host.stop()
    }

    @Test func secondHelloIsMalformedAndDoesNotJoinAgain() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        let id = UUID()
        ben.send(hello("Ben"), id: id)
        let reply = try await ben.nextEnvelope { $0.error != nil }
        #expect(reply.message.error == WireErrorCode.malformed.rawValue && reply.id == id)
        #expect(await host.snapshot.game.state.seats.map(\.name) == ["Anna", "Ben"])
        await host.stop()
    }

    @Test func joinAfterStartRejected() async throws {
        let (host, port) = try await startHost(snapshot(guests: 1, started: true))
        let cem = try await RawClient.connect(port)
        cem.send(hello("Cem"))
        #expect(try await cem.error() == WireErrorCode.gameInProgress.rawValue)
        try await cem.waitForClose()
        await host.stop()
    }

    @Test func tableFullRejected() async throws {
        let (host, port) = try await startHost(snapshot(guests: 9))
        let cem = try await RawClient.connect(port)
        cem.send(hello("Cem"))
        #expect(try await cem.error() == WireErrorCode.tableFull.rawValue)
        try await cem.waitForClose()
        await host.stop()
    }

    @Test func disconnectedPlayerStaysSeated() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        let w = try await ben.welcome()
        try await eventually { await host.connectedPlayers.contains(w.player) }
        ben.close()
        try await eventually { await !host.connectedPlayers.contains(w.player) }
        #expect(await host.snapshot.game.state.seats.count == 2)
        await host.stop()
    }

    @Test func onChangeReceivesSnapshotAfterJoin() async throws {
        let inbox = Inbox()
        let (host, port) = try await startHost(onChange: { s in Task { await inbox.put(s) } })
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        try await eventually { await inbox.last?.tokens.count == 2 }
        #expect(await inbox.last?.game.state.seats.count == 2)
        await host.stop()
    }

    @Test func snapshotCarriesCodeAndTableName() async throws {
        let snap = HostSnapshot.newTable(hostName: "Anna", tableName: "Kitchen", code: TableCode("1234")!, config: .relaxed)
        let decoded = try Wire.decoder.decode(HostSnapshot.self, from: Wire.encoder.encode(snap))
        #expect(decoded == snap && decoded.tableName == "Kitchen" && decoded.code == TableCode("1234"))
        let (host, port) = try await startHost(decoded)
        let ben = try await RawClient.connect(port, code: TableCode("1234")!)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        await host.stop()
    }

    @Test func restoredHostKeepsTokens() async throws {
        let (host, port) = try await startHost()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        let w = try await ben.welcome()
        let snap = await host.snapshot
        await host.stop()

        let (restored, newPort) = try await startHost(snap)
        let again = try await RawClient.connect(newPort)
        again.send(hello("Ben", token: w.token))
        #expect(try await again.welcome().player == w.player)
        await restored.stop()
    }
}
