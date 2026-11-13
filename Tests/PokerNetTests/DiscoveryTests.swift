import Foundation
import Network
import PokerCore
import Testing
@testable import PokerNet

/// mDNS can be slow on a cold start (first run of a new service type).
private let discoveryTimeout: Duration = .seconds(15)

/// Starts a host advertising a unique table name.
private func advertisedHost() async throws -> (TableHost, String) {
    let name = "Kitchen-\(UUID().uuidString.prefix(6))"
    let host = TableHost(snapshot: .newTable(hostName: "Anna", tableName: name, code: code4711, config: .relaxed))
    _ = try await host.start()
    return (host, name)
}

@Suite(.timeLimit(.minutes(1)))
struct DiscoveryTests {
    @Test func hostAdvertisesTableName() async throws {
        let (host, name) = try await advertisedHost()
        let browser = TableBrowser()
        let lists = EventRecorder(browser.tables)
        browser.start()
        _ = try await lists.first(timeout: discoveryTimeout) { $0.contains { $0.name == name } }
        browser.stop()
        await host.stop()
    }

    @Test func clientConnectsViaDiscoveredEndpoint() async throws {
        let (host, name) = try await advertisedHost()
        let browser = TableBrowser()
        let lists = EventRecorder(browser.tables)
        browser.start()
        let table = try await lists.first(timeout: discoveryTimeout) { $0.contains { $0.name == name } }.first { $0.name == name }!
        browser.stop()

        let ben = TableClient(endpoint: table.endpoint, code: code4711, name: "Ben", retryDelay: .milliseconds(100))
        let events = EventRecorder(ben.events)
        await ben.connect()
        _ = try await events.first(timeout: discoveryTimeout) { if case .welcome = $0 { true } else { false } }
        await ben.disconnect()
        await host.stop()
    }

    /// Over a Bonjour endpoint Network.framework retries a failed TLS handshake forever unless the channel
    /// resolves the service first (#50).
    @Test func wrongCodeViaBonjourFailsWithoutRetry() async throws {
        let (host, name) = try await advertisedHost()
        let ben = TableClient(endpoint: .service(name: name, type: Wire.serviceType, domain: "local.", interface: nil),
                              code: TableCode("0815")!, name: "Ben", retryDelay: .milliseconds(100))
        let events = EventRecorder(ben.events)
        await ben.connect()
        _ = try await events.first(timeout: discoveryTimeout) { $0 == .failed(.wrongCode) }
        #expect(await events.all == [.failed(.wrongCode)])
        await ben.disconnect()
        await host.stop()
    }

    @Test func browserReportsDeniedLocalNetwork() {
        let denied = NWBrowser.State.waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)))
        #expect(TableBrowser.status(for: denied) == .localNetworkDenied)
        #expect(TableBrowser.status(for: .ready) == .browsing)
        #expect(TableBrowser.status(for: .failed(.posix(.ENETDOWN))) == .failed)
        #expect(TableBrowser.status(for: .setup) == nil)
    }

    @Test func duplicatesKeepThePreferredInterface() {
        func table(_ name: String, _ port: NWEndpoint.Port) -> DiscoveredTable { DiscoveredTable(name: name, endpoint: loopback(port)) }
        let found: [(table: DiscoveredTable, type: NWInterface.InterfaceType?, interface: String)] = [
            (table("B", 1), .other, "bridge100"), (table("A", 1), .other, "awdl0"), (table("B", 2), .wifi, "en0"),
            (table("A", 2), .wiredEthernet, "en5"), (table("B", 3), .loopback, "lo0"), (table("A", 3), .other, "anpi0"),
        ]
        let expected = [table("A", 2), table("B", 2)]
        #expect(TableBrowser.unique(found) == expected && TableBrowser.unique(found.reversed()) == expected)
        // Same type: the interface name decides, whatever the order.
        let awdl = [(table("C", 1), NWInterface.InterfaceType.other, "awdl0"), (table("C", 2), .other, "bridge100")]
        #expect(TableBrowser.unique(awdl) == [table("C", 1)] && TableBrowser.unique(awdl.reversed()) == [table("C", 1)])
    }

    @Test func stoppedHostDisappears() async throws {
        let (host, name) = try await advertisedHost()
        let browser = TableBrowser()
        let lists = EventRecorder(browser.tables)
        browser.start()
        _ = try await lists.first(timeout: discoveryTimeout) { $0.contains { $0.name == name } }
        await host.stop()
        let gone: @Sendable () async -> Bool = { await !(lists.all.last?.contains { $0.name == name } ?? true) }
        try await eventually(timeout: discoveryTimeout, gone)
        browser.stop()
    }
}
