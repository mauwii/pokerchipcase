import Testing
@testable import PokerCore

private func seat(_ id: PlayerID, bet: Chips, allIn: Bool = false, folded: Bool = false) -> Seat {
    var s = Seat(id: id, name: id, stack: allIn ? 0 : 1000)
    s.handBet = bet
    s.allIn = allIn
    s.folded = folded
    return s
}

@Test func singlePot() {
    let pots = computePots([seat("A", bet: 100), seat("B", bet: 100), seat("C", bet: 100)])
    #expect(pots == [Pot(amount: 300, eligible: ["A", "B", "C"])])
}

@Test func sidePotFromShortAllIn() {
    let pots = computePots([seat("A", bet: 100, allIn: true), seat("B", bet: 300), seat("C", bet: 300)])
    #expect(pots == [Pot(amount: 300, eligible: ["A", "B", "C"]), Pot(amount: 400, eligible: ["B", "C"])])
}

@Test func foldedChipsStayInPots() {
    let pots = computePots([seat("A", bet: 50, folded: true), seat("B", bet: 100, allIn: true), seat("C", bet: 300)])
    #expect(pots == [Pot(amount: 250, eligible: ["B", "C"]), Pot(amount: 200, eligible: ["C"])])
}

@Test func twoAllInsSameLevel() {
    let pots = computePots([
        seat("A", bet: 100, allIn: true), seat("B", bet: 100, allIn: true), seat("C", bet: 300), seat("D", bet: 300),
    ])
    #expect(pots == [Pot(amount: 400, eligible: ["A", "B", "C", "D"]), Pot(amount: 400, eligible: ["C", "D"])])
}

@Test func foldedBetsCreateNoLevel() {
    let pots = computePots([
        seat("A", bet: 50, folded: true), seat("B", bet: 100, folded: true), seat("C", bet: 300), seat("D", bet: 300),
    ])
    #expect(pots == [Pot(amount: 750, eligible: ["C", "D"])])
}
