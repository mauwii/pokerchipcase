import Foundation
import Network
@testable import PokerNet

struct TimeoutError: Error {}

/// Sammelt Ereignisse eines Streams; `first(where:)` wartet höchstens `timeout`.
actor EventRecorder<Event: Sendable> {
    private var events: [Event] = []
    private var end: (any Error)?? = nil

    /// Liest `stream` in einem eigenen Task mit; funktioniert für AsyncStream und AsyncThrowingStream.
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

    func first(timeout: Duration = .seconds(5), where predicate: @Sendable (Event) -> Bool) async throws -> Event {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let e = events.first(where: predicate) { return e }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TimeoutError()
    }

    /// Wartet auf das Stream-Ende; liefert den Fehler, mit dem er endete (nil = sauber beendet).
    func waitForEnd(timeout: Duration = .seconds(5)) async throws -> (any Error)? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let end { return end }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TimeoutError()
    }
}

func loopback(_ port: NWEndpoint.Port) -> NWEndpoint {
    .hostPort(host: "127.0.0.1", port: port)
}

/// Wartet, bis der Listener bereit ist, und liefert seinen Port.
func waitReady(_ listener: NWListener) async throws -> NWEndpoint.Port {
    let (stream, cont) = AsyncThrowingStream<NWEndpoint.Port, Error>.makeStream()
    listener.stateUpdateHandler = { state in
        switch state {
        case .ready: cont.yield(listener.port!); cont.finish()
        case let .failed(e): cont.finish(throwing: e)
        default: break
        }
    }
    listener.start(queue: .global())
    for try await port in stream { return port }
    throw TimeoutError()
}

/// NWListener mit PSK-Parametern; jede neue Verbindung wird zum Echo-Kanal.
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
    return (listener, try await waitReady(listener))
}
