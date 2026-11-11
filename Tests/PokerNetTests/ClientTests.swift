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
    _ port: NWEndpoint.Port, name: String = "Ben", token: String? = nil, code: TableCode = code4711
) async -> (TableClient, EventRecorder<ClientEvent>) {
    let client = TableClient(endpoint: loopback(port), code: code, name: name, token: token, retryDelay: .milliseconds(100))
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

/// Accepts connections, answers `hello` with welcome + state, never acks; `dropAll()` closes everything.
private actor SilentHost {
    private var channels: [MessageChannel] = []
    let listener: NWListener

    init() throws { listener = try NWListener(using: PSK.parameters(code: code4711), on: .any) }

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
                    guard case let .message(data) = event, case .hello = try Wire.decodeClient(data).message else { continue }
                    channel.send(try Wire.encode(ServerMessage.welcome(Welcome(player: "B", token: "t")), id: UUID()))
                    let state = testSnapshot().game.state
                    channel.send(try Wire.encode(ServerMessage.state(state), id: UUID()))
                }
            } catch {}
        }
        channel.start()
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
        let silent = try SilentHost()
        let port = try await silent.start()
        let (ben, events) = await client(port)
        _ = try await events.first { $0.state != nil }
        let pendingSend = Task { try await ben.send(.startNextHand) }
        try await Task.sleep(for: .milliseconds(100))
        await silent.dropAll()
        await #expect(throws: ClientError.connectionLost) { try await pendingSend.value }
        await ben.disconnect()
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
}
