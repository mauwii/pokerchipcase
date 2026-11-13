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

/// A connection as a message stream: each message is one line terminated by `\n`.
/// The stream ends with the connection.
/// ponytail: @unchecked Sendable, `connection`, `buffer` and the flags are only touched on `queue`
final class MessageChannel: @unchecked Sendable {
    static let maxMessageSize = 1_048_576
    private static let newline = UInt8(ascii: "\n")

    let events: AsyncThrowingStream<ChannelEvent, Error>
    private let continuation: AsyncThrowingStream<ChannelEvent, Error>.Continuation
    private var connection: NWConnection
    private let queue = DispatchQueue(label: "pokernet.channel")
    private var buffer = Data()
    /// Set while `connection` only resolves a Bonjour service; the TLS connection to its address uses these.
    private var tlsAfterResolving: NWParameters?
    private var isReady = false
    private var isCancelled = false

    init(connection: NWConnection) {
        self.connection = connection
        (events, continuation) = AsyncThrowingStream.makeStream()
    }

    /// A `.service` endpoint is resolved over plain TCP first: on a service endpoint Network.framework
    /// retries a failed TLS handshake forever instead of reporting it, so a wrong code would never fail.
    convenience init(to endpoint: NWEndpoint, code: TableCode) {
        let tls = PSK.parameters(code: code)
        if case .service = endpoint {
            let tcp = NWParameters.tcp
            tcp.includePeerToPeer = true
            self.init(connection: NWConnection(to: endpoint, using: tcp))
            tlsAfterResolving = tls
        } else {
            self.init(connection: NWConnection(to: endpoint, using: tls))
        }
    }

    func start() {
        continuation.onTermination = { [self] _ in cancel() }
        run(connection)
    }

    /// Sends one message (must not contain a newline); failures surface as the end of the stream.
    func send(_ data: Data) {
        queue.async { [self] in connection.send(content: data + [Self.newline], completion: .idempotent) }
    }

    /// Sends a last message, then closes the connection gracefully.
    func sendAndClose(_ data: Data) {
        queue.async { [self] in
            connection.send(
                content: data + [Self.newline], contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { [connection] _ in connection.cancel() }
            )
        }
    }

    func cancel() {
        queue.async { [self] in
            isCancelled = true
            connection.cancel()
        }
    }

    private func run(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [self, weak connection] state in
            guard connection === self.connection else { return }  // a finished resolver
            switch state {
            case .ready:
                if let tls = tlsAfterResolving { return connectResolved(using: tls) }
                isReady = true
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
        connection.start(queue: queue)
    }

    /// The service resolved: connect again, with TLS, to the address it resolved to.
    private func connectResolved(using tls: NWParameters) {
        guard !isCancelled else { return }
        let resolver = connection
        guard let address = resolver.currentPath?.remoteEndpoint else { return fail(ChannelError.closed) }
        tlsAfterResolving = nil
        run(NWConnection(to: address, using: tls))
        resolver.cancel()
    }

    private func fail(_ error: Error) {
        continuation.finish(throwing: isHandshakeFailure(error) ? ChannelError.handshakeFailed : error)
        connection.cancel()
    }

    /// Before the TLS connection is ready, every failure except an unreachable host counts as a failed
    /// handshake, which with TLS-PSK means a wrong code. After `.ready` or while resolving, it is a drop.
    /// ponytail: a handshake aborted by the host's suspension also counts (#36); match the PSK alert if that bites.
    private func isHandshakeFailure(_ error: Error) -> Bool {
        guard !isReady, tlsAfterResolving == nil else { return false }
        switch error as? NWError {
        case .dns: return false
        case let .posix(code):
            return ![.ECONNREFUSED, .ETIMEDOUT, .EHOSTUNREACH, .EHOSTDOWN, .ENETUNREACH, .ENETDOWN].contains(code)
        default: return true
        }
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
