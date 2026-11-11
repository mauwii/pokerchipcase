import PokerCore
import PokerSession
import SwiftUI

private func dealerName(_ state: GameState) -> String {
    state.dealerID.flatMap { state.seat($0)?.name } ?? ""
}

struct ShowdownView: View {
    let session: TableSession
    let state: GameState
    @State private var winners: [Set<PlayerID>] = []

    init(session: TableSession, state: GameState) {
        self.session = session
        self.state = state
    }

    private var selection: [Set<PlayerID>] {
        winners.count == state.pots.count ? winners : Array(repeating: [], count: state.pots.count)
    }

    var body: some View {
        if session.canRunHand {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(state.pots.indices, id: \.self) { i in potSection(i) }
                    }
                }
                Button("Pay out") { payOut() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isSending || selection.contains { $0.isEmpty })
            }
            .padding(.bottom)
            .onChange(of: state.version, initial: true) { winners = Array(repeating: [], count: state.pots.count) }
        } else {
            Text("Waiting for \(dealerName(state)) to pick the winners").foregroundStyle(.secondary).padding(.bottom)
        }
    }

    private func potSection(_ i: Int) -> some View {
        let pot = state.pots[i]
        return VStack(alignment: .leading) {
            Text(i == 0 ? "Main pot \(pot.amount)" : "Side pot \(i) \(pot.amount)").font(.headline)
            ForEach(pot.eligible, id: \.self) { id in
                Toggle(state.seat(id)?.name ?? "", isOn: Binding(
                    get: { selection[i].contains(id) },
                    set: { on in
                        var s = selection
                        if on { s[i].insert(id) } else { s[i].remove(id) }
                        winners = s
                    }))
            }
        }
    }

    private func payOut() {
        let order = state.seats.map(\.id)
        let lists = selection.map { chosen in order.filter(chosen.contains) }
        Task { await session.send(.resolveShowdown(winners: lists)) }
    }
}

struct NextHandBar: View {
    let session: TableSession
    let state: GameState

    init(session: TableSession, state: GameState) {
        self.session = session
        self.state = state
    }

    var body: some View {
        Group {
            if session.canRunHand {
                Button("Next hand") { Task { await session.send(.startNextHand) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isSending)
            } else {
                Text("Waiting for \(dealerName(state)) to start the next hand").foregroundStyle(.secondary)
            }
        }
        .padding(.bottom)
    }
}
