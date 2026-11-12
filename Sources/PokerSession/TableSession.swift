import Foundation
import Network
import Observation
import PokerCore
import PokerNet

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
        guard let token = snapshot.hostToken else { throw CocoaError(.fileReadCorruptFile) }
        // Saved before anything else, so a crash in the lobby is resumable too.
        try saveFile.save(snapshot)
        let host = TableHost(snapshot: snapshot, onChange: { try? saveFile.save($0) })
        let bound = try await host.start(port: port)
        let name = snapshot.game.state.seat(snapshot.game.state.hostID)!.name
        let client = TableClient(endpoint: .hostPort(host: "127.0.0.1", port: bound), code: snapshot.code,
                                 name: name, token: token)
        let session = TableSession(tableName: snapshot.tableName, code: snapshot.code, name: name, client: client,
                                   tableHost: host, port: bound, saveFile: saveFile, ticketFile: nil)
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
        defer { isSending = false }
        // Thrown errors are ignored: `connection` already shows the problem.
        if case let .rejected(reason) = try? await client.send(command) { rejection = reason }
    }

    public func act(_ action: Action) async {
        guard let me else { return }
        await send(.act(player: me, action: action))
    }

    /// Call when the scene becomes active: restarts the host listener iOS tore down.
    public func appBecameActive() async {
        // ponytail: if the old port is taken the table stays unreachable; restart on .any + new loopback client if that happens in practice
        try? await tableHost?.ensureListening()
    }

    /// Disconnects; the host also stops the table. Deletes this device's save file.
    public func leave() async {
        await client.disconnect()
        await tableHost?.stop()
        saveFile?.delete()
        ticketFile?.delete()
    }

    private func start() async {
        Task { [weak self, events = client.events] in
            for await event in events {
                guard let self else { return }
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
            try? ticketFile?.save(SeatTicket(tableName: tableName, code: code, name: name, token: welcome.token))
        case let .state(new):
            state = new
            rejection = nil
        case .connectionLost:
            connection = .reconnecting
        case let .failed(failure):
            connection = .failed(failure)
            // Only our own ticket: one we rejoined with or saved on welcome, never another table's.
            if fromTicket || me != nil { ticketFile?.delete() }
        }
    }
}
