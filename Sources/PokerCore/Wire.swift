import Foundation

public struct Hello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var name: String
    /// Reconnect token from an earlier `welcome`.
    public var token: String?

    public init(protocolVersion: Int, name: String, token: String?) {
        self.protocolVersion = protocolVersion
        self.name = name
        self.token = token
    }
}

public struct Welcome: Codable, Equatable, Sendable {
    public var player: PlayerID
    public var token: String

    public init(player: PlayerID, token: String) {
        self.player = player
        self.token = token
    }
}

public enum AckResult: Codable, Equatable, Sendable {
    case ok
    case rejected(reason: Rejection)
}

public struct Ack: Codable, Equatable, Sendable {
    /// `id` of the client message being answered.
    public var id: UUID
    public var result: AckResult

    public init(id: UUID, result: AckResult) {
        self.id = id
        self.result = result
    }
}

public struct CommandRequest: Codable, Equatable, Sendable {
    public var command: Command
    /// `GameState.version` of the last `state` the client saw.
    public var stateVersion: Int

    public init(command: Command, stateVersion: Int) {
        self.command = command
        self.stateVersion = stateVersion
    }
}

public enum ClientMessage: Equatable, Sendable {
    case hello(Hello)
    case command(CommandRequest)
}

public enum ServerMessage: Equatable, Sendable {
    case welcome(Welcome)
    case ack(Ack)
    case state(GameState)
    case error(String)
}

/// Machine-readable codes sent as the payload of `ServerMessage.error`.
public enum WireErrorCode: String, Sendable {
    case versionMismatch, tableFull, gameInProgress, helloRequired, malformed
}

public enum WireError: Error, Equatable {
    case versionMismatch(Int)
    case unknownType(String)
}

/// JSON envelope `{"v": 1, "type": "<case>", "id": "<UUID>", "payload": …}`, see docs/PROTOCOL.md.
public enum Wire {
    public static let version = 1
    public static let serviceType = "_pokerchipcase._tcp"

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = .sortedKeys
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }

    public static func encode(_ message: ClientMessage, id: UUID) throws -> Data {
        switch message {
        case let .hello(p): try envelope("hello", p, id)
        case let .command(p): try envelope("command", p, id)
        }
    }

    public static func encode(_ message: ServerMessage, id: UUID) throws -> Data {
        switch message {
        case let .welcome(p): try envelope("welcome", p, id)
        case let .ack(p): try envelope("ack", p, id)
        case let .state(p): try envelope("state", p, id)
        case let .error(p): try envelope("error", p, id)
        }
    }

    public static func decodeClient(_ data: Data) throws -> (id: UUID, message: ClientMessage) {
        let h = try header(data)
        switch h.type {
        case "hello": return (h.id, .hello(try payload(data)))
        case "command": return (h.id, .command(try payload(data)))
        default: throw WireError.unknownType(h.type)
        }
    }

    public static func decodeServer(_ data: Data) throws -> (id: UUID, message: ServerMessage) {
        let h = try header(data)
        switch h.type {
        case "welcome": return (h.id, .welcome(try payload(data)))
        case "ack": return (h.id, .ack(try payload(data)))
        case "state": return (h.id, .state(try payload(data)))
        case "error": return (h.id, .error(try payload(data)))
        default: throw WireError.unknownType(h.type)
        }
    }

    private struct Envelope<P: Encodable>: Encodable {
        var v: Int
        var type: String
        var id: UUID
        var payload: P
    }

    private struct Header: Decodable {
        var v: Int
        var type: String
        var id: UUID
    }

    private struct Body<P: Decodable>: Decodable {
        var payload: P
    }

    private static func envelope(_ type: String, _ payload: some Encodable, _ id: UUID) throws -> Data {
        try encoder.encode(Envelope(v: version, type: type, id: id, payload: payload))
    }

    private static func header(_ data: Data) throws -> Header {
        let h = try decoder.decode(Header.self, from: data)
        guard h.v == version else { throw WireError.versionMismatch(h.v) }
        return h
    }

    private static func payload<P: Decodable>(_ data: Data) throws -> P {
        try decoder.decode(Body<P>.self, from: data).payload
    }
}
