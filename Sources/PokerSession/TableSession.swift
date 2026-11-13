import Foundation
import Network
import Observation
import PokerCore
import PokerNet

/// A local operation that failed; `message` is the error's `localizedDescription`.
public struct SessionProblem: Equatable, Sendable {
    public enum Action: Sendable { case save, delete, send, listen }
    public var action: Action
    public var message: String
}

public enum ConnectionStatus: Equatable, Sendable { case connecting, connected, reconnecting, failed(ClientFailure) }

/// One device's seat at a table: the host device runs the `TableHost` and joins it over loopback,
/// a guest only has a `TableClient`. The app reads the state from here and sends commands through it.
@MainActor @Observable public final class TableSession {
    public let tableName: String
    public let code: TableCode
    public private(set) var state: GameState?
    public private(set) var me: PlayerID?
    public private(set) var connection: ConnectionStatus = .connecting
    public private(set) var isSending = false
    /// Reason of the last rejected command; cleared by the next `state` and by `send`.
    public private(set) var rejection: Rejection?
    /// Last failed save, delete, send or listener restart; cleared when that action works again
    /// (`.send`: by the next `send`).
    public private(set) var problem: SessionProblem?

    /// This device runs the `TableHost`.
    public var isHost: Bool { tableHost != nil }

    /// me's legal actions; nil when it is not my turn.
    public var legalActions: LegalActions? { me.flatMap { state?.legalActions(for: $0) } }

    /// Dealer of the hand or host: may resolve the showdown and start the next hand.
    public var canRunHand: Bool { isHost || (me != nil && me == state?.dealerID) }

    let client: TableClient
    private(set) var tableHost: TableHost?
    private(set) var port: NWEndpoint.Port?
    private let name: String
    private let saveFile: SaveFile<HostSnapshot>?
    private let ticketFile: SaveFile<SeatTicket>?
    /// Started from the stored ticket's token, so a failure may delete that ticket.
    private let fromTicket: Bool
    private var eventTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    private init(tableName: String, code: TableCode, name: String, client: TableClient, tableHost: TableHost?,
                 port: NWEndpoint.Port?, saveFile: SaveFile<HostSnapshot>?, ticketFile: SaveFile<SeatTicket>?,
                 fromTicket: Bool = false) {
        self.tableName = tableName
        self.code = code
        self.name = name
        self.client = client
        self.tableHost = tableHost
        self.port = port
        self.saveFile = saveFile
        self.ticketFile = ticketFile
        self.fromTicket = fromTicket
    }

    /// Hosts `snapshot` (new or resumed) and joins it over loopback with the host token.
    public static func host(_ snapshot: HostSnapshot, saveFile: SaveFile<HostSnapshot> = .host,
                            port: NWEndpoint.Port = .any) async throws -> TableSession {
        guard let token = snapshot.hostToken, let name = snapshot.game.state.seat(snapshot.game.state.hostID)?.name
        else { throw CocoaError(.fileReadCorruptFile) }
        // Saved before anything else, so a crash in the lobby is resumable too.
        let previous = saveFile.load()
        try saveFile.save(snapshot)
        // Save results go to the session's `problem`; the host calls onChange on its own actor.
        let (saves, saved) = AsyncStream<(any Error)?>.makeStream()
        let host = TableHost(snapshot: snapshot, onChange: {
            do { try saveFile.save($0); saved.yield(nil) } catch { saved.yield(error) }
        })
        let bound: NWEndpoint.Port
        do { bound = try await host.start(port: port) } catch {
            // The table never opened: put the old save back (or remove the new one).
            if let previous { try? saveFile.save(previous) } else { try? saveFile.delete() }
            throw error
        }
        let client = TableClient(endpoint: .hostPort(host: "127.0.0.1", port: bound), code: snapshot.code,
                                 name: name, token: token)
        let session = TableSession(tableName: snapshot.tableName, code: snapshot.code, name: name, client: client,
                                   tableHost: host, port: bound, saveFile: saveFile, ticketFile: nil)
        session.saveTask = Task { [weak session] in
            for await error in saves { session?.record(.save, error) }
        }
        await session.start()
        return session
    }

    public static func join(endpoint: NWEndpoint, tableName: String, code: TableCode, name: String,
                            token: String? = nil, ticketFile: SaveFile<SeatTicket> = .seat) async -> TableSession {
        let client = TableClient(endpoint: endpoint, code: code, name: name, token: token)
        let session = TableSession(tableName: tableName, code: code, name: name, client: client,
                                   tableHost: nil, port: nil, saveFile: nil, ticketFile: ticketFile,
                                   fromTicket: token != nil)
        await session.start()
        return session
    }

    public func send(_ command: Command) async {
        guard !isSending else { return }  // double tap
        isSending = true
        rejection = nil
        record(.send, nil)
        defer { isSending = false }
        do {
            if case let .rejected(reason) = try await client.send(command) { rejection = reason }
        } catch {
            record(.send, error)
        }
    }

    public func act(_ action: Action) async {
        guard let me else { return }
        await send(.act(player: me, action: action))
    }

    /// Call when the scene becomes active: restarts the host listener iOS tore down.
    public func appBecameActive() async {
        // ponytail: if the old port is taken the table stays unreachable; restart on .any + new loopback client if that happens in practice
        do {
            try await tableHost?.ensureListening()
            record(.listen, nil)
        } catch {
            record(.listen, error)
        }
    }

    /// Disconnects; the host also ends the table for everyone. Deletes this device's save file and
    /// returns false if that failed (`problem` says why; calling `leave()` again retries).
    @discardableResult public func leave() async -> Bool {
        eventTask?.cancel()
        saveTask?.cancel()
        await client.disconnect()
        await tableHost?.end()
        return record(.delete) { try saveFile?.delete(); try ticketFile?.delete() }
    }

    /// Sets `problem` for a failed `action`, or clears it when that action worked.
    private func record(_ action: SessionProblem.Action, _ error: (any Error)?) {
        if let error {
            problem = SessionProblem(action: action, message: error.localizedDescription)
        } else if problem?.action == action {
            problem = nil
        }
    }

    @discardableResult private func record(_ action: SessionProblem.Action, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            record(action, nil)
            return true
        } catch {
            record(action, error)
            return false
        }
    }

    private func start() async {
        eventTask = Task { [weak self, events = client.events] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
        await client.connect()
    }

    private func handle(_ event: ClientEvent) {
        switch event {
        case let .welcome(welcome):
            me = welcome.player
            connection = .connected
            record(.save) { try ticketFile?.save(SeatTicket(tableName: tableName, code: code, name: name, token: welcome.token)) }
        case let .state(new):
            state = new
            rejection = nil
        case .connectionLost:
            connection = .reconnecting
        case let .failed(failure):
            connection = .failed(failure)
            // Only our own ticket: one we rejoined with or saved on welcome, never another table's.
            if fromTicket || me != nil { record(.delete) { try ticketFile?.delete() } }
        }
    }
}
