import PokerCore
import PokerNet
import PokerSession
import SwiftUI

struct TableScreen: View {
    let session: TableSession
    let onLeave: () -> Void
    @State private var confirmLeave = false

    init(session: TableSession, onLeave: @escaping () -> Void) {
        self.session = session
        self.onLeave = onLeave
    }

    private var failure: Binding<Bool> {
        Binding(get: { if case .failed = session.connection { true } else { false } }, set: { _ in })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let state = session.state {
                    if state.phase == .lobby {
                        LobbyView(session: session, state: state)
                    } else if state.phase == .finished {
                        RankingView(session: session, state: state, onLeave: onLeave)
                    } else {
                        TableView(session: session, state: state)
                    }
                } else {
                    ProgressView("Connecting…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(session.tableName)
            .safeAreaInset(edge: .top) { banner }
            .toolbar {
                Menu("Table", systemImage: "ellipsis.circle") {
                    Button(session.isHost ? "End table" : "Leave table", role: .destructive) { confirmLeave = true }
                }
            }
            .confirmationDialog(
                session.isHost ? "End the table for everyone?" : "Leave the table? Your seat stays until the host removes it.",
                isPresented: $confirmLeave, titleVisibility: .visible
            ) {
                Button(session.isHost ? "End table" : "Leave table", role: .destructive) { leave() }
            }
            .alert(failureMessage, isPresented: failure) { Button("OK") { leave() } }
        }
    }

    private var failureMessage: String {
        if case let .failed(f) = session.connection { f.message } else { "" }
    }

    @ViewBuilder private var banner: some View {
        if session.connection == .reconnecting {
            Text("Reconnecting…").frame(maxWidth: .infinity).padding(6).background(.bar)
        } else if session.isSending {
            Text("Sending…").frame(maxWidth: .infinity).padding(6).background(.bar)
        } else if let rejection = session.rejection {
            Text(rejection.message).foregroundStyle(.red).frame(maxWidth: .infinity).padding(6).background(.bar)
        }
    }

    private func leave() {
        Task {
            await session.leave()
            onLeave()
        }
    }
}
