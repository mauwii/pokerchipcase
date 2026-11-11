import Foundation
import PokerNet
@testable import PokerCore

let t0 = Date(timeIntervalSince1970: 0)
let code4711 = TableCode("4711")!

/// A (host), B, C with 1000 chips each unless `stacks` says otherwise; blinds 10/20; button A, started at t0.
/// B posts 10, C posts 20, A acts first.
func started(stacks: [PlayerID: Chips] = [:]) throws -> Game {
    var g = Game(
        hostID: "A", hostName: "A",
        config: TournamentConfig(startingStack: 1000, levels: [BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600)]))
    try g.apply(.join(player: "B", name: "B"), by: "A", at: t0)
    try g.apply(.join(player: "C", name: "C"), by: "A", at: t0)
    for (id, stack) in stacks {
        g.state.seats[g.state.index(of: id)!].stack = stack
    }
    try g.apply(.startTournament(button: "A"), by: "A", at: t0)
    return g
}

extension Game {
    /// The player to act, by themselves, at t0.
    mutating func act(_ action: Action) throws {
        guard let i = state.toActIndex else { throw Rejection.notYourTurn }
        let p = state.seats[i].id
        try apply(.act(player: p, action: action), by: p, at: t0)
    }
}
