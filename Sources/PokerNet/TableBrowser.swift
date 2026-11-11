import Foundation
import Network
import PokerCore

public struct DiscoveredTable: Hashable, Sendable {
    public var name: String
    public var endpoint: NWEndpoint
}

public enum BrowserStatus: Equatable, Sendable {
    case browsing, localNetworkDenied, failed
}

/// Finds tables nearby via Bonjour (Wi-Fi and peer-to-peer).
/// ponytail: @unchecked Sendable, NWBrowser is confined to `queue`
public final class TableBrowser: @unchecked Sendable {
    /// The current list of tables, delivered on every change.
    public let tables: AsyncStream<[DiscoveredTable]>
    /// Browser health; `.localNetworkDenied` means the user must allow local network access in Settings.
    public let status: AsyncStream<BrowserStatus>
    private let continuation: AsyncStream<[DiscoveredTable]>.Continuation
    private let statusContinuation: AsyncStream<BrowserStatus>.Continuation
    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "pokernet.browser")

    public init() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: Wire.serviceType, domain: nil), using: parameters)
        (tables, continuation) = AsyncStream.makeStream()
        (status, statusContinuation) = AsyncStream.makeStream()
    }

    public func start() {
        browser.browseResultsChangedHandler = { [continuation] results, _ in
            var seen = Set<String>()
            let tables = results.compactMap { result -> DiscoveredTable? in
                // The same table shows up once per interface; keep the first.
                guard case let .service(name, _, _, _) = result.endpoint, seen.insert(name).inserted else { return nil }
                return DiscoveredTable(name: name, endpoint: result.endpoint)
            }
            continuation.yield(tables.sorted { $0.name < $1.name })
        }
        browser.stateUpdateHandler = { [continuation, statusContinuation] state in
            if let status = Self.status(for: state) { statusContinuation.yield(status) }
            if case .failed = state { continuation.finish() }
        }
        browser.start(queue: queue)
    }

    static func status(for state: NWBrowser.State) -> BrowserStatus? {
        switch state {
        case .ready: .browsing
        case .waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))): .localNetworkDenied
        case .failed: .failed
        default: nil
        }
    }

    public func stop() {
        browser.cancel()
        continuation.finish()
        statusContinuation.finish()
    }
}
