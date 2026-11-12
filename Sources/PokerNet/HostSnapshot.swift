import Foundation
import PokerCore

/// Everything the host must persist to resume a table after a crash:
/// the game, the reconnect tokens, and the table name and code clients know it by.
public struct HostSnapshot: Codable, Equatable, Sendable {
    public var game: Game
    /// Reconnect token → player.
    public var tokens: [String: PlayerID]
    public var tableName: String
    public var code: TableCode

    public init(game: Game, tokens: [String: PlayerID], tableName: String, code: TableCode) {
        self.game = game
        self.tokens = tokens
        self.tableName = tableName
        self.code = code
    }

    public static func newTable(
        hostName: String, tableName: String, code: TableCode = .random(), config: TournamentConfig
    ) -> HostSnapshot {
        let hostID = UUID().uuidString
        return HostSnapshot(
            game: Game(hostID: hostID, hostName: hostName, config: config),
            tokens: [UUID().uuidString: hostID],
            tableName: tableName,
            code: code
        )
    }

    /// Token the host device's own client uses to connect as the host; nil if the save lost it.
    public var hostToken: String? {
        tokens.first { $0.value == game.state.hostID }?.key
    }
}
