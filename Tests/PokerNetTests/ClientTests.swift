import Foundation
import Network
import PokerCore
import Testing
@testable import PokerNet

extension ClientEvent {
    var welcome: Welcome? { if case let .welcome(w) = self { w } else { nil } }
    var state: GameState? { if case let .state(s) = self { s } else { nil } }
}

private func client(
    _ port: NWEndpoint.Port, name: String = "Ben", token: String? = nil, code: TableCode = code4711,
    ackTimeout: Duration = .seconds(10)
) async -> (TableClient, EventRecorder<ClientEvent>) {
    let client = TableClient(
        endpoint: loopback(port), code: code, name: name, token: token,
        retryDelay: .milliseconds(100), ackTimeout: ackTimeout
    )
    let recorder = EventRecorder(client.events)
    await client.connect()
    return (client, recorder)
}

/// Host with Anna (host device) and Ben connected, both having seen the 2-seat state.
private func table() async throws -> (TableHost, NWEndpoint.Port, TableClient, TableClient, EventRecorder<ClientEvent>) {
    let (host, port) = try await startHost()
    let (anna, annaEvents) = await client(port, name: "Anna", token: await host.snapshot.hostToken)
    _ = try await annaEvents.first { $0.welcome != nil }
    let (ben, benEvents) = await client(port)
    _ = try await benEvents.first { $0.state?.seats.count == 2 }
    _ = try await annaEvents.first { $0.state?.seats.count == 2 }
    return (host, port, anna, ben, benEvents)
}

/// Scripted host: answers `hello` with welcome + state unless `script` returns lines; never acks on its own.
private actor FakeHost {
    typealias Script = @Sendable (_ id: UUID, _ message: ClientMessage) -> (lines: [Data], close: Bool)
    private var channels: [MessageChannel] = []
    private let script: Script
    let listener: NWListener
    private(set) var hellos = 0

    init(script: @escaping Script = { _, _ in ([], false) }) throws {
        self.script = script
        listener = try NWListener(using: PSK.parameters(code: code4711), on: .any)
    }

    func start() async throws -> NWEndpoint.Port {
        listener.newConnectionHandler = { [weak self] connection in Task { await self?.accept(connection) } }
        return try await listener.startAndWaitUntilReady(queue: .global())
    }

    private func accept(_ connection: NWConnection) {
        let channel = MessageChannel(connection: connection)
        channels.append(channel)
        Task {
            do {
                for try await event in channel.events {
                    guard case let .message(data) = event else { continue }
                    let (id, message) = try Wire.decodeClient(data)
                    try self.respond(id, message, on: channel)
                }
            } catch {}
        }
        channel.start()
    }

    private func respond(_ id: UUID, _ message: ClientMessage, on channel: MessageChannel) throws {
        if case .hello = message { hellos += 1 }
        var (lines, close) = script(id, message)
        if lines.isEmpty, case .hello = message {
            lines = [
                try Wire.encode(ServerMessage.welcome(Welcome(player: "B", token: "t")), id: UUID()),
                try Wire.encode(ServerMessage.state(testSnapshot().game.state), id: UUID()),
            ]
        }
        for (i, line) in lines.enumerated() {
            if close && i == lines.count - 1 { channel.sendAndClose(line) } else { channel.send(line) }
        }
    }

    func dropAll() {
        channels.forEach { $0.cancel() }
        listener.cancel()
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ClientTests {
    @Test func clientJoinsAndReceivesState() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port)
        _ = try await events.first { $0.welcome != nil }
        _ = try await events.first { $0.state?.seats.count == 2 }
        #expect(await ben.token != nil)
        await ben.disconnect()
        await host.stop()
    }

    @Test func hostDeviceStartsTournament() async throws {
        let (host, _, anna, ben, benEvents) = try await table()
        let hostID = await host.snapshot.game.state.hostID
        #expect(try await anna.send(.startTournament(button: hostID)) == .ok)
        _ = try await benEvents.first { $0.state?.phase == .betting }
        await anna.disconnect(); await ben.disconnect(); await host.stop()
    }

    @Test func sendReturnsRejection() async throws {
        let (host, _, anna, ben, _) = try await table()
        let hostID = await host.snapshot.game.state.hostID
        #expect(try await ben.send(.startTournament(button: hostID)) == .rejected(reason: .notHost))
        await anna.disconnect(); await ben.disconnect(); await host.stop()
    }

    @Test func sendUsesLatestStateVersion() async throws {
        let (host, _, anna, ben, _) = try await table()
        let hostID = await host.snapshot.game.state.hostID
        #expect(try await anna.send(.startTournament(button: hostID)) == .ok)
        #expect(try await anna.send(.pauseClock) == .ok)
        await anna.disconnect(); await ben.disconnect(); await host.stop()
    }

    @Test func sendWhileDisconnectedThrows() async throws {
        let ben = TableClient(endpoint: loopback(1), code: code4711, name: "Ben")
        await #expect(throws: ClientError.notConnected) { try await ben.send(.startNextHand) }
    }

    @Test func wrongCodeFailsWithoutRetry() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port, code: TableCode("0815")!)
        _ = try await events.first { $0 == .failed(.wrongCode) }
        try await Task.sleep(for: .milliseconds(500))
        #expect(await events.all == [.failed(.wrongCode)])
        await ben.disconnect()
        await host.stop()
    }

    @Test func gameInProgressFails() async throws {
        let (host, port, anna, ben, _) = try await table()
        let hostID = await host.snapshot.game.state.hostID
        #expect(try await anna.send(.startTournament(button: hostID)) == .ok)
        let (cem, events) = await client(port, name: "Cem")
        _ = try await events.first { $0 == .failed(.gameInProgress) }
        await cem.disconnect(); await anna.disconnect(); await ben.disconnect(); await host.stop()
    }

    @Test func reconnectsAfterConnectionDrop() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port)
        let first = try await events.first { $0.welcome != nil }.welcome!
        await host.disconnectAll()
        _ = try await events.first { $0 == .connectionLost }
        try await eventually { await events.all.compactMap(\.welcome).count == 2 }
        #expect(await events.all.compactMap(\.welcome).last?.player == first.player)
        await ben.disconnect()
        await host.stop()
    }

    @Test func clientReconnectsAfterHostRestart() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port)
        let first = try await events.first { $0.welcome != nil }.welcome!
        _ = try await events.first { $0.state?.seats.count == 2 }
        let snapshot = await host.snapshot
        await host.stop()
        _ = try await events.first { $0 == .connectionLost }

        let (restarted, _) = try await startHost(snapshot, port: port)
        try await eventually { await events.all.compactMap(\.welcome).count == 2 }
        #expect(await events.all.compactMap(\.welcome).last?.player == first.player)
        #expect(await ben.lastState?.seats.count == 2)
        await ben.disconnect()
        await restarted.stop()
    }

    @Test func pendingSendThrowsOnConnectionLoss() async throws {
        let silent = try FakeHost()
        let port = try await silent.start()
        let (ben, events) = await client(port)
        _ = try await events.first { $0.state != nil }
        let pendingSend = Task { try await ben.send(.startNextHand) }
        try await Task.sleep(for: .milliseconds(100))
        await silent.dropAll()
        await #expect(throws: ClientError.connectionLost) { try await pendingSend.value }
        await ben.disconnect()
    }

    @Test func hostErrorFailsPendingSend() async throws {
        let fake = try FakeHost { id, message in
            guard case .command = message else { return ([], false) }
            return ([try! Wire.encode(ServerMessage.error(WireErrorCode.malformed.rawValue), id: id)], false)
        }
        let port = try await fake.start()
        let (ben, events) = await client(port)
        _ = try await events.first { $0.state != nil }
        await #expect(throws: ClientError.hostError("malformed")) { try await ben.send(.startNextHand) }
        await ben.disconnect()
        await fake.dropAll()
    }

    @Test func newerHostVersionFailsWithoutRetry() async throws {
        let fake = try FakeHost { _, message in
            guard case .hello = message else { return ([], false) }
            let line = #"{"id":"00000000-0000-0000-0000-000000000001","payload":"versionMismatch","type":"error","v":2}"#
            return ([Data(line.utf8)], true)
        }
        let port = try await fake.start()
        let (ben, events) = await client(port)
        _ = try await events.first { $0 == .failed(.versionMismatch) }
        try await Task.sleep(for: .milliseconds(500))
        #expect(await fake.hellos == 1)
        await ben.disconnect()
        await fake.dropAll()
    }

    @Test func secondDeviceWithTheSameTokenEndsTheFirst() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port)
        let w = try await events.first { $0.welcome != nil }.welcome!
        let (ben2, events2) = await client(port, token: w.token)
        _ = try await events2.first { $0.welcome?.player == w.player }
        _ = try await events.first { $0 == .failed(.replaced) }
        #expect(await events.all.compactMap(\.welcome).count == 1)
        #expect(await host.connectedPlayers == [w.player])
        #expect(!(await events2.all.contains(.connectionLost)))
        await ben.disconnect(); await ben2.disconnect(); await host.stop()
    }

    /// A host from before a wire change answers `hello` with `malformed` and keeps the connection open (#53).
    @Test func errorBeforeWelcomeFailsWithoutRetry() async throws {
        let fake = try FakeHost { id, message in
            guard case .hello = message else { return ([], false) }
            return ([try! Wire.encode(ServerMessage.error(WireErrorCode.malformed.rawValue), id: id)], false)
        }
        let port = try await fake.start()
        let (ben, events) = await client(port)
        #expect(try await events.waitForEnd() == nil)
        #expect(await events.all == [.failed(.versionMismatch)])
        await ben.disconnect()
        await fake.dropAll()
    }

    @Test func removedPlayerFails() async throws {
        let (host, _, anna, ben, benEvents) = try await table()
        let benID = try await benEvents.first { $0.welcome != nil }.welcome!.player
        #expect(try await anna.send(.removePlayer(player: benID)) == .ok)
        _ = try await benEvents.first { $0 == .failed(.removed) }
        await anna.disconnect(); await ben.disconnect(); await host.stop()
    }

    @Test func hostEndingTheTableFailsWithoutRetry() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port)
        _ = try await events.first { $0.welcome != nil }
        await host.end()
        _ = try await events.first { $0 == .failed(.tableClosed) }
        #expect(try await events.waitForEnd() == nil)
        #expect(!(await events.all.contains(.connectionLost)))
        #expect(await !host.isListening)
        await ben.disconnect()
    }

    @Test func eventsFinishAfterFailure() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port, code: TableCode("0815")!)
        #expect(try await events.waitForEnd() == nil)
        await ben.disconnect()
        await host.stop()
    }

    @Test func sendTimesOutWithoutAckAndReconnects() async throws {
        let fake = try FakeHost()
        let port = try await fake.start()
        let (ben, events) = await client(port, ackTimeout: .milliseconds(300))
        _ = try await events.first { $0.state != nil }
        await #expect(throws: ClientError.connectionLost) { try await ben.send(.startNextHand) }
        _ = try await events.first { $0 == .connectionLost }
        try await eventually { await fake.hellos == 2 }
        await ben.disconnect()
        await fake.dropAll()
    }

    @Test func disconnectStopsRetrying() async throws {
        let (host, port) = try await startHost()
        let (ben, events) = await client(port)
        _ = try await events.first { $0.welcome != nil }
        await ben.disconnect()
        await host.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await events.all.compactMap(\.welcome).count == 1)
        #expect(!(await events.all.contains(.connectionLost)))
    }

    @Test func eventsFinishWhenTheClientIsReleased() async throws {
        var ben: TableClient? = TableClient(endpoint: loopback(1), code: code4711, name: "Ben")
        let events = EventRecorder(ben!.events)
        ben = nil
        #expect(try await events.waitForEnd() == nil)
    }

    @Test func releasedClientClosesItsConnection() async throws {
        let (host, port) = try await startHost()
        var ben: TableClient? = TableClient(endpoint: loopback(port), code: code4711, name: "Ben")
        await ben?.connect()
        try await eventually { await host.connectedPlayers.count == 1 }
        ben = nil
        try await eventually { await host.connectedPlayers.isEmpty }
        await host.stop()
    }
}
