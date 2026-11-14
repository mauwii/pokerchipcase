import PokerSession
import SwiftUI

@main
struct PokerChipCaseApp: App {
    @State private var session: TableSession?
    /// Browses for the whole app life, also at the table: iOS tears down an AWDL link about 30 s
    /// after the last browser on the device stops, which drops a table without a shared Wi-Fi (#39).
    @State private var nearby = NearbyTables()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup {
            Group {
                if let session {
                    TableScreen(session: session, onLeave: { self.session = nil })
                } else {
                    StartView(onSession: { session = $0 }, nearby: nearby)
                }
            }
            // preferredColorScheme forces the window's scheme; themed() picks the theme from it.
            .task { await nearby.run() }
            .themed()
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: session == nil, initial: true) { UIApplication.shared.isIdleTimerDisabled = session != nil }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await session?.appBecameActive() } }
            }
        }
    }
}
