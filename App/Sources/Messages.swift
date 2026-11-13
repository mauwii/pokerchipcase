import PokerCore
import PokerNet
import PokerSession

extension ClientFailure {
    var message: String {
        switch self {
        case .wrongCode: "Wrong code"
        case .versionMismatch: "Please update the app"
        case .tableFull: "The table is full"
        case .gameInProgress: "The tournament has already started"
        case .removed: "You were removed from the table"
        case .tableClosed: "The host ended the table"
        case .replaced: "You joined this table from another device"
        }
    }
}

extension SessionProblem {
    var text: String {
        switch action {
        case .save: "Couldn't save the game: \(message)"
        case .delete: "Couldn't delete the saved game: \(message)"
        case .send: "Not sent – please try again"
        case .listen: "Guests can't reach the table: \(message)"
        }
    }
}

extension Rejection {
    var message: String {
        switch self {
        case .notHost: "Only the host can do that"
        case .notDealer: "Only the dealer can do that"
        case .notYourTurn: "It's not your turn"
        case .invalidPhase: "Not possible right now"
        case .illegalAction: "That action is not allowed"
        case .invalidAmount: "Invalid amount"
        case .unknownPlayer: "Unknown player"
        case .duplicatePlayer: "That player is already seated"
        case .tableFull: "The table is full"
        case .tooFewPlayers: "At least 2 players are needed"
        case .invalidConfig: "Invalid tournament settings"
        case .invalidShowdown: "Pick at least one winner for every pot"
        case .nothingToUndo: "Nothing to undo"
        case .staleState: "The table changed – please try again"
        }
    }
}

extension DealerHint {
    var message: String {
        switch self {
        case .dealHand: "You deal"
        case .dealFlop: "Deal the flop"
        case .dealTurn: "Deal the turn"
        case .dealRiver: "Deal the river"
        case .dealRest: "Deal the rest of the board"
        }
    }
}
