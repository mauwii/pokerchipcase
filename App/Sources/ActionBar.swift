import PokerCore
import PokerSession
import SwiftUI

struct ActionBar: View {
    let session: TableSession
    let state: GameState
    @State private var raiseTo: Chips = 0
    @State private var pending: Action?

    init(session: TableSession, state: GameState) {
        self.session = session
        self.state = state
    }

    @Environment(\.theme) private var theme

    private var legal: LegalActions? { session.legalActions }
    private var disabled: Bool { legal == nil || session.isSending }
    private var stack: Chips { session.me.flatMap { state.seat($0)?.stack } ?? 0 }

    var body: some View {
        VStack(spacing: 10) {
            if let lo = legal?.minRaiseTo, let hi = legal?.maxRaiseTo {
                if lo < hi {
                    Slider(
                        value: Binding(get: { Double(min(max(raiseTo, lo), hi)) }, set: { raiseTo = Int($0) }),
                        in: Double(lo)...Double(hi), step: Double(max(1, state.currentLevel.smallBlind)))
                    HStack {
                        ForEach(quickPicks, id: \.kind) { pick in
                            Button("\(label(pick.kind)) \(pick.raiseTo)") { raiseTo = pick.raiseTo }
                                .font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .overlay(Capsule().strokeBorder(theme.muted))
                        }
                    }
                }
            }
            HStack {
                Button("Fold", role: .destructive) { request(.fold) }.buttonStyle(ThemeButtonStyle(.fold))
                if legal?.canCheck ?? false {
                    Button("Check") { request(.check) }
                } else {
                    Button(legal.map { "Call \($0.callAmount)" } ?? "Call") { request(.call) }
                }
                if let lo = legal?.minRaiseTo, let hi = legal?.maxRaiseTo {
                    let x = min(max(raiseTo, lo), hi)
                    Button(state.currentBet == 0 ? "Bet \(x)" : "Raise to \(x)") { request(.raiseTo(amount: x)) }
                }
            }
            .buttonStyle(ThemeButtonStyle())
        }
        .disabled(disabled)
        .padding(.bottom)
        .onChange(of: state.version, initial: true) {
            raiseTo = legal?.minRaiseTo ?? 0
            pending = nil
        }
        .confirmationDialog("All-in with \(stack) chips?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("All-in", role: .destructive) {
                if let action = pending { Task { await session.act(action) } }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    private var quickPicks: [QuickPick] { session.me.map { state.quickPicks(for: $0) } ?? [] }

    private func label(_ kind: QuickPick.Kind) -> String {
        switch kind {
        case .halfPot: "½ Pot"
        case .pot: "Pot"
        case .allIn: "All-in"
        }
    }

    private func request(_ action: Action) {
        if let me = session.me, state.commitsAllChips(action, by: me) {
            pending = action
        } else {
            Task { await session.act(action) }
        }
    }
}
