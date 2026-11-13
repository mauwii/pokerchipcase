import PokerCore
import PokerSession
import SwiftUI

struct TableView: View {
    let session: TableSession
    let state: GameState
    @Environment(\.theme) private var theme
    /// Showdown winners per pot, picked on the oval by the player running the hand.
    @State private var winners: [Set<PlayerID>] = []
    @State private var pot = 0

    private var picking: Bool { state.phase == .showdown && session.canRunHand && state.pots.indices.contains(pot) }

    private var myStack: Chips { session.me.flatMap { state.seat($0)?.stack } ?? 0 }
    /// The hand is over and I won chips in it.
    private var iWon: Bool {
        state.phase == .handComplete && (session.me.flatMap { state.seat($0) }.map { $0.stack > $0.stackAtHandStart } ?? false)
    }
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
            // One view for every phase, so it keeps its identity and animates into the showdown.
            OvalTable(state: state, viewer: session.me, seatState: seatState, onTapSeat: onTapSeat)
            VStack(spacing: 0) {
                Text("Your stack").font(.subheadline).foregroundStyle(theme.muted)
                Text("\(myStack)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).animation(.default, value: myStack)
                if let legal = session.legalActions, legal.callAmount > 0 {
                    Text("To call \(legal.callAmount)").foregroundStyle(theme.muted)
                }
            }
            bottom
        }
        .padding(.horizontal)
        .foregroundStyle(theme.text)
        .background(theme.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: iWon) { _, won in won }
        .onChange(of: state.pots, initial: true) {
            winners = Array(repeating: [], count: state.pots.count)
            pot = 0
        }
    }

    private var seatState: (Seat) -> SeatMark {
        guard picking else { return { _ in SeatMark.normal } }
        return { mark($0) }
    }

    private var onTapSeat: ((PlayerID) -> Void)? {
        guard picking else { return nil }
        return { toggle($0) }
    }

    private func mark(_ seat: Seat) -> SeatMark {
        if winners.indices.contains(pot), winners[pot].contains(seat.id) { return .selected }
        return state.pots[pot].eligible.contains(seat.id) ? .selectable : .dimmed
    }

    private func toggle(_ id: PlayerID) {
        guard winners.indices.contains(pot), state.pots[pot].eligible.contains(id) else { return }
        if winners[pot].contains(id) { winners[pot].remove(id) } else { winners[pot].insert(id) }
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
        case .showdown: ShowdownView(session: session, state: state, winners: $winners, pot: $pot)
        case .handComplete: NextHandBar(session: session, state: state)
        default: EmptyView()
        }
    }
}
