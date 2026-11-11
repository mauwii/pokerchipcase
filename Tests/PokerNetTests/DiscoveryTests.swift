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

    @Test func browserReportsDeniedLocalNetwork() {
        let denied = NWBrowser.State.waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)))
        #expect(TableBrowser.status(for: denied) == .localNetworkDenied)
        #expect(TableBrowser.status(for: .ready) == .browsing)
        #expect(TableBrowser.status(for: .failed(.posix(.ENETDOWN))) == .failed)
        #expect(TableBrowser.status(for: .setup) == nil)
    }

    @Test func stoppedHostDisappears() async throws {
        let (host, name) = try await advertisedHost()
        let browser = TableBrowser()
        let lists = EventRecorder(browser.tables)
        browser.start()
        _ = try await lists.first(timeout: discoveryTimeout) { $0.contains { $0.name == name } }
        await host.stop()
        try await eventually(timeout: discoveryTimeout) { await lists.all.last.map { !$0.contains { $0.name == name } } ?? false }
        browser.stop()
    }
}
