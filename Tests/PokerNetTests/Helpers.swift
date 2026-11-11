import Foundation
import Network
import PokerCore
@testable import PokerNet

struct TimeoutError: Error {}

/// Records a stream's events; `first(where:)` waits at most `timeout`.
actor EventRecorder<Event: Sendable> {
    private var events: [Event] = []
    private var end: (any Error)?? = nil

    /// Reads `stream` in its own task; works for AsyncStream and AsyncThrowingStream.
    init<S: AsyncSequence & Sendable>(_ stream: S) where S.Element == Event {
        Task {
            do {
                for try await e in stream { await self.append(e) }
                await self.finish(nil)
            } catch {
                await self.finish(error)
            }
        }
    }

    private func append(_ e: Event) { events.append(e) }
    private func finish(_ error: (any Error)?) { end = .some(error) }

    var all: [Event] { events }

    /// Like `first`, but removes the found event and all before it – "next event" semantics.
    func take(timeout: Duration = .seconds(5), where predicate: @Sendable (Event) -> Bool) async throws -> Event {
        let e = try await first(timeout: timeout, where: predicate)
        let i = events.firstIndex(where: predicate)!
        events.removeFirst(i + 1)
        return e
    }

    func first(timeout: Duration = .seconds(5), where predicate: @Sendable (Event) -> Bool) async throws -> Event {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let e = events.first(where: predicate) { return e }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TimeoutError()
    }

    /// Waits for the stream to end; returns the error it ended with (nil = finished cleanly).
    func waitForEnd(timeout: Duration = .seconds(5)) async throws -> (any Error)? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let end { return end }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TimeoutError()
    }
}

/// Waits until `condition` is true (at most `timeout`).
func eventually(timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TimeoutError()
}

let code4711 = TableCode("4711")!

extension ServerMessage {
    var welcome: Welcome? { if case let .welcome(w) = self { w } else { nil } }
    var state: GameState? { if case let .state(s) = self { s } else { nil } }
    var ack: Ack? { if case let .ack(a) = self { a } else { nil } }
    var error: String? { if case let .error(e) = self { e } else { nil } }
}

func hello(_ name: String, token: String? = nil, version: Int = Wire.version) -> ClientMessage {
    .hello(Hello(protocolVersion: version, name: name, token: token))
}

/// Raw protocol client without TableClient logic.
final class RawClient: Sendable {
    private let channel: MessageChannel
    private let recorder: EventRecorder<ChannelEvent>

    private init(channel: MessageChannel) {
        self.channel = channel
        recorder = EventRecorder(channel.events)
    }

    static func connect(_ port: NWEndpoint.Port, code: TableCode = code4711) async throws -> RawClient {
        let client = RawClient(channel: MessageChannel(to: loopback(port), code: code))
        client.channel.start()
        _ = try await client.recorder.first { $0 == .ready }
        return client
    }

    func send(_ message: ClientMessage, id: UUID = UUID()) {
        channel.send(try! Wire.encode(message, id: id))
    }

    func sendRaw(_ data: Data) { channel.send(data) }

    /// Next server message matching `predicate` (older ones are discarded).
    func next(where predicate: @escaping @Sendable (ServerMessage) -> Bool) async throws -> ServerMessage {
        let event = try await recorder.take {
            guard case let .message(d) = $0, let m = try? Wire.decodeServer(d).message else { return false }
            return predicate(m)
        }
        guard case let .message(d) = event else { throw TimeoutError() }
        return try Wire.decodeServer(d).message
    }

    func welcome() async throws -> Welcome { try await next { $0.welcome != nil }.welcome! }
    func ack() async throws -> Ack { try await next { $0.ack != nil }.ack! }
    func error() async throws -> String { try await next { $0.error != nil }.error! }
    func state(where predicate: @escaping @Sendable (GameState) -> Bool = { _ in true }) async throws -> GameState {
        try await next { $0.state.map(predicate) ?? false }.state!
    }

    func waitForClose() async throws { _ = try await recorder.waitForEnd() }
    func close() { channel.cancel() }
}

/// Starts a host with a new table "Anna" (or `snapshot`) on loopback.
func startHost(
    _ snapshot: HostSnapshot = .newTable(hostName: "Anna", config: .relaxed),
    port: NWEndpoint.Port = .any,
    onChange: @escaping @Sendable (HostSnapshot) -> Void = { _ in }
) async throws -> (TableHost, NWEndpoint.Port) {
    let host = TableHost(snapshot: snapshot, tableName: "Test", code: code4711, onChange: onChange)
    return (host, try await host.start(port: port))
}

func loopback(_ port: NWEndpoint.Port) -> NWEndpoint {
    .hostPort(host: "127.0.0.1", port: port)
}

/// NWListener with PSK parameters; every new connection becomes an echo channel.
func startEchoListener(code: TableCode) async throws -> (NWListener, NWEndpoint.Port) {
    let listener = try NWListener(using: PSK.parameters(code: code), on: .any)
    listener.newConnectionHandler = { connection in
        let channel = MessageChannel(connection: connection)
        Task {
            do {
                for try await event in channel.events {
                    if case let .message(data) = event { channel.send(data) }
                }
            } catch {}
        }
        channel.start()
    }
    return (listener, try await listener.startAndWaitUntilReady(queue: .global()))
}
