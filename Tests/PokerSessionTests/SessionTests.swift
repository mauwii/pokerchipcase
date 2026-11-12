import Foundation
import Network
import Testing
@testable import PokerCore
@testable import PokerNet
@testable import PokerSession

@MainActor @Suite(.timeLimit(.minutes(1)))
struct SessionTests {
    @Test func hostCreatesTableAndJoinsItself() async throws {
        let file: SaveFile<HostSnapshot> = tempFile()
        let anna = try await hostSession(file)
        defer { Task { await anna.leave() } }
        #expect(anna.isHost && anna.connection == .connected)
        #expect(anna.me == anna.state?.hostID && anna.state?.seats.map(\.name) == ["Anna"])
        #expect(file.load()?.tableName == "Test")
    }

    @Test func guestJoinsAndSavesTicket() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let tickets: SaveFile<SeatTicket> = tempFile()
        let ben = await guestSession(anna, ticketFile: tickets)
        defer { Task { await ben.leave() } }
        try await eventually { anna.state?.seats.count == 2 && ben.connection == .connected }
        let ticket = try #require(tickets.load())
        #expect(!ben.isHost && ticket.tableName == "Test" && ticket.code == code4711 && ticket.name == "Ben")
    }

    @Test func rejectionIsShownUntilTheNextState() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let ben = await guestSession(anna)
        defer { Task { await ben.leave() } }
        try await eventually { ben.state?.seats.count == 2 }
        await ben.send(.startTournament(button: ben.me!))
        #expect(ben.rejection == .notHost && !ben.isSending)
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { ben.state?.phase == .betting && ben.rejection == nil }
    }

    @Test func turnAndDealerDecideWhatEachPlayerMayDo() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let ben = await guestSession(anna)
        defer { Task { await ben.leave() } }
        try await eventually { anna.state?.seats.count == 2 && ben.state?.seats.count == 2 }
        #expect(anna.canRunHand && !ben.canRunHand)
        await anna.send(.startTournament(button: ben.me!))
        try await eventually { anna.state?.phase == .betting && ben.state?.phase == .betting }
        #expect(ben.canRunHand)
        let state = try #require(ben.state)
        let toAct = state.seats[try #require(state.toActIndex)].id
        let (actor, other) = toAct == ben.me ? (ben, anna) : (anna, ben)
        #expect(actor.legalActions != nil && other.legalActions == nil)
        await actor.act(.call)
        #expect(actor.rejection == nil)
        try await eventually { other.state?.seat(toAct)?.acted == true && actor.legalActions == nil }
    }

    @Test func hostSavesEveryChange() async throws {
        let file: SaveFile<HostSnapshot> = tempFile()
        let anna = try await hostSession(file)
        defer { Task { await anna.leave() } }
        let ben = await guestSession(anna)
        defer { Task { await ben.leave() } }
        try await eventually { anna.state?.seats.count == 2 }
        await anna.send(.startTournament(button: anna.me!))
        #expect(anna.rejection == nil)
        try await eventually { file.load()?.game.state.phase == .betting }
    }

    @Test func guestReconnectsAfterDrop() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let ben = await guestSession(anna)
        defer { Task { await ben.leave() } }
        try await eventually { ben.connection == .connected }
        let p = ben.me
        await anna.tableHost!.disconnectAll()
        try await eventually { ben.connection == .reconnecting }
        try await eventually { ben.connection == .connected && ben.me == p }
        #expect(anna.state?.seats.count == 2)
    }

    @Test func appBecameActiveRestartsListener() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let h = anna.tableHost!
        await h.simulateListenerFailure()
        try await eventually { await !h.isListening }
        await anna.appBecameActive()
        try await eventually { await h.isListening }
        let cem = await guestSession(anna, name: "Cem")
        defer { Task { await cem.leave() } }
        try await eventually { anna.state?.seats.count == 2 }
    }

    @Test func resumeAfterHostCrash() async throws {
        let file: SaveFile<HostSnapshot> = tempFile()
        let anna = try await hostSession(file)
        defer { Task { await anna.leave() } }
        let ben = await guestSession(anna)
        defer { Task { await ben.leave() } }
        try await eventually { ben.state?.seats.count == 2 }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { ben.state?.phase == .betting && file.load()?.game.state.phase == .betting }
        let snap = try #require(file.load())
        let port = anna.port!
        let p = ben.me
        // Crash without leave().
        await anna.tableHost!.stop()
        await anna.client.disconnect()
        // stop() cancels the listener asynchronously; the old port can stay taken for a moment (EADDRINUSE on CI).
        var rebound: TableSession?
        for _ in 0..<50 where rebound == nil {
            rebound = try? await TableSession.host(snap, saveFile: file, port: port)
            if rebound == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        let resumed = try #require(rebound)
        defer { Task { await resumed.leave() } }
        try await eventually { resumed.state?.phase == .betting && resumed.me == snap.game.state.hostID }
        // ben still shows .connected until it notices the drop; only the new host proves the reconnect.
        try await eventually { await resumed.tableHost!.connectedPlayers.contains(p!) }
        try await eventually { ben.connection == .connected && ben.me == p }
    }

    @Test func rejoinWithTicketKeepsSeat() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let tickets: SaveFile<SeatTicket> = tempFile()
        let ben = await guestSession(anna, ticketFile: tickets)
        defer { Task { await ben.leave() } }
        try await eventually { ben.connection == .connected }
        let p = ben.me
        let ticket = try #require(tickets.load())
        // App killed.
        await ben.client.disconnect()
        let ben2 = await TableSession.join(
            endpoint: .hostPort(host: "127.0.0.1", port: anna.port!), tableName: ticket.tableName,
            code: ticket.code, name: ticket.name, token: ticket.token, ticketFile: tickets)
        defer { Task { await ben2.leave() } }
        try await eventually { ben2.me == p }
        #expect(anna.state?.seats.count == 2)
    }

    @Test func failedRejoinDeletesTicket() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let tickets: SaveFile<SeatTicket> = tempFile()
        try tickets.save(SeatTicket(tableName: "Test", code: code4711, name: "Ben", token: "old"))
        let ben = await guestSession(anna, token: "old", code: TableCode("0815")!, ticketFile: tickets)
        defer { Task { await ben.leave() } }
        try await eventually { ben.connection == .failed(.wrongCode) }
        #expect(tickets.load() == nil)
    }

    @Test func failedTokenlessJoinKeepsTicket() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let tickets: SaveFile<SeatTicket> = tempFile()
        let old = SeatTicket(tableName: "Old", code: code4711, name: "Ben", token: "old")
        try tickets.save(old)
        let ben = await guestSession(anna, code: TableCode("0815")!, ticketFile: tickets)
        defer { Task { await ben.leave() } }
        try await eventually { ben.connection == .failed(.wrongCode) }
        #expect(tickets.load() == old)
    }

    @Test func leaveDeletesSaveFiles() async throws {
        let file: SaveFile<HostSnapshot> = tempFile()
        let anna = try await hostSession(file)
        let tickets: SaveFile<SeatTicket> = tempFile()
        let ben = await guestSession(anna, ticketFile: tickets)
        try await eventually { ben.connection == .connected && tickets.load() != nil }
        await ben.leave()
        #expect(tickets.load() == nil)
        await anna.leave()
        #expect(file.load() == nil)
    }

    @Test func snapshotWithoutHostTokenThrows() async throws {
        var snap = HostSnapshot.newTable(hostName: "Anna", tableName: "Test", code: code4711, config: .relaxed)
        snap.tokens = [:]
        await #expect(throws: CocoaError.self) { try await TableSession.host(snap, saveFile: tempFile()) }
    }
}
