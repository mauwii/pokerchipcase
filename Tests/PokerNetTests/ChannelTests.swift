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
        channel.send(Data("one".utf8))
        channel.send(Data("two".utf8))
        _ = try await rec.first { $0 == .message(Data("two".utf8)) }
        #expect(await rec.all == [.ready, .message(Data("one".utf8)), .message(Data("two".utf8))])
        channel.cancel()
    }

    @Test func echoOverTLS() async throws {
        let (listener, port) = try await startEchoListener(code: TableCode("4711")!)
        defer { listener.cancel() }
        let channel = MessageChannel(to: loopback(port), code: TableCode("4711")!)
        let rec = EventRecorder(channel.events)
        channel.start()
        _ = try await rec.first { $0 == .ready }
        channel.send(Data("hello".utf8))
        _ = try await rec.first { $0 == .message(Data("hello".utf8)) }
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

    @Test func oversizedMessageEndsTheReceiversStream() async throws {
        let (listener, port, channels) = try await startRecordingListener()
        defer { listener.cancel() }
        let sender = MessageChannel(to: loopback(port), code: code4711)
        defer { sender.cancel() }
        let rec = EventRecorder(sender.events)
        sender.start()
        _ = try await rec.first { $0 == .ready }
        // Two receive chunks (64 KiB each) beyond the limit, so the newline cannot arrive before the check.
        sender.send(Data(repeating: UInt8(ascii: "a"), count: MessageChannel.maxMessageSize + 131_072))
        var it = channels.makeAsyncIterator()
        let receiver = try #require(await it.next())
        #expect(try await receiver.waitForEnd() as? ChannelError == .messageTooLarge)
    }

    @Test func messageAtTheLimitArrives() async throws {
        let (listener, port) = try await startEchoListener(code: code4711)
        defer { listener.cancel() }
        let channel = MessageChannel(to: loopback(port), code: code4711)
        let rec = EventRecorder(channel.events)
        channel.start()
        _ = try await rec.first { $0 == .ready }
        let big = Data(repeating: UInt8(ascii: "a"), count: MessageChannel.maxMessageSize)
        channel.send(big)
        _ = try await rec.first { $0 == .message(big) }
        channel.cancel()
    }
}

/// PSK listener that hands every accepted channel's recorder to `channels`.
private func startRecordingListener() async throws -> (NWListener, NWEndpoint.Port, AsyncStream<EventRecorder<ChannelEvent>>) {
    let (channels, inbox) = AsyncStream<EventRecorder<ChannelEvent>>.makeStream()
    let listener = try NWListener(using: PSK.parameters(code: code4711), on: .any)
    listener.newConnectionHandler = { connection in
        let channel = MessageChannel(connection: connection)
        inbox.yield(EventRecorder(channel.events))
        channel.start()
    }
    return (listener, try await listener.startAndWaitUntilReady(queue: .global()), channels)
}
