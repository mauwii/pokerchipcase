import Observation
import PokerNet
import SwiftUI

@MainActor @Observable final class NearbyTables {
    var tables: [DiscoveredTable] = []
    var localNetworkDenied = false

    /// Browses until the calling task is cancelled; a failed browser (iOS kills it in the background)
    /// is replaced by a fresh one after a second.
    func run() async {
        while !Task.isCancelled {
            let browser = TableBrowser()  // single-use
            browser.start()
            async let list: Void = follow(browser.tables)
            await follow(browser.status)  // returns on .failed or cancellation
            browser.stop()
            await list
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func follow(_ stream: AsyncStream<[DiscoveredTable]>) async {
        for await list in stream { tables = list }
    }

    private func follow(_ stream: AsyncStream<BrowserStatus>) async {
        for await status in stream {
            switch status {
            case .localNetworkDenied: localNetworkDenied = true
            case .browsing: localNetworkDenied = false
            case .failed: return
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
