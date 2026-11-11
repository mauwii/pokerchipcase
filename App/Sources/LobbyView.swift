import PokerCore
import PokerSession
import SwiftUI

struct LobbyView: View {
    let session: TableSession
    let state: GameState
    @State private var dealer: PlayerID?
    @State private var nearby = NearbyTables()

    init(session: TableSession, state: GameState) {
        self.session = session
        self.state = state
    }

    private var minutes: Int { Int((state.config.levels.first?.duration ?? 0) / 60) }

    /// A dealer seat that has left the table falls back to "Random".
    private var choice: PlayerID? { dealer.flatMap { state.seat($0)?.id } }

    var body: some View {
        List {
            if session.isHost {
                Section {
                    VStack(spacing: 4) {
                        Text("Table code").font(.subheadline).foregroundStyle(.secondary)
                        Text(session.code.digits).font(.system(size: 48, weight: .bold, design: .monospaced))
                        Text("\(state.config.startingStack) chips · \(minutes) min levels").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                if nearby.localNetworkDenied { Section { LocalNetworkNotice() } }
            }
            Section("Players") {
                if session.isHost {
                    ForEach(state.seats, id: \.id) { seat in Text(seat.name).deleteDisabled(seat.id == state.hostID) }
                        .onMove { source, destination in
                            var ids = state.seats.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            Task { await session.send(.arrangeSeats(order: ids)) }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { state.seats[$0].id }.filter { $0 != state.hostID }
                            Task { for id in ids { await session.send(.removePlayer(player: id)) } }
                        }
                } else {
                    ForEach(state.seats, id: \.id) { seat in Text(seat.name) }
                }
            }
            if session.isHost {
                Section {
                    Picker("Dealer", selection: $dealer) {
                        Text("Random").tag(PlayerID?.none)
                        ForEach(state.seats, id: \.id) { Text($0.name).tag(PlayerID?.some($0.id)) }
                    }
                    Button("Start tournament") {
                        guard let button = choice ?? state.seats.randomElement()?.id else { return }
                        Task { await session.send(.startTournament(button: button)) }
                    }
                    .disabled(state.seats.count < 2 || session.isSending)
                }
            } else {
                Section { Text("Waiting for \(state.seat(state.hostID)?.name ?? "the host") to start") }
            }
        }
        .environment(\.editMode, .constant(session.isHost ? .active : .inactive))
        .task { if session.isHost { await nearby.run() } }
    }
}
