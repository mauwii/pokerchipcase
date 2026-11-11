import Foundation
import Network
import PokerCore

/// Server for one table: owns the snapshot, accepts connections, applies commands and broadcasts state.
public actor TableHost {
    public private(set) var snapshot: HostSnapshot
    private let tableName: String
    private let code: TableCode
    private let onChange: @Sendable (HostSnapshot) -> Void
    private let queue = DispatchQueue(label: "pokernet.host")
    private var listener: NWListener?
    private var channels: [UUID: MessageChannel] = [:]
    private var bound: [UUID: PlayerID] = [:]

    public init(
        snapshot: HostSnapshot,
        tableName: String,
        code: TableCode,
        onChange: @escaping @Sendable (HostSnapshot) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.tableName = tableName
        self.code = code
        self.onChange = onChange
    }

    public var connectedPlayers: Set<PlayerID> { Set(bound.values) }

    /// Starts listening and returns the bound port.
    public func start(port: NWEndpoint.Port = .any) async throws -> NWEndpoint.Port {
        let listener = try NWListener(using: PSK.parameters(code: code), on: port)
        listener.service = NWListener.Service(name: tableName, type: Wire.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        self.listener = listener
        return try await listener.startAndWaitUntilReady(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        disconnectAll()
    }

    func disconnectAll() {
        for channel in channels.values { channel.cancel() }
        channels = [:]
        bound = [:]
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let channel = MessageChannel(connection: connection)
        channels[id] = channel
        Task { [weak self] in
            do {
                for try await event in channel.events {
                    if case let .message(data) = event { await self?.receive(data, from: id) }
                }
            } catch {}
            await self?.drop(id)
        }
        channel.start()
    }

    private func drop(_ id: UUID) {
        channels[id] = nil
        bound[id] = nil
    }

    private func receive(_ data: Data, from id: UUID) {
        let messageID: UUID
        let message: ClientMessage
        do {
            (messageID, message) = try Wire.decodeClient(data)
        } catch WireError.versionMismatch {
            return reject(.versionMismatch, id)
        } catch {
            return send(.error(WireErrorCode.malformed.rawValue), to: id)
        }
        switch message {
        case let .hello(hello):
            welcome(hello, from: id)
        case let .command(request):
            handle(request, messageID: messageID, from: id)
        }
    }

    private func handle(_ request: CommandRequest, messageID: UUID, from id: UUID) {
        guard let player = bound[id] else {
            return send(.error(WireErrorCode.helloRequired.rawValue), to: id)
        }
        do {
            try snapshot.game.apply(request.command, by: player, at: Date(), expectedVersion: request.stateVersion)
        } catch {
            return send(.ack(Ack(id: messageID, result: .rejected(reason: error))), to: id)
        }
        // State before ack: when a client's send returns, it already knows the new state version.
        broadcastState()
        send(.ack(Ack(id: messageID, result: .ok)), to: id)
        onChange(snapshot)
    }

    private func welcome(_ hello: Hello, from id: UUID) {
        guard hello.protocolVersion == Wire.version else { return reject(.versionMismatch, id) }
        let player: PlayerID
        let token: String
        if let t = hello.token, let p = snapshot.tokens[t] {
            player = p
            token = t
            // The newest connection for a player wins; the old one is probably dead.
            for (other, q) in bound where q == p && other != id {
                channels[other]?.cancel()
                drop(other)
            }
        } else {
            player = UUID().uuidString
            do {
                try snapshot.game.apply(.join(player: player, name: hello.name), by: snapshot.game.state.hostID, at: Date())
            } catch .tableFull {
                return reject(.tableFull, id)
            } catch {
                return reject(.gameInProgress, id)
            }
            token = UUID().uuidString
            snapshot.tokens[token] = player
            onChange(snapshot)
        }
        bound[id] = player
        send(.welcome(Welcome(player: player, token: token)), to: id)
        broadcastState()
    }

    private func reject(_ code: WireErrorCode, _ id: UUID) {
        guard let data = try? Wire.encode(ServerMessage.error(code.rawValue), id: UUID()) else { return }
        channels[id]?.sendAndClose(data)
        drop(id)
    }

    private func send(_ message: ServerMessage, to id: UUID) {
        guard let data = try? Wire.encode(message, id: UUID()) else { return }
        channels[id]?.send(data)
    }

    private func broadcastState() {
        for id in bound.keys { send(.state(snapshot.game.state), to: id) }
    }
}

extension NWListener {
    /// Starts the listener and waits until it is ready.
    func startAndWaitUntilReady(queue: DispatchQueue) async throws -> NWEndpoint.Port {
        let (ready, continuation) = AsyncThrowingStream<NWEndpoint.Port, Error>.makeStream()
        stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.port { continuation.yield(port) }
                continuation.finish()
            case let .failed(error):
                continuation.finish(throwing: error)
            case .cancelled:
                continuation.finish()
            default:
                break
            }
        }
        start(queue: queue)
        for try await port in ready { return port }
        throw NWError.posix(.ECANCELED)
    }
}
