import Foundation

public typealias Chips = Int
public typealias PlayerID = String

public struct BlindLevel: Codable, Equatable, Sendable {
    public var smallBlind: Chips
    public var bigBlind: Chips
    public var duration: TimeInterval

    public init(smallBlind: Chips, bigBlind: Chips, duration: TimeInterval) {
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.duration = duration
    }
}

public struct TournamentConfig: Codable, Equatable, Sendable {
    public var startingStack: Chips
    public var levels: [BlindLevel]

    public init(startingStack: Chips, levels: [BlindLevel]) {
        self.startingStack = startingStack
        self.levels = levels
    }

    private static let standardBlinds: [(Chips, Chips)] = [
        (10, 20), (15, 30), (25, 50), (50, 100), (75, 150),
        (100, 200), (150, 300), (200, 400), (300, 600), (500, 1000),
    ]

    private static func standard(levelDuration: TimeInterval) -> TournamentConfig {
        TournamentConfig(
            startingStack: 1000,
            levels: standardBlinds.map { BlindLevel(smallBlind: $0.0, bigBlind: $0.1, duration: levelDuration) }
        )
    }

    public static let relaxed = standard(levelDuration: 1200)
    public static let quick = standard(levelDuration: 600)
    public static let presets: [(name: String, config: TournamentConfig)] = [
        ("Relaxed – 20 min", relaxed),
        ("Quick – 10 min", quick),
    ]
}

public struct Seat: Codable, Equatable, Sendable {
    public var id: PlayerID
    public var name: String
    public var stack: Chips
    /// Bet in the current betting round.
    public var roundBet: Chips = 0
    /// Bet in the whole hand.
    public var handBet: Chips = 0
    public var stackAtHandStart: Chips = 0
    public var folded = false
    public var allIn = false
    public var acted = false
    public var mayRaise = true
    /// Final rank; nil while the player is still in the tournament (and for the winner).
    public var eliminatedRank: Int?

    public init(id: PlayerID, name: String, stack: Chips) {
        self.id = id
        self.name = name
        self.stack = stack
    }

    public var isEliminated: Bool { eliminatedRank != nil }
}

public enum Phase: String, Codable, Equatable, Sendable {
    case lobby, betting, showdown, handComplete, finished
}

public enum Street: String, Codable, Equatable, Sendable {
    case preflop, flop, turn, river
}

public struct Pot: Codable, Equatable, Sendable {
    public var amount: Chips
    public var eligible: [PlayerID]
}

public struct BlindClock: Codable, Equatable, Sendable {
    public var levelIndex = 0
    public var levelEndsAt: Date?
    public var pausedRemaining: TimeInterval?

    public init() {}
}

public struct GameState: Codable, Equatable, Sendable {
    public var config: TournamentConfig
    public var hostID: PlayerID
    public var seats: [Seat]
    public var phase: Phase = .lobby
    public var street: Street = .preflop
    public var buttonIndex: Int?
    public var handNumber = 0
    public var currentBet: Chips = 0
    public var lastRaiseSize: Chips = 0
    public var toActIndex: Int?
    public var pots: [Pot] = []
    public var clock = BlindClock()
    /// Increases with every change (undo too); clients send it back so late double taps get rejected.
    public var version = 0

    public init(config: TournamentConfig, hostID: PlayerID, seats: [Seat]) {
        self.config = config
        self.hostID = hostID
        self.seats = seats
    }

    public func seat(_ id: PlayerID) -> Seat? {
        seats.first { $0.id == id }
    }

    func index(of id: PlayerID) -> Int? {
        seats.firstIndex { $0.id == id }
    }
}
