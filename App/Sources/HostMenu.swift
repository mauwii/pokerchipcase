import PokerCore
import PokerSession
import SwiftUI

/// Destructive host actions that need a confirmation. The dialog lives outside the menu
/// (see `hostConfirmation`), because a menu's content is gone once it closes.
enum HostConfirm: Equatable {
    case remove(PlayerID, String)
    case undo
}

/// Menu content for the host; the caller provides the surrounding menu and the confirmation dialog.
struct HostMenu: View {
    let session: TableSession
    let state: GameState
    @Binding var pending: HostConfirm?

    init(session: TableSession, state: GameState, pending: Binding<HostConfirm?>) {
        self.session = session
        self.state = state
        _pending = pending
    }

    private var actor: Seat? {
        guard state.phase == .betting, let i = state.toActIndex, state.seats.indices.contains(i) else { return nil }
        return state.seats[i]
    }

    var body: some View {
        if state.phase != .finished {
            if state.clock.isPaused {
                Button("Resume clock", systemImage: "play") { send(.resumeClock) }
            } else {
                Button("Pause clock", systemImage: "pause") { send(.pauseClock) }
            }
        }
        if let seat = actor, seat.id != session.me {
            if state.legalActions(for: seat.id)?.canCheck == true {
                Button("Check for \(seat.name)") { send(.act(player: seat.id, action: .check)) }
            } else {
                Button("Fold for \(seat.name)") { send(.act(player: seat.id, action: .fold)) }
            }
        }
        Menu("Remove player", systemImage: "person.badge.minus") {
            ForEach(state.seats.filter { $0.id != state.hostID && !$0.isEliminated }, id: \.id) { seat in
                Button(seat.name) { pending = .remove(seat.id, seat.name) }
            }
        }
        Button("Undo last change", systemImage: "arrow.uturn.backward") { pending = .undo }
    }

    private func send(_ command: Command) {
        Task { await session.send(command) }
    }
}

extension View {
    func hostConfirmation(_ pending: Binding<HostConfirm?>, session: TableSession) -> some View {
        let item = pending.wrappedValue
        let title: String = switch item {
        case let .remove(_, name): "Remove \(name)? Their chips are forfeited."
        case .undo: "Undo the last change for everyone?"
        case nil: ""
        }
        return confirmationDialog(
            title, isPresented: Binding(get: { item != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible
        ) {
            switch item {
            case let .remove(id, _): Button("Remove", role: .destructive) { run(.removePlayer(player: id)) }
            case .undo: Button("Undo", role: .destructive) { run(.undo) }
            case nil: EmptyView()
            }
        }
        func run(_ command: Command) { Task { await session.send(command) } }
    }
}
