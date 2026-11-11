import Foundation
@testable import PokerCore

let t0 = Date(timeIntervalSince1970: 0)
let tenTwenty = [BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600)]

extension Game {
    /// Host = first player. Stacks are set in the lobby, then startTournament(button:) at t0.
    static func started(
        _ stacks: KeyValuePairs<PlayerID, Chips> = ["A": 1000, "B": 1000, "C": 1000],
        levels: [BlindLevel] = tenTwenty,
        button: PlayerID = "A"
    ) throws -> Game {
        let host = stacks.first!.key
        var g = Game(hostID: host, hostName: host, config: TournamentConfig(startingStack: 1000, levels: levels))
        for (id, _) in stacks.dropFirst() {
            try g.apply(.join(player: id, name: id), by: host, at: t0)
        }
        for (id, stack) in stacks {
            g.state.seats[g.state.index(of: id)!].stack = stack
        }
        try g.apply(.startTournament(button: button), by: host, at: t0)
        return g
    }

    var toAct: PlayerID? { state.toActIndex.map { state.seats[$0].id } }

    /// Checks or calls until no betting round is running.
    mutating func checkDown() throws(Rejection) {
        while state.phase == .betting, let p = toAct {
            try act(state.legalActions(for: p)!.canCheck ? .check : .call)
        }
    }

    /// Applies act(player: toAct, action:).
    mutating func act(_ action: Action, at now: Date = t0) throws(Rejection) {
        guard let p = toAct else { throw .notYourTurn }
        try apply(.act(player: p, action: action), by: p, at: now)
    }
}
