import Foundation
import Network
import PokerCore
import Testing
@testable import PokerNet

/// A host with Anna (host client) and Ben connected, both past `welcome` and the 2-seat `state`.
private struct Table {
    let host: TableHost
    let port: NWEndpoint.Port
    let anna: RawClient
    let ben: RawClient
    let hostID: PlayerID
    let benWelcome: Welcome
    let version: Int

    static func open(onChange: @escaping @Sendable (HostSnapshot) -> Void = { _ in }) async throws -> Table {
        let (host, port) = try await startHost(onChange: onChange)
        let anna = try await RawClient.connect(port)
        anna.send(hello("Anna", token: await host.snapshot.hostToken))
        let hostID = try await anna.welcome().player
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        let benWelcome = try await ben.welcome()
        let state = try await anna.state { $0.seats.count == 2 }
        _ = try await ben.state { $0.seats.count == 2 }
        return Table(host: host, port: port, anna: anna, ben: ben, hostID: hostID, benWelcome: benWelcome, version: state.version)
    }

    func command(_ command: Command, version: Int? = nil) -> ClientMessage {
        .command(CommandRequest(command: command, stateVersion: version ?? self.version))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HostCommandTests {
    @Test func commandAckedAndBroadcast() async throws {
        let t = try await Table.open()
        let id = UUID()
        t.anna.send(t.command(.startTournament(button: t.hostID)), id: id)
        #expect(try await t.anna.ack() == Ack(id: id, result: .ok))
        _ = try await t.ben.state { $0.phase == .betting }
        await t.host.stop()
    }

    @Test func rejectedCommandAckedToSenderOnly() async throws {
        let t = try await Table.open()
        t.ben.send(t.command(.startTournament(button: t.hostID)))
        #expect(try await t.ben.ack().result == .rejected(reason: .notHost))
        #expect(await t.host.snapshot.game.state.phase == .lobby)
        await t.host.stop()
    }

    @Test func staleVersionRejected() async throws {
        let t = try await Table.open()
        t.anna.send(t.command(.startTournament(button: t.hostID), version: t.version - 1))
        #expect(try await t.anna.ack().result == .rejected(reason: .staleState))
        await t.host.stop()
    }

    @Test func commandBeforeHelloRejected() async throws {
        let t = try await Table.open()
        let cem = try await RawClient.connect(t.port)
        cem.send(t.command(.startNextHand))
        #expect(try await cem.error() == WireErrorCode.helloRequired.rawValue)
        cem.send(hello("Cem"))
        _ = try await cem.welcome()
        await t.host.stop()
    }

    @Test func malformedMessageGetsErrorAndConnectionStays() async throws {
        let t = try await Table.open()
        t.ben.sendRaw(Data("broken".utf8))
        #expect(try await t.ben.error() == WireErrorCode.malformed.rawValue)
        t.ben.send(t.command(.startNextHand))
        #expect(try await t.ben.ack().result == .rejected(reason: .invalidPhase))
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        _ = try await t.anna.state { $0.phase == .betting }
        await t.host.stop()
    }

    @Test func removedPlayerIsDisconnectedAndForgotten() async throws {
        let t = try await Table.open()
        t.anna.send(t.command(.removePlayer(player: t.benWelcome.player)))
        #expect(try await t.ben.error() == WireErrorCode.removed.rawValue)
        try await t.ben.waitForClose()
        #expect(await t.host.snapshot.tokens[t.benWelcome.token] == nil)
        let again = try await RawClient.connect(t.port)
        again.send(hello("Ben", token: t.benWelcome.token))
        #expect(try await again.welcome().player != t.benWelcome.player)
        await t.host.stop()
    }

    @Test func removedMidGameIsDisconnectedAndForgotten() async throws {
        let t = try await Table.open()
        let cem = try await RawClient.connect(t.port)
        cem.send(hello("Cem"))
        _ = try await cem.welcome()
        let state = try await t.anna.state { $0.seats.count == 3 }
        t.anna.send(t.command(.startTournament(button: t.hostID), version: state.version))
        let running = try await t.anna.state { $0.phase == .betting }
        t.anna.send(t.command(.removePlayer(player: t.benWelcome.player), version: running.version))
        #expect(try await t.ben.error() == WireErrorCode.removed.rawValue)
        try await t.ben.waitForClose()
        #expect(await t.host.snapshot.tokens[t.benWelcome.token] == nil)
        #expect(await t.host.snapshot.game.state.seat(t.benWelcome.player) != nil)  // seat kept mid-game
        await t.host.stop()
    }

    @Test func errorReplyCarriesRequestID() async throws {
        let t = try await Table.open()
        let id = UUID()
        let raw = #"{"id":"\#(id.uuidString)","payload":{"command":{"bogus":{}},"stateVersion":0},"type":"command","v":1}"#
        t.ben.sendRaw(Data(raw.utf8))
        let reply = try await t.ben.nextEnvelope { $0.error != nil }
        #expect(reply.message.error == WireErrorCode.malformed.rawValue && reply.id == id)
        await t.host.stop()
    }

    @Test func ensureListeningRestartsAfterListenerFailure() async throws {
        let (host, port) = try await startHost()
        await host.simulateListenerFailure()
        try await eventually { await !host.isListening }
        try await host.ensureListening()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        await host.stop()
    }

    @Test func ensureListeningRestartsBeforeTheStoppedCallback() async throws {
        let (host, port) = try await startHost()
        await host.simulateListenerFailure(callbackLost: true)
        try await eventually { await !host.isListening }
        try await host.ensureListening()
        #expect(await host.isListening)
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        await host.stop()
    }

    @Test func restartOnTheSamePortWhileListening() async throws {
        let (host, port) = try await startHost()
        #expect(try await host.start(port: port) == port)
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        await host.stop()
    }

    @Test func onChangeAfterCommand() async throws {
        let inbox = Inbox()
        let t = try await Table.open(onChange: { s in Task { await inbox.put(s) } })
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        _ = try await t.anna.ack()
        try await eventually { await inbox.last?.game.state.phase == .betting }
        await t.host.stop()
    }

    @Test func secondStartStopsTheFirstListener() async throws {
        let (host, first) = try await startHost()
        _ = try await host.start()
        // Host still running, so only a closed first listener (not the accept guard) can end this stream.
        let channel = MessageChannel(to: loopback(first), code: code4711)
        let rec = EventRecorder(channel.events)
        channel.start()
        #expect(try await rec.waitForEnd() != nil)
        await host.stop()
    }
}
