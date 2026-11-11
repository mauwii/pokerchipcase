import Foundation
import Network
import PokerCore

public enum ClientEvent: Equatable, Sendable {
    case welcome(Welcome)
    case state(GameState)
    /// The connection dropped; the client keeps retrying by itself.
    case connectionLost
    /// Final: the client gave up.
    case failed(ClientFailure)
}

public enum ClientFailure: Equatable, Sendable {
    case wrongCode, versionMismatch, tableFull, gameInProgress
}

public enum ClientError: Error, Equatable {
    case notConnected, connectionLost
}

/// Connection to a table host: sends commands, waits for their ack and reconnects after drops.
public actor TableClient {
    public nonisolated let events: AsyncStream<ClientEvent>
    public private(set) var token: String?
    public private(set) var lastState: GameState?

    private let continuation: AsyncStream<ClientEvent>.Continuation
    private let endpoint: NWEndpoint
    private let code: TableCode
    private let name: String
    private let retryDelay: Duration
    private var channel: MessageChannel?
    private var connected = false
    private var running = false
    /// Bumped for every new connection attempt and on disconnect, so stale channel callbacks are ignored.
    private var generation = 0
    private var pending: [UUID: CheckedContinuation<AckResult, Error>] = [:]

    public init(endpoint: NWEndpoint, code: TableCode, name: String, token: String? = nil,
                retryDelay: Duration = .seconds(1)) {
        self.endpoint = endpoint
        self.code = code
        self.name = name
        self.token = token
        self.retryDelay = retryDelay
        (events, continuation) = AsyncStream.makeStream()
    }

    public func connect() {
        guard !running else { return }
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
            let hello = ClientMessage.hello(Hello(protocolVersion: Wire.version, name: name, token: token))
            if let data = try? Wire.encode(hello, id: UUID()) { channel?.send(data) }
        case let .message(data):
            guard let (_, message) = try? Wire.decodeServer(data) else { return }
            receive(message)
        }
    }

    private func receive(_ message: ServerMessage) {
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
            switch WireErrorCode(rawValue: code) {
            case .versionMismatch: fail(.versionMismatch)
            case .tableFull: fail(.tableFull)
            case .gameInProgress: fail(.gameInProgress)
            default: break
            }
        }
    }

    private func channelEnded(_ error: Error?, attempt: Int) async {
        guard attempt == generation, running else { return }
        let wasConnected = connected
        dropChannel()
        if error as? ChannelError == .handshakeFailed { return fail(.wrongCode) }
        if wasConnected { continuation.yield(.connectionLost) }
        try? await Task.sleep(for: retryDelay)
        guard running, attempt == generation else { return }
        open()
    }

    private func fail(_ failure: ClientFailure) {
        running = false
        generation += 1
        dropChannel()
        continuation.yield(.failed(failure))
    }

    private func dropChannel() {
        connected = false
        channel?.cancel()
        channel = nil
        for waiting in pending.values { waiting.resume(throwing: ClientError.connectionLost) }
        pending = [:]
    }
}
