public enum Action: Codable, Equatable, Sendable {
    case fold
    case check
    case call
    /// Raises the player's total bet in this betting round to `amount` (a bet if nobody has bet yet).
    case raiseTo(amount: Chips)
    case allIn
}

public enum Command: Codable, Equatable, Sendable {
    case join(player: PlayerID, name: String)
    case removePlayer(player: PlayerID)
    case arrangeSeats(order: [PlayerID])
    case startTournament(button: PlayerID)
    case act(player: PlayerID, action: Action)
    /// Winners per pot, in the order of `GameState.pots`.
    case resolveShowdown(winners: [[PlayerID]])
    case startNextHand
    case pauseClock
    case resumeClock
    case undo
}

public enum Rejection: String, Error, Codable, Equatable, Sendable {
    case notHost
    case notDealer
    case notYourTurn
    case invalidPhase
    case illegalAction
    case invalidAmount
    case unknownPlayer
    case duplicatePlayer
    case tableFull
    case tooFewPlayers
    /// The tournament config has no levels, a non-positive stack or duration, or a small blind outside `1...bigBlind`.
    case invalidConfig
    case invalidShowdown
    case nothingToUndo
    /// The command was based on an outdated state.
    case staleState
}
