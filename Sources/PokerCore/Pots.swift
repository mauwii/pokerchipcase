/// Teilt `amount` gleichmäßig; Restchips einzeln an die Gewinner in Sitzreihenfolge ab dem ersten Sitz links vom Button.
func split(_ amount: Chips, among winners: [PlayerID], seats: [Seat], buttonIndex: Int) -> [PlayerID: Chips] {
    var shares = Dictionary(uniqueKeysWithValues: winners.map { ($0, amount / winners.count) })
    let order = (1...seats.count).map { seats[(buttonIndex + $0) % seats.count].id }.filter(winners.contains)
    for id in order.prefix(amount % winners.count) {
        shares[id]! += 1
    }
    return shares
}

/// Teilt die Einsätze der Hand in Haupt- und Side-Pots (Hauptpot zuerst).
/// Pot-Grenzen entstehen nur durch All-ins von Spielern, die noch in der Hand sind.
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
    return pots
}
