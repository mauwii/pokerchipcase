import Foundation
import Network
import PokerCore

/// Server for one table: owns the snapshot, accepts connections, applies commands and broadcasts state.
///
/// iOS tears down listening sockets while an app is suspended. Call `ensureListening()` whenever the
/// app becomes active again; it restarts the listener on the same port if it has stopped.
public actor TableHost {
    public private(set) var snapshot: HostSnapshot
    private let onChange: @Sendable (HostSnapshot) -> Void
    private let queue = DispatchQueue(label: "pokernet.host")
    private var listener: NWListener?
    /// Port of the last successful start; nil after `stop()`.
    private var port: NWEndpoint.Port?
    private var channels: [UUID: MessageChannel] = [:]
    private var bound: [UUID: PlayerID] = [:]

    /// `onChange` receives every new snapshot; persist it to resume after a crash.
    public init(snapshot: HostSnapshot, onChange: @escaping @Sendable (HostSnapshot) -> Void = { _ in }) {
        self.snapshot = snapshot
        self.onChange = onChange
    }

    public var connectedPlayers: Set<PlayerID> { Set(bound.values) }

    public var isListening: Bool { listener != nil }

    /// Starts listening and returns the bound port.
    public func start(port: NWEndpoint.Port = .any) async throws -> NWEndpoint.Port {
        let listener = try NWListener(using: PSK.parameters(code: snapshot.code), on: port)
        listener.service = NWListener.Service(name: snapshot.tableName, type: Wire.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        let id = ObjectIdentifier(listener)
        self.listener = listener
        do {
            let bound = try await listener.startAndWaitUntilReady(queue: queue) { [weak self] in
                Task { await self?.listenerStopped(id) }
            }
            self.port = bound
            return bound
        } catch {
            listenerStopped(id)
            throw error
        }
    }

    /// Restarts the listener on its previous port if it has stopped (e.g. after the app was suspended).
    public func ensureListening() async throws {
        guard listener == nil, let port else { return }
        _ = try await start(port: port)
    }

    public func stop() {
        port = nil
        listener?.cancel()
        listener = nil
        disconnectAll()
    }

    func disconnectAll() {
        for channel in channels.values { channel.cancel() }
        channels = [:]
        bound = [:]
    }

    func simulateListenerFailure() {
        listener?.cancel()
    }

    private func listenerStopped(_ id: ObjectIdentifier) {
        if let listener, ObjectIdentifier(listener) == id { self.listener = nil }
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
        guard channels[id] != nil else { return }
        // Errors reuse the request's envelope id so the sender can match them to its command.
        let messageID: UUID
        let message: ClientMessage
        do {
            (messageID, message) = try Wire.decodeClient(data)
        } catch WireError.versionMismatch {
            return reject(.versionMismatch, id, replyTo: Wire.envelopeID(data))
        } catch {
            return send(.error(WireErrorCode.malformed.rawValue), to: id, envelopeID: Wire.envelopeID(data))
        }
        switch message {
        case let .hello(hello):
            welcome(hello, from: id, requestID: messageID)
        case let .command(request):
            handle(request, messageID: messageID, from: id)
        }
    }

    private func handle(_ request: CommandRequest, messageID: UUID, from id: UUID) {
        guard let player = bound[id] else {
            return send(.error(WireErrorCode.helloRequired.rawValue), to: id, envelopeID: messageID)
        }
        do {
            try snapshot.game.apply(request.command, by: player, at: Date(), expectedVersion: request.stateVersion)
        } catch {
            return send(.ack(Ack(id: messageID, result: .rejected(reason: error))), to: id)
        }
        forgetRemovedPlayers()
        // State before ack: when a client's send returns, it already knows the new state version.
        broadcastState()
        send(.ack(Ack(id: messageID, result: .ok)), to: id)
        onChange(snapshot)
    }

    /// Players without a seat (removed in the lobby, or their join was undone) lose their token and connection.
    private func forgetRemovedPlayers() {
        let seated = Set(snapshot.game.state.seats.map(\.id))
        snapshot.tokens = snapshot.tokens.filter { seated.contains($0.value) }
        for (id, player) in bound where !seated.contains(player) {
            reject(.removed, id, replyTo: nil)
        }
    }

    private func welcome(_ hello: Hello, from id: UUID, requestID: UUID?) {
        guard bound[id] == nil else {
            return send(.error(WireErrorCode.malformed.rawValue), to: id, envelopeID: requestID)
        }
        guard hello.protocolVersion == Wire.version else { return reject(.versionMismatch, id, replyTo: requestID) }
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
                return reject(.tableFull, id, replyTo: requestID)
            } catch {
                return reject(.gameInProgress, id, replyTo: requestID)
            }
            token = UUID().uuidString
            snapshot.tokens[token] = player
            onChange(snapshot)
        }
        bound[id] = player
        send(.welcome(Welcome(player: player, token: token)), to: id)
        broadcastState()
    }

    /// Sends a final error and closes the connection.
    private func reject(_ code: WireErrorCode, _ id: UUID, replyTo requestID: UUID?) {
        guard let data = try? Wire.encode(ServerMessage.error(code.rawValue), id: requestID ?? UUID()) else { return }
        channels[id]?.sendAndClose(data)
        drop(id)
    }

    private func send(_ message: ServerMessage, to id: UUID, envelopeID: UUID? = nil) {
        guard let data = try? Wire.encode(message, id: envelopeID ?? UUID()) else { return }
        channels[id]?.send(data)
    }

    private func broadcastState() {
        for id in bound.keys { send(.state(snapshot.game.state), to: id) }
    }
}

extension NWListener {
    /// Starts the listener and waits until it is ready. `onStopped` fires if it fails or is cancelled later.
    func startAndWaitUntilReady(
        queue: DispatchQueue, onStopped: @escaping @Sendable () -> Void = {}
    ) async throws -> NWEndpoint.Port {
        let (ready, continuation) = AsyncThrowingStream<NWEndpoint.Port, Error>.makeStream()
        stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.port { continuation.yield(port) }
                continuation.finish()
            case let .waiting(error):
                // E.g. the port is taken; treat as failure instead of hanging.
                continuation.finish(throwing: error)
                self?.cancel()
            case let .failed(error):
                continuation.finish(throwing: error)
                onStopped()
            case .cancelled:
                continuation.finish()
                onStopped()
            default:
                break
            }
        }
        start(queue: queue)
        for try await port in ready { return port }
        throw NWError.posix(.ECANCELED)
    }
}
