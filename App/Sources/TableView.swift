import PokerCore
import PokerSession
import SwiftUI

struct TableView: View {
    let session: TableSession
    let state: GameState

    init(session: TableSession, state: GameState) {
        self.session = session
        self.state = state
    }

    private var myStack: Chips { session.me.flatMap { state.seat($0)?.stack } ?? 0 }
    private var nextLevel: BlindLevel? {
        state.config.levels.indices.contains(state.clock.levelIndex + 1) ? state.config.levels[state.clock.levelIndex + 1] : nil
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            if session.me == state.dealerID, let hint = state.dealerHint {
                Text(hint.message).font(.headline).frame(maxWidth: .infinity).padding(8)
                    .background(.tint.opacity(0.2), in: .rect(cornerRadius: 8))
            }
            List(state.seats.indices, id: \.self) { i in
                seatRow(state.seats[i], acting: state.toActIndex == i)
                    .listRowBackground(state.toActIndex == i ? Color.accentColor.opacity(0.2) : nil)
            }
            .listStyle(.plain)
            Text("Pot \(state.potTotal)").font(.title2.bold())
            VStack {
                Text("Your stack").font(.subheadline).foregroundStyle(.secondary)
                Text("\(myStack)").font(.system(size: 44, weight: .bold, design: .rounded))
                if let legal = session.legalActions, legal.callAmount > 0 {
                    Text("To call \(legal.callAmount)").foregroundStyle(.secondary)
                }
            }
            bottom
        }
        .padding(.horizontal)
    }

    private var header: some View {
        VStack(spacing: 2) {
            let level = state.currentLevel
            Text("Level \(state.clock.levelIndex + 1) · \(level.smallBlind)/\(level.bigBlind)").font(.headline)
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
                Text("Next: \(next.smallBlind)/\(next.bigBlind)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func seatRow(_ seat: Seat, acting: Bool) -> some View {
        HStack {
            Text(seat.name + (seat.id == session.me ? " (you)" : "")).fontWeight(acting ? .bold : .regular)
            if seat.id == state.dealerID { badge("D") }
            if seat.allIn { badge("All-in") }
            Spacer()
            if let rank = seat.eliminatedRank {
                Text("Out · #\(rank)").foregroundStyle(.secondary)
            } else {
                if seat.folded { Text("folded") }
                if seat.roundBet > 0 { Text("bet \(seat.roundBet)") }
                if state.phase == .handComplete, seat.stack != seat.stackAtHandStart {
                    let delta = seat.stack - seat.stackAtHandStart
                    Text(delta > 0 ? "+\(delta)" : "−\(-delta)").foregroundStyle(delta > 0 ? .green : .red)
                }
                Text("\(seat.stack)").monospacedDigit().bold()
            }
        }
        .opacity(seat.folded || seat.isEliminated ? 0.5 : 1)
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(.tint.opacity(0.25), in: .capsule)
    }

    @ViewBuilder private var bottom: some View {
        switch state.phase {
        case .betting: ActionBar(session: session, state: state)
        default: Text(state.phase.rawValue) // replaced in Task 8
        }
    }
}
