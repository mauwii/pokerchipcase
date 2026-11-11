import Foundation
import Testing
@testable import PokerCore

private let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

private func json(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

@Test func commandGoldenJSON() throws {
    let data = try Wire.encode(ClientMessage.command(.act(player: "B", action: .raiseTo(amount: 60))), id: id1)
    #expect(json(data) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"act":{"action":{"raiseTo":{"amount":60}},"player":"B"}},"type":"command","v":1}"#)
}

@Test func ackGoldenJSON() throws {
    let data = try Wire.encode(ServerMessage.ack(Ack(id: id1, result: .rejected(reason: .notYourTurn))), id: id1)
    #expect(json(data) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"id":"00000000-0000-0000-0000-000000000001","result":{"rejected":{"reason":"notYourTurn"}}},"type":"ack","v":1}"#)
}

@Test func helloGoldenJSON() throws {
    let data = try Wire.encode(ClientMessage.hello(Hello(protocolVersion: 1, name: "Anna", token: nil)), id: id1)
    #expect(json(data) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Anna","protocolVersion":1},"type":"hello","v":1}"#)
}

@Test func clientRoundTrip() throws {
    for message: ClientMessage in [
        .hello(Hello(protocolVersion: 1, name: "Ben", token: "t")),
        .command(.resolveShowdown(winners: [["A", "B"]])),
        .command(.undo),
    ] {
        let decoded = try Wire.decodeClient(Wire.encode(message, id: id1))
        #expect(decoded.id == id1 && decoded.message == message)
    }
}

@Test func serverRoundTrip() throws {
    var g = try Game.started()
    try g.apply(.pauseClock, by: "A", at: t0 + 1.5)
    for message: ServerMessage in [
        .state(g.state),
        .welcome(Welcome(player: "B", token: "secret")),
        .ack(Ack(id: id1, result: .ok)),
        .error("kaputt"),
    ] {
        let decoded = try Wire.decodeServer(Wire.encode(message, id: id1))
        #expect(decoded.id == id1 && decoded.message == message)
    }
}

@Test func versionMismatchRejected() {
    let data = Data(#"{"v":2,"type":"hello","id":"00000000-0000-0000-0000-000000000001","payload":{}}"#.utf8)
    #expect(throws: WireError.versionMismatch(2)) { try Wire.decodeClient(data) }
}

@Test func unknownTypeRejected() {
    let data = Data(#"{"v":1,"type":"bogus","id":"00000000-0000-0000-0000-000000000001","payload":{}}"#.utf8)
    #expect(throws: WireError.unknownType("bogus")) { try Wire.decodeClient(data) }
}
