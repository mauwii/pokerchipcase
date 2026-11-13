import PokerCore
import PokerSession
import SwiftUI

struct TableView: View {
    let session: TableSession
    let state: GameState
    @Environment(\.theme) private var theme

    private var myStack: Chips { session.me.flatMap { state.seat($0)?.stack } ?? 0 }
    private var nextLevel: BlindLevel? {
        state.config.levels.indices.contains(state.clock.levelIndex + 1) ? state.config.levels[state.clock.levelIndex + 1] : nil
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if session.me == state.dealerID, let hint = state.dealerHint {
                Text(hint.message).font(.headline).frame(maxWidth: .infinity).padding(8)
                    .background(theme.accent.opacity(0.25), in: .rect(cornerRadius: 8))
            }
            OvalTable(state: state, viewer: session.me)
            VStack(spacing: 0) {
                Text("Your stack").font(.subheadline).foregroundStyle(theme.muted)
                Text("\(myStack)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                if let legal = session.legalActions, legal.callAmount > 0 {
                    Text("To call \(legal.callAmount)").foregroundStyle(theme.muted)
                }
            }
            bottom
        }
        .padding(.horizontal)
        .foregroundStyle(theme.text)
        .background(theme.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 2) {
            let level = state.currentLevel
            Text("Level \(state.clock.levelIndex + 1) · \(level.smallBlind)/\(level.bigBlind)").font(.headline)
                .foregroundStyle(theme.accent)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if state.clock.isPaused {
                    Text("Paused")
                } else {
                    let seconds = Int(max(0, state.clock.remaining(at: context.date)))
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                    if seconds == 0, nextLevel != nil { Text("Next level starts with the next hand").font(.caption) }
                }
            }
            if let next = nextLevel {
                Text("Next: \(next.smallBlind)/\(next.bigBlind)").font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    @ViewBuilder private var bottom: some View {
        switch state.phase {
        case .betting: ActionBar(session: session, state: state)
        case .showdown: ShowdownView(session: session, state: state)
        case .handComplete: NextHandBar(session: session, state: state)
        default: EmptyView()
        }
    }
}
