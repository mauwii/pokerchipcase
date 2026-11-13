import Foundation
import Network
import PokerNet
import Testing
@testable import PokerCore
@testable import PokerSession

@Test func savesIntoAMissingDirectoryAndLoads() throws {
    let file: SaveFile<SeatTicket> = tempFile()
    let ticket = SeatTicket(tableName: "Kitchen", code: code4711, name: "Ben", token: "t")
    try file.save(ticket)
    #expect(file.load() == ticket)
}

@Test func missingOrCorruptFileLoadsNil() throws {
    let file: SaveFile<SeatTicket> = tempFile()
    #expect(file.load() == nil)
    try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: file.url)
    #expect(file.load() == nil)
}

@Test func deleteRemovesTheFile() throws {
    let file: SaveFile<SeatTicket> = tempFile()
    try file.save(SeatTicket(tableName: "K", code: code4711, name: "Ben", token: "t"))
    try file.delete()
    #expect(file.load() == nil)
    try file.delete()  // missing is no error
}

@Test func deleteThatCannotRemoveTheFileThrows() throws {
    let file: SaveFile<SeatTicket> = tempFile()
    try file.save(SeatTicket(tableName: "K", code: code4711, name: "Ben", token: "t"))
    try setReadOnly(file, true)
    defer { try? setReadOnly(file, false) }
    #expect(throws: CocoaError.self) { try file.delete() }
    #expect(file.load() != nil)
}

@Test func hostSnapshotRoundTripsExactly() throws {
    var snap = HostSnapshot.newTable(hostName: "Anna", tableName: "T", code: code4711, config: .relaxed)
    try snap.game.apply(.join(player: "B", name: "B"), by: snap.game.state.hostID, at: Date())
    try snap.game.apply(.startTournament(button: snap.game.state.hostID), by: snap.game.state.hostID, at: Date())
    let file: SaveFile<HostSnapshot> = tempFile()
    try file.save(snap)
    #expect(file.load() == snap)
}

@Test func onlyRunningTablesWithAHostTokenAreResumable() throws {
    let fresh = HostSnapshot.newTable(hostName: "Anna", tableName: "T", code: code4711, config: .relaxed)
    #expect(fresh.isResumable)
    var noToken = fresh; noToken.tokens = [:]
    #expect(!noToken.isResumable)
    var finished = fresh; finished.game.state.phase = .finished
    #expect(!finished.isResumable)
}

@Test func ticketEndpointIsTheBonjourService() {
    let t = SeatTicket(tableName: "Kitchen", code: code4711, name: "Ben", token: "t")
    #expect(t.endpoint == .service(name: "Kitchen", type: "_pokerchipcase._tcp", domain: "local.", interface: nil))
}
