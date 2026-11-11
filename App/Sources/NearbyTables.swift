import Observation
import PokerNet
import SwiftUI

@MainActor @Observable final class NearbyTables {
    var tables: [DiscoveredTable] = []
    var localNetworkDenied = false

    /// Browses with a fresh TableBrowser until the calling task is cancelled, then stops it.
    func run() async {
        let browser = TableBrowser()  // single-use
        browser.start()
        defer { browser.stop() }
        async let list: Void = follow(browser.tables)
        async let status: Void = follow(browser.status)
        _ = await (list, status)
    }

    private func follow(_ stream: AsyncStream<[DiscoveredTable]>) async {
        for await list in stream { tables = list }
    }

    private func follow(_ stream: AsyncStream<BrowserStatus>) async {
        for await status in stream {
            switch status {
            case .localNetworkDenied: localNetworkDenied = true
            case .browsing: localNetworkDenied = false
            case .failed: break
            }
        }
    }
}

struct LocalNetworkNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PokerChipCase needs local network access to find and host tables. Allow it in Settings.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }
}
