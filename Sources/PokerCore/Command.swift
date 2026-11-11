public enum Action: Codable, Equatable, Sendable {
    case fold
    case check
    case call
    /// Erhöht den eigenen Gesamteinsatz in dieser Setzrunde auf `amount` (Bet, wenn noch niemand gesetzt hat).
    case raiseTo(amount: Chips)
    case allIn
}

public enum Command: Codable, Equatable, Sendable {
    case join(player: PlayerID, name: String)
    case removePlayer(player: PlayerID)
    case arrangeSeats(order: [PlayerID])
    case startTournament(button: PlayerID)
    case act(player: PlayerID, action: Action)
    /// Pro Pot (in der Reihenfolge von `GameState.pots`) die Gewinner.
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
    case invalidShowdown
    case nothingToUndo
}
