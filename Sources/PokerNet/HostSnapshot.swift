import Foundation
import PokerCore

/// Everything the host must persist to resume a table after a crash: the game and the reconnect tokens.
public struct HostSnapshot: Codable, Equatable, Sendable {
    public var game: Game
    /// Reconnect token → player.
    public var tokens: [String: PlayerID]

    public init(game: Game, tokens: [String: PlayerID]) {
        self.game = game
        self.tokens = tokens
    }

    public static func newTable(hostName: String, config: TournamentConfig) -> HostSnapshot {
        let hostID = UUID().uuidString
        return HostSnapshot(
            game: Game(hostID: hostID, hostName: hostName, config: config),
            tokens: [UUID().uuidString: hostID]
        )
    }

    /// Token the host device's own client uses to connect as the host.
    public var hostToken: String {
        tokens.first { $0.value == game.state.hostID }!.key
    }
}
