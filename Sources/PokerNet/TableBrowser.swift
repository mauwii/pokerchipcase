import Foundation
import Network
import PokerCore

/// A table found nearby, with the Bonjour endpoint to connect to.
public struct DiscoveredTable: Hashable, Sendable {
    public var name: String
    public var endpoint: NWEndpoint
}

/// Health of a ``TableBrowser``.
public enum BrowserStatus: Equatable, Sendable {
    case browsing, localNetworkDenied, failed
}

/// Finds tables nearby via Bonjour (Wi-Fi and peer-to-peer). One-shot: after `stop()` or a failure,
/// create a new browser.
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
            continuation.yield(Self.unique(results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                let interface = result.interfaces.first
                return (DiscoveredTable(name: name, endpoint: result.endpoint), interface?.type, interface?.name ?? "")
            }))
        }
        browser.stateUpdateHandler = { [continuation, statusContinuation] state in
            if let status = Self.status(for: state) { statusContinuation.yield(status) }
            if case .failed = state { continuation.finish() }
        }
        browser.start(queue: queue)
    }

    /// The same table shows up once per interface; keep the one on the most preferred interface
    /// (Wi-Fi, wired, other such as AWDL, then the rest), ties broken by interface name. Sorted by name.
    static func unique(_ found: [(table: DiscoveredTable, type: NWInterface.InterfaceType?, interface: String)]) -> [DiscoveredTable] {
        let preference: [NWInterface.InterfaceType?] = [.wifi, .wiredEthernet, .other]
        let rank = { (type: NWInterface.InterfaceType?) in preference.firstIndex(of: type) ?? preference.count }
        let best = Dictionary(found.map { ($0.table.name, $0) }) { a, b in
            (rank(a.type), a.interface) <= (rank(b.type), b.interface) ? a : b
        }
        return best.values.map(\.table).sorted { $0.name < $1.name }
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
