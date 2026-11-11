/// Splits `amount` evenly; odd chips go one by one to the winners in seat order, starting left of the button.
func split(_ amount: Chips, among winners: [PlayerID], seats: [Seat], buttonIndex: Int) -> [PlayerID: Chips] {
    var shares = Dictionary(uniqueKeysWithValues: winners.map { ($0, amount / winners.count) })
    let order = (1...seats.count).map { seats[(buttonIndex + $0) % seats.count].id }.filter(winners.contains)
    for id in order.prefix(amount % winners.count) {
        shares[id]! += 1
    }
    return shares
}

/// Splits the hand's bets into main and side pots (main pot first).
/// Pot boundaries come only from all-ins of players still in the hand.
func computePots(_ seats: [Seat]) -> [Pot] {
    let live = seats.filter { !$0.folded }
    let allInLevels = live.filter(\.allIn).map(\.handBet)
    let levels = Set(allInLevels + [live.map(\.handBet).max() ?? 0]).sorted()

    var pots: [Pot] = []
    var prev: Chips = 0
    for level in levels {
        let amount = seats.reduce(0) { $0 + min($1.handBet, level) - min($1.handBet, prev) }
        let eligible = live.filter { $0.handBet >= level }.map(\.id)
        prev = level
        guard amount > 0 else { continue }
        if pots.last?.eligible == eligible {
            pots[pots.count - 1].amount += amount
        } else {
            pots.append(Pot(amount: amount, eligible: eligible))
        }
    }
    // Folded players' bets above the highest live bet belong to the top pot.
    let dead = seats.reduce(0) { $0 + max(0, $1.handBet - prev) }
    if dead > 0, !pots.isEmpty { pots[pots.count - 1].amount += dead }
    return pots
}
