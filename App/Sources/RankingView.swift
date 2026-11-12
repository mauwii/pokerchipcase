import PokerCore
import PokerSession
import SwiftUI

struct RankingView: View {
    let session: TableSession
    let state: GameState
    let onLeave: () -> Void

    init(session: TableSession, state: GameState, onLeave: @escaping () -> Void) {
        self.session = session
        self.state = state
        self.onLeave = onLeave
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Final ranking").font(.title.bold())
            List(Array(state.ranking.enumerated()), id: \.element.id) { i, seat in
                HStack {
                    Text("\(i + 1). \(seat.name)")
                    if i == 0 {
                        Spacer()
                        Text("\(seat.stack)").monospacedDigit().bold()
                    }
                }
            }
            .listStyle(.plain)
            Button("Leave table") {
                Task {
                    await session.leave()
                    onLeave()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .padding(.horizontal)
    }
}
