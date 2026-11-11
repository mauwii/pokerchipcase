import Foundation
import Network
import Testing
@testable import PokerNet

@Suite(.timeLimit(.minutes(1)))
struct ChannelTests {
    @Test func pskKeyMatchesTestVector() {
        let key = PSK.key(for: TableCode("4711")!)
        let hex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "67a659eb4579867f3873c0e9311b75f65b3d6d0b7c0c7cdc7687d0fb78f423f2")
    }

    @Test func tableCodeValidation() {
        #expect(TableCode("4711")?.digits == "4711" && TableCode("0815") != nil)
        #expect(TableCode("471") == nil && TableCode("47a1") == nil && TableCode("47111") == nil && TableCode("４７１１") == nil)
        #expect((0..<50).allSatisfy { _ in TableCode(TableCode.random().digits) != nil })
    }

    @Test func messagesArriveSeparately() async throws {
        let (listener, port) = try await startEchoListener(code: TableCode("4711")!)
        defer { listener.cancel() }
        let channel = MessageChannel(to: loopback(port), code: TableCode("4711")!)
        let rec = EventRecorder(channel.events)
        channel.start()
        _ = try await rec.first { $0 == .ready }
        channel.send(Data("eins".utf8))
        channel.send(Data("zwei".utf8))
        _ = try await rec.first { $0 == .message(Data("zwei".utf8)) }
        #expect(await rec.all == [.ready, .message(Data("eins".utf8)), .message(Data("zwei".utf8))])
        channel.cancel()
    }

    @Test func echoOverTLS() async throws {
        let (listener, port) = try await startEchoListener(code: TableCode("4711")!)
        defer { listener.cancel() }
        let channel = MessageChannel(to: loopback(port), code: TableCode("4711")!)
        let rec = EventRecorder(channel.events)
        channel.start()
        _ = try await rec.first { $0 == .ready }
        channel.send(Data("hallo".utf8))
        _ = try await rec.first { $0 == .message(Data("hallo".utf8)) }
        channel.cancel()
    }

    @Test func wrongCodeFailsHandshake() async throws {
        let (listener, port) = try await startEchoListener(code: TableCode("4711")!)
        defer { listener.cancel() }
        let channel = MessageChannel(to: loopback(port), code: TableCode("0815")!)
        let rec = EventRecorder(channel.events)
        channel.start()
        #expect(try await rec.waitForEnd() as? ChannelError == .handshakeFailed)
    }

    @Test func unreachableHostEndsStream() async throws {
        let channel = MessageChannel(to: loopback(1), code: TableCode("4711")!)
        let rec = EventRecorder(channel.events)
        channel.start()
        #expect(try await rec.waitForEnd() != nil)
    }
}
