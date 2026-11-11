import Foundation

extension BlindClock {
    public var isPaused: Bool { pausedRemaining != nil }

    public func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let levelEndsAt else { return 0 }
        return max(0, levelEndsAt.timeIntervalSince(now))
    }

    /// Advances expired levels; the last level stays forever.
    mutating func advance(to now: Date, levels: [BlindLevel]) {
        guard !isPaused, var endsAt = levelEndsAt else { return }
        while levelIndex < levels.count - 1, now >= endsAt {
            levelIndex += 1
            endsAt += levels[levelIndex].duration
        }
        levelEndsAt = endsAt
    }

    mutating func pause(at now: Date) {
        pausedRemaining = remaining(at: now)
        levelEndsAt = nil
    }

    mutating func resume(at now: Date) {
        levelEndsAt = now + (pausedRemaining ?? 0)
        pausedRemaining = nil
    }
}
