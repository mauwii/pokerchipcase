import PokerSession
import SwiftUI

@main
struct PokerChipCaseApp: App {
    @State private var session: TableSession?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup {
            Group {
                if let session {
                    TableScreen(session: session, onLeave: { self.session = nil })
                } else {
                    StartView(onSession: { session = $0 })
                }
            }
            // preferredColorScheme forces the window's scheme; themed() picks the theme from it.
            .themed()
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: session == nil, initial: true) { UIApplication.shared.isIdleTimerDisabled = session != nil }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await session?.appBecameActive() } }
            }
        }
    }
}
