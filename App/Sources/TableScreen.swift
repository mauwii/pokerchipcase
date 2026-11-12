import PokerCore
import PokerNet
import PokerSession
import SwiftUI

struct TableScreen: View {
    let session: TableSession
    let onLeave: () -> Void
    @State private var confirmLeave = false
    @State private var hostPending: HostConfirm?

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
            // Here, not in ActionBar: that is re-inserted every hand with the trigger already true.
            .sensoryFeedback(.impact(weight: .heavy), trigger: session.legalActions != nil ? session.state?.street : nil) { $1 != nil }
            .toolbar {
                Menu("Table", systemImage: "ellipsis.circle") {
                    if session.isHost, let state = session.state, state.phase != .lobby {
                        HostMenu(session: session, state: state, pending: $hostPending)
                        Divider()
                    }
                    Button(session.isHost ? "End table" : "Leave table", role: .destructive) { confirmLeave = true }
                }
            }
            .hostConfirmation($hostPending, session: session)
            .confirmationDialog(
                session.isHost ? "End the table for everyone?" : "Leave the table? You can't rejoin once the tournament has started.",
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
