import Foundation

/// Most players one table seats.
public let maxSeats = 10

/// A tournament in progress: the current state plus the earlier states that `undo` steps back to.
public struct Game: Codable, Equatable, Sendable {
    /// The current table state.
    public internal(set) var state: GameState
    /// Earlier states of the current hand, oldest first; a new hand keeps only the previous hand's last step
    /// and the steps of the command that started it.
    /// `undo` pops the last one.
    public internal(set) var history: [GameState] = []

    /// Starts a lobby with only the host seated at `config.startingStack`.
    public init(hostID: PlayerID, hostName: String, config: TournamentConfig) {
        state = GameState(
            config: config,
            hostID: hostID,
            seats: [Seat(id: hostID, name: hostName, stack: config.startingStack)]
        )
    }

    /// Applies a command atomically: on a `Rejection` the game stays unchanged.
    /// `expectedVersion`: the `state.version` the sender saw last (nil = no check).
    /// Digital games shuffle with the system random number generator.
    public mutating func apply(
        _ command: Command, by actor: PlayerID, at now: Date, expectedVersion: Int? = nil
    ) throws(Rejection) {
        var rng = SystemRandomNumberGenerator()
        try apply(command, by: actor, at: now, expectedVersion: expectedVersion, using: &rng)
    }

    /// Applies a command like ``apply(_:by:at:expectedVersion:)``, shuffling digital decks with `rng`.
    public mutating func apply<R: RandomNumberGenerator>(
        _ command: Command, by actor: PlayerID, at now: Date, expectedVersion: Int? = nil, using rng: inout R
    ) throws(Rejection) {
        if let expectedVersion, expectedVersion != state.version { throw .staleState }
        let version = state.version + 1
        if command == .undo {
            guard actor == state.hostID else { throw .notHost }
            guard var previous = history.popLast() else { throw .nothingToUndo }
            // The clock is not undone: a pause survives undoing the misclick it was taken for.
            if previous.phase != .lobby { previous.clock = state.clock }
            // The host is not undone: the phone that handed the table over no longer serves it.
            previous.hostID = state.hostID
            state = previous
        } else {
            var next = state
            try next.apply(command, by: actor, at: now, using: &rng)
            var steps = [.pauseClock, .resumeClock].contains(command) || command.isTransferHost ? [] : [state]
            if next.config.digitalCards, state.phase != .showdown, next.phase == .showdown {
                // The cards decide, so the payout is automatic; the showdown stays in history for undo.
                steps.append(next)
                try next.resolveShowdown(next.showdownWinners())
            }
            // The host save holds the history, so it must not grow over a tournament (#109). The previous
            // hand's last step stays, so undoing the deal can still take back that hand's payout.
            history = (next.handNumber > state.handNumber ? Array(history.suffix(1)) : history) + steps
            state = next
        }
        state.version = version
    }

    /// Updates a seat's display name in the current state and undo history without recording a game action.
    public mutating func renameSeat(_ player: PlayerID, to name: String) {
        for index in state.seats.indices where state.seats[index].id == player {
            state.seats[index].name = name
        }
        for step in history.indices {
            for index in history[step].seats.indices where history[step].seats[index].id == player {
                history[step].seats[index].name = name
            }
        }
    }

    /// Drops all but the `count` newest undo steps.
    public mutating func keepHistory(last count: Int) {
        history = Array(history.suffix(count))
    }
}

extension Command {
    fileprivate var isTransferHost: Bool {
        if case .transferHost = self { true } else { false }
    }
}

extension GameState {
    mutating func apply<R: RandomNumberGenerator>(
        _ command: Command, by actor: PlayerID, at now: Date, using rng: inout R
    ) throws(Rejection) {
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
            guard actor == hostID || (phase == .lobby && actor == player) else { throw .notHost }
            guard player != hostID else { throw .illegalAction }
            guard let i = index(of: player), !seats[i].isOut else { throw .unknownPlayer }
            if phase == .lobby {
                seats.remove(at: i)
            } else {
                try removeFromGame(seat: i)
            }

        case let .startTournament(button):
            try requireLobbyHost(actor)
            guard seats.count >= 2 else { throw .tooFewPlayers }
            guard config.isValid else { throw .invalidConfig }
            guard let b = index(of: button) else { throw .unknownPlayer }
            buttonIndex = b
            handNumber = 1
            clock.levelEndsAt = now + config.levels[0].duration
            startHand(using: &rng)

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
            startNextHand(using: &rng)

        case .pauseClock:
            guard actor == hostID else { throw .notHost }
            guard phase != .lobby, phase != .finished, !clock.isPaused else { throw .invalidPhase }
            clock.pause(at: now)

        case .resumeClock:
            guard actor == hostID else { throw .notHost }
            guard clock.isPaused else { throw .invalidPhase }
            clock.resume(at: now)

        case let .transferHost(player):
            guard actor == hostID else { throw .notHost }
            guard phase != .lobby, phase != .finished else { throw .invalidPhase }
            guard seat(player) != nil else { throw .unknownPlayer }
            guard player != hostID else { throw .illegalAction }
            hostID = player

        default:
            throw .invalidPhase
        }
    }

    func requireLobbyHost(_ actor: PlayerID) throws(Rejection) {
        guard actor == hostID else { throw .notHost }
        guard phase == .lobby else { throw .invalidPhase }
    }
}
