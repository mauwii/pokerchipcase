import Foundation
import Network

enum ChannelEvent: Equatable, Sendable {
    case ready
    case message(Data)
}

enum ChannelError: Error, Equatable {
    case handshakeFailed
    case closed
    case messageTooLarge
}

/// Eine Verbindung als Nachrichten-Stream: jede Nachricht ist eine Zeile, abgeschlossen mit `\n`.
/// Der Stream endet mit der Verbindung.
/// ponytail: @unchecked Sendable, NWConnection und `buffer` werden nur über `queue` angesprochen
final class MessageChannel: @unchecked Sendable {
    static let maxMessageSize = 1_048_576
    private static let newline = UInt8(ascii: "\n")

    let events: AsyncThrowingStream<ChannelEvent, Error>
    private let continuation: AsyncThrowingStream<ChannelEvent, Error>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "pokernet.channel")
    private var buffer = Data()

    init(connection: NWConnection) {
        self.connection = connection
        (events, continuation) = AsyncThrowingStream.makeStream()
    }

    convenience init(to endpoint: NWEndpoint, code: TableCode) {
        self.init(connection: NWConnection(to: endpoint, using: PSK.parameters(code: code)))
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                continuation.yield(.ready)
                receive()
            case let .waiting(error), let .failed(error):
                fail(error)
            case .cancelled:
                continuation.finish()
            default:
                break
            }
        }
        continuation.onTermination = { [connection] _ in connection.cancel() }
        connection.start(queue: queue)
    }

    /// Sendet eine Nachricht (ohne Zeilenumbruch darin); Fehler zeigen sich als Stream-Ende.
    func send(_ data: Data) {
        connection.send(content: data + [Self.newline], completion: .idempotent)
    }

    /// Sends a last message, then closes the connection gracefully.
    func sendAndClose(_ data: Data) {
        connection.send(
            content: data + [Self.newline], contentContext: .finalMessage, isComplete: true,
            completion: .contentProcessed { [connection] _ in connection.cancel() }
        )
    }

    func cancel() {
        connection.cancel()
    }

    private func fail(_ error: Error) {
        if case .tls = error as? NWError {
            continuation.finish(throwing: ChannelError.handshakeFailed)
        } else {
            continuation.finish(throwing: error)
        }
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            if let error { return fail(error) }
            if let data { buffer.append(data) }
            while let end = buffer.firstIndex(of: Self.newline) {
                let line = buffer[buffer.startIndex..<end]
                buffer = Data(buffer[(end + 1)...])
                if !line.isEmpty { continuation.yield(.message(Data(line))) }
            }
            if buffer.count > Self.maxMessageSize { return fail(ChannelError.messageTooLarge) }
            if isComplete { return fail(ChannelError.closed) }
            receive()
        }
    }
}
