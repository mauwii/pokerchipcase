import Foundation
import Network
import Testing
@testable import PokerNet

// TEMP: CI probe, removed again in the next commit.
@Test func probeCancelledListener() async throws {
    for round in 0..<30 {
        let (listener, port) = try await startEchoListener(code: code4711)
        listener.cancel()
        try await Task.sleep(for: .milliseconds(100))
        let c = NWConnection(to: loopback(port), using: PSK.parameters(code: code4711))
        c.stateUpdateHandler = { s in
            switch s {
            case .preparing, .setup, .cancelled: break
            default: print("PROBE round \(round) port \(port): \(s)")
            }
        }
        c.start(queue: .global())
        try await Task.sleep(for: .milliseconds(300))
        c.cancel()
    }
}
