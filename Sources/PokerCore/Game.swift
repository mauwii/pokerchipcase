import Foundation

public let maxSeats = 10

public struct Game: Codable, Equatable, Sendable {
    public internal(set) var state: GameState
    public internal(set) var history: [GameState] = []

    public init(hostID: PlayerID, hostName: String, config: TournamentConfig) {
        state = GameState(
            config: config,
            hostID: hostID,
            seats: [Seat(id: hostID, name: hostName, stack: config.startingStack)]
        )
    }

    /// Wendet einen Befehl atomar an: bei einer `Rejection` bleibt das Spiel unverändert.
    public mutating func apply(_ command: Command, by actor: PlayerID, at now: Date) throws(Rejection) {
        var next = state
        try next.apply(command, by: actor, at: now)
        history.append(state)
        state = next
    }
}

extension GameState {
    mutating func apply(_ command: Command, by actor: PlayerID, at now: Date) throws(Rejection) {
        switch command {
        case let .join(player, name):
            try requireLobbyHost(actor)
            guard seat(player) == nil else { throw .duplicatePlayer }
            guard seats.count < maxSeats else { throw .tableFull }
            seats.append(Seat(id: player, name: name, stack: config.startingStack))

        case let .arrangeSeats(order):
            try requireLobbyHost(actor)
            guard order.count == seats.count, Set(order) == Set(seats.map(\.id)) else { throw .unknownPlayer }
            seats = order.map { id in seats.first { $0.id == id }! }

        case let .removePlayer(player):
            guard actor == hostID else { throw .notHost }
            guard player != hostID else { throw .illegalAction }
            guard let i = index(of: player) else { throw .unknownPlayer }
            guard phase == .lobby else { throw .invalidPhase }
            seats.remove(at: i)

        default:
            throw .invalidPhase
        }
    }

    func requireLobbyHost(_ actor: PlayerID) throws(Rejection) {
        guard actor == hostID else { throw .notHost }
        guard phase == .lobby else { throw .invalidPhase }
    }
}
