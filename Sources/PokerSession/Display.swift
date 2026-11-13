import PokerCore

public enum DealerHint: Equatable, Sendable { case dealHand, dealFlop, dealTurn, dealRiver, dealRest }

public struct QuickPick: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case halfPot, pot, allIn }
    public var kind: Kind
    public var raiseTo: Chips
}

extension GameState {
    /// What the dealer has to deal right now; nil if nothing.
    public var dealerHint: DealerHint? {
        switch phase {
        case .betting where !seats.contains { $0.acted }:
            switch street {
            case .preflop: .dealHand
            case .flop: .dealFlop
            case .turn: .dealTurn
            case .river: .dealRiver
            }
        case .showdown where street != .river:
            .dealRest
        default:
            nil
        }
    }

    /// "½ pot", "pot", "all-in" raise targets in that order, clamped to the legal range; empty if `player` cannot raise.
    public func quickPicks(for player: PlayerID) -> [QuickPick] {
        guard let legal = legalActions(for: player),
              let lo = legal.minRaiseTo, let hi = legal.maxRaiseTo else { return [] }
        let base = potTotal + legal.callAmount
        var picks: [QuickPick] = []
        for (kind, target) in [(QuickPick.Kind.halfPot, currentBet + base / 2), (.pot, currentBet + base)] {
            let raiseTo = min(max(target, lo), hi)
            if raiseTo != hi {
                picks.append(QuickPick(kind: kind, raiseTo: raiseTo))
            }
        }
        return picks + [QuickPick(kind: .allIn, raiseTo: hi)]
    }

    /// True if `action` would put all of `player`'s remaining chips in; the app asks for confirmation.
    public func commitsAllChips(_ action: Action, by player: PlayerID) -> Bool {
        guard let s = seat(player) else { return false }
        switch action {
        case .allIn: return true
        case .call: return currentBet - s.roundBet >= s.stack
        case .raiseTo(let x): return x >= s.roundBet + s.stack
        default: return false
        }
    }
}
