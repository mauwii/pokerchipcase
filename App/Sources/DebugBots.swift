#if DEBUG
import Network
import PokerCore
import PokerSession
import SwiftUI

/// Debug builds only: fills the host's lobby with in-process guests that check or call on their turn,
/// so a full table can be played on one simulator.
@MainActor enum DebugBots {
    private static let names = ["foo", "bar", "baz", "qux", "quux", "corge", "grault", "Maximilian-Alexander", "garply"]
    // ponytail: bots are never torn down; they idle after the table ends. Add cleanup if they get in the way.
    private static var bots: [(TableSession, Task<Void, Never>)] = []

    /// Launch argument `-debugTable`: create a table, fill it with bots and start, with no taps.
    /// Combine with `-playerName Du` and `-appearance felt|dark`.
    static let auto = ProcessInfo.processInfo.arguments.contains("-debugTable")

    static func autoStart(_ host: TableSession) async {
        guard let state = host.state else { return }
        fill(host, seated: state.seats.count)
        for _ in 0..<60 where (host.state?.seats.count ?? 0) < maxSeats { try? await Task.sleep(for: .milliseconds(500)) }
        if let me = host.me { await host.send(.startTournament(button: me)) }
    }

    static func fill(_ host: TableSession, seated: Int) {
        let free = max(0, maxSeats - seated)
        for name in names.prefix(free) {
            Task {
                // Bonjour, like a real guest; a throwaway ticket file so the real seat ticket stays untouched.
                let bot = await TableSession.join(
                    endpoint: .service(name: host.tableName, type: Wire.serviceType, domain: "local.", interface: nil),
                    tableName: host.tableName, code: host.code, name: name,
                    ticketFile: SaveFile(url: .temporaryDirectory.appending(path: "bot-\(name).json")))
                let play = Task {
                    while !Task.isCancelled {
                        if let legal = bot.legalActions, !bot.isSending { await bot.act(legal.canCheck ? .check : .call) }
                        try? await Task.sleep(for: .milliseconds(800))
                    }
                }
                bots.append((bot, play))
            }
        }
    }
}
#endif
