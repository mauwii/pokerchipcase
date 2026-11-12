import PokerCore
import PokerSession
import SwiftUI

struct RankingView: View {
    let state: GameState
    let onLeave: () -> Void

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
            Button("Leave table", action: onLeave)
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .padding(.horizontal)
    }
}
