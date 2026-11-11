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
    /// `expectedVersion`: die `state.version`, die der Absender zuletzt gesehen hat (nil = keine Prüfung).
    public mutating func apply(
        _ command: Command, by actor: PlayerID, at now: Date, expectedVersion: Int? = nil
    ) throws(Rejection) {
        if let expectedVersion, expectedVersion != state.version { throw .staleState }
        let version = state.version + 1
        if command == .undo {
            guard actor == state.hostID else { throw .notHost }
            guard let previous = history.popLast() else { throw .nothingToUndo }
            state = previous
        } else {
            var next = state
            try next.apply(command, by: actor, at: now)
            history.append(state)
            state = next
        }
        state.version = version
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
            guard let i = index(of: player), !seats[i].isEliminated else { throw .unknownPlayer }
            if phase == .lobby {
                seats.remove(at: i)
            } else {
                try removeFromGame(seat: i)
            }

        case let .startTournament(button):
            try requireLobbyHost(actor)
            guard seats.count >= 2 else { throw .tooFewPlayers }
            guard let b = index(of: button) else { throw .unknownPlayer }
            buttonIndex = b
            handNumber = 1
            clock.levelEndsAt = now + config.levels[0].duration
            startHand()

        case let .act(player, action):
            guard phase == .betting else { throw .invalidPhase }
            guard let i = toActIndex, seats[i].id == player else { throw .notYourTurn }
            if actor != player {
                guard actor == hostID else { throw .notYourTurn }
                guard action == .fold || action == .check else { throw .illegalAction }
            }
            try perform(action, by: i)

        case let .resolveShowdown(winners):
            guard phase == .showdown else { throw .invalidPhase }
            guard actor == dealerID || actor == hostID else { throw .notDealer }
            try resolveShowdown(winners)

        case .startNextHand:
            guard phase == .handComplete else { throw .invalidPhase }
            guard actor == dealerID || actor == hostID else { throw .notDealer }
            clock.advance(to: now, levels: config.levels)
            startNextHand()

        case .pauseClock:
            guard actor == hostID else { throw .notHost }
            guard phase != .lobby, phase != .finished, !clock.isPaused else { throw .invalidPhase }
            clock.pause(at: now)

        case .resumeClock:
            guard actor == hostID else { throw .notHost }
            guard clock.isPaused else { throw .invalidPhase }
            clock.resume(at: now)

        default:
            throw .invalidPhase
        }
    }

    func requireLobbyHost(_ actor: PlayerID) throws(Rejection) {
        guard actor == hostID else { throw .notHost }
        guard phase == .lobby else { throw .invalidPhase }
    }
}
