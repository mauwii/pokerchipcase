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
        // Anna sends, so Anna's state must include Ben; otherwise the host rejects the start as .staleState.
        try await eventually { anna.state?.seats.count == 2 }
        await anna.send(.startTournament(button: anna.me!))
        #expect(anna.rejection == nil)
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

    @Test func guestIsToldWhenTheHostEndsTheTable() async throws {
        let anna = try await hostSession()
        let tickets: SaveFile<SeatTicket> = tempFile()
        let ben = await guestSession(anna, ticketFile: tickets)
        defer { Task { await ben.leave() } }
        try await eventually { ben.connection == .connected && tickets.load() != nil }
        await anna.leave()
        try await eventually { ben.connection == .failed(.tableClosed) }
        #expect(tickets.load() == nil)
    }

    @Test func failedSaveAndDeleteAreShownUntilTheyWorkAgain() async throws {
        let file: SaveFile<HostSnapshot> = tempFile()
        let anna = try await hostSession(file)
        try setReadOnly(file, true)
        let ben = await guestSession(anna)
        defer { Task { await ben.leave() } }
        try await eventually { anna.problem?.action == .save }
        #expect(await anna.leave() == false)
        #expect(anna.problem?.action == .delete)
        #expect(file.load() != nil)
        try setReadOnly(file, false)
        #expect(await anna.leave() == true)
        #expect(anna.problem == nil && file.load() == nil)
    }

    @Test func failedSendIsShown() async throws {
        let ben = await TableSession.join(endpoint: .hostPort(host: "127.0.0.1", port: 1), tableName: "Test",
                                          code: code4711, name: "Ben", ticketFile: tempFile())
        defer { Task { await ben.leave() } }
        await ben.send(.startNextHand)
        #expect(ben.problem?.action == .send && !ben.isSending)
    }

    @Test func failedStartRestoresThePreviousSave() async throws {
        let blocker = try await hostSession()  // occupies its port
        defer { Task { await blocker.leave() } }
        let empty: SaveFile<HostSnapshot> = tempFile()
        let new = HostSnapshot.newTable(hostName: "Cem", tableName: "New", code: code4711, config: .relaxed)
        await #expect(throws: (any Error).self) { try await TableSession.host(new, saveFile: empty, port: blocker.port!) }
        #expect(empty.load() == nil)
        let old: SaveFile<HostSnapshot> = tempFile()
        let saved = HostSnapshot.newTable(hostName: "Ben", tableName: "Old", code: code4711, config: .relaxed)
        try old.save(saved)
        await #expect(throws: (any Error).self) { try await TableSession.host(new, saveFile: old, port: blocker.port!) }
        #expect(old.load() == saved)
    }

    @Test func snapshotWithoutHostTokenThrows() async throws {
        var snap = HostSnapshot.newTable(hostName: "Anna", tableName: "Test", code: code4711, config: .relaxed)
        snap.tokens = [:]
        await #expect(throws: CocoaError.self) { try await TableSession.host(snap, saveFile: tempFile()) }
    }

    @Test func snapshotWithoutHostSeatThrows() async throws {
        var snap = HostSnapshot.newTable(hostName: "Anna", tableName: "Test", code: code4711, config: .relaxed)
        snap.game.state.seats = []
        await #expect(throws: CocoaError.self) { try await TableSession.host(snap, saveFile: tempFile()) }
    }

    @Test func appBecameActiveReconnectsTheHostClient() async throws {
        let anna = try await hostSession()
        defer { Task { await anna.leave() } }
        let h = anna.tableHost!
        // Like an iOS suspension: listener and every connection, the loopback client's too, are gone.
        await h.simulateListenerFailure()
        await h.disconnectAll()
        try await eventually { await !h.isListening && anna.connection == .reconnecting }
        await anna.appBecameActive()
        try await eventually { anna.connection == .connected }
        let cem = await guestSession(anna, name: "Cem")
        defer { Task { await cem.leave() } }
        // The host's own client receives broadcasts again.
        try await eventually { anna.state?.seats.count == 2 }
    }

    @Test func resumeOnNewPortViaBonjour() async throws {
        let name = "T-\(UUID().uuidString.prefix(8))"
        let file: SaveFile<HostSnapshot> = tempFile()
        let anna = try await TableSession.host(
            .newTable(hostName: "Anna", tableName: name, code: code4711, config: .relaxed), saveFile: file)
        defer { Task { await anna.leave() } }
        let ben = await TableSession.join(
            endpoint: .service(name: name, type: Wire.serviceType, domain: "local.", interface: nil),
            tableName: name, code: code4711, name: "Ben", ticketFile: tempFile())
        defer { Task { await ben.leave() } }
        try await eventually(timeout: .seconds(15)) { ben.me != nil }
        let p = ben.me
        // Crash without leave(), then relaunch on a new port like the app does.
        await anna.tableHost!.stop()
        await anna.client.disconnect()
        let resumed = try await TableSession.host(try #require(file.load()), saveFile: file)
        defer { Task { await resumed.leave() } }
        #expect(resumed.port != anna.port)
        try await eventually(timeout: .seconds(10)) { await resumed.tableHost!.connectedPlayers.contains(p!) }
    }
}
