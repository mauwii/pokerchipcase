import Foundation
import Network
import PokerCore

/// Something a ``TableClient`` reports on its `events` stream.
public enum ClientEvent: Equatable, Sendable {
    case welcome(Welcome)
    case state(GameState)
    /// The connection dropped; the client keeps retrying by itself.
    case connectionLost
    /// Final: the client gave up and `events` finishes.
    case failed(ClientFailure)
}

/// Why a ``TableClient`` gave up for good.
public enum ClientFailure: Equatable, Sendable {
    case wrongCode, versionMismatch, tableFull, gameInProgress, removed, tableClosed
    /// Another connection took this seat with the same token (e.g. the player's second device).
    case replaced
}

/// Why sending a command through a ``TableClient`` failed.
public enum ClientError: Error, Equatable {
    case notConnected, connectionLost
    /// The host answered the command with an `error` code instead of an ack.
    case hostError(String)
}

/// Connection to a table host: sends commands, waits for their ack and reconnects after drops.
/// After `.failed` the client is done; create a new one to try again.
public actor TableClient {
    public nonisolated let events: AsyncStream<ClientEvent>
    public private(set) var token: String?
    public private(set) var lastState: GameState?

    private let continuation: AsyncStream<ClientEvent>.Continuation
    private let endpoint: NWEndpoint
    private let code: TableCode
    private let name: String
    private let retryDelay: Duration
    private let ackTimeout: Duration
    private var channel: MessageChannel?
    private var connected = false
    private var running = false
    private var gaveUp = false
    /// Bumped for every new connection attempt and on disconnect, so stale channel callbacks are ignored.
    private var generation = 0
    private var pending: [UUID: CheckedContinuation<AckResult, Error>] = [:]

    /// `ackTimeout`: how long `send` waits before treating the connection as dead and reconnecting.
    public init(endpoint: NWEndpoint, code: TableCode, name: String, token: String? = nil,
                retryDelay: Duration = .seconds(1), ackTimeout: Duration = .seconds(10)) {
        self.endpoint = endpoint
        self.code = code
        self.name = name
        self.token = token
        self.retryDelay = retryDelay
        self.ackTimeout = ackTimeout
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        channel?.cancel()
        continuation.finish()
    }

    public func connect() {
        guard !running, !gaveUp else { return }
        running = true
        open()
    }

    public func disconnect() {
        running = false
        generation += 1
        dropChannel()
    }

    /// Sends a command based on the last state seen and returns the host's verdict.
    public func send(_ command: Command) async throws -> AckResult {
        guard connected, let channel else { throw ClientError.notConnected }
        let id = UUID()
        let request = CommandRequest(command: command, stateVersion: lastState?.version ?? 0)
        let data = try Wire.encode(ClientMessage.command(request), id: id)
        Task { [weak self, ackTimeout] in
            try? await Task.sleep(for: ackTimeout)
            await self?.ackTimedOut(id)
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            channel.send(data)
        }
    }

    private func open() {
        generation += 1
        let attempt = generation
        let channel = MessageChannel(to: endpoint, code: code)
        self.channel = channel
        Task { [weak self] in
            var failure: Error?
            do {
                for try await event in channel.events {
                    await self?.handle(event, attempt: attempt)
                }
            } catch {
                failure = error
            }
            await self?.channelEnded(failure, attempt: attempt)
        }
        channel.start()
    }

    private func handle(_ event: ChannelEvent, attempt: Int) {
        guard attempt == generation else { return }
        switch event {
        case .ready:
            let hello = ClientMessage.hello(Hello(name: name, token: token))
            if let data = try? Wire.encode(hello, id: UUID()) { channel?.send(data) }
        case let .message(data):
            do {
                let (id, message) = try Wire.decodeServer(data)
                receive(message, id: id)
            } catch WireError.versionMismatch {
                fail(.versionMismatch)
            } catch {
                // Skips a message this client cannot decode; the next one may be fine.
            }
        }
    }

    private func receive(_ message: ServerMessage, id: UUID) {
        switch message {
        case let .welcome(welcome):
            token = welcome.token
            connected = true
            continuation.yield(.welcome(welcome))
        case let .state(state):
            lastState = state
            continuation.yield(.state(state))
        case let .ack(ack):
            pending.removeValue(forKey: ack.id)?.resume(returning: ack.result)
        case let .error(code):
            pending.removeValue(forKey: id)?.resume(throwing: ClientError.hostError(code))
            switch WireErrorCode(rawValue: code) {
            case .versionMismatch: fail(.versionMismatch)
            case .tableFull: fail(.tableFull)
            case .gameInProgress: fail(.gameInProgress)
            case .removed: fail(.removed)
            case .tableClosed: fail(.tableClosed)
            case .replaced: fail(.replaced)
            // An error answering `hello` that is not one of the above: a host that cannot read this client
            // (e.g. an older protocol answering `malformed`). Waiting would hang at "Connecting…".
            default: if !connected { fail(.versionMismatch) }
            }
        }
    }

    private func channelEnded(_ error: Error?, attempt: Int) async {
        guard attempt == generation, running else { return }
        if error as? ChannelError == .handshakeFailed { return fail(.wrongCode) }
        await reconnect()
    }

    private func ackTimedOut(_ id: UUID) async {
        guard pending[id] != nil, running else { return }
        await reconnect()
    }

    /// Drops the current connection (failing pending sends) and opens a new one after `retryDelay`.
    private func reconnect() async {
        let wasConnected = connected
        generation += 1
        let attempt = generation
        dropChannel()
        if wasConnected { continuation.yield(.connectionLost) }
        try? await Task.sleep(for: retryDelay)
        guard running, attempt == generation else { return }
        open()
    }

    private func fail(_ failure: ClientFailure) {
        running = false
        gaveUp = true
        generation += 1
        dropChannel()
        continuation.yield(.failed(failure))
        continuation.finish()
    }

    private func dropChannel() {
        connected = false
        channel?.cancel()
        channel = nil
        for waiting in pending.values { waiting.resume(throwing: ClientError.connectionLost) }
        pending = [:]
    }
}
