import Foundation

/// A standalone Control hold. Input adapters supply monotonic time and discard key contents.
public struct ControlHoldGesture: Sendable {
    public static let duration: TimeInterval = 1
    private var startedAt: TimeInterval?
    private var lastSample: TimeInterval?
    private var lastReleasedAt: TimeInterval?
    private var requiresRelease = true

    public init() {}

    public var deadline: TimeInterval? { startedAt.map { $0 + Self.duration } }

    /// Returns true once per uninterrupted hold. Gaps cancel instead of firing after wake.
    public mutating func update(controlHeld: Bool, interrupted: Bool, at time: TimeInterval, pressedAt: TimeInterval? = nil) -> Bool {
        defer { lastSample = time }
        guard time.isFinite else { requiresRelease = true; startedAt = nil; return false }
        guard controlHeld else {
            requiresRelease = false; startedAt = nil; lastReleasedAt = time
            return false
        }
        if startedAt != nil, let previous = lastSample, time < previous || time - previous > 0.5 {
            requiresRelease = true
        }
        if interrupted { requiresRelease = true }
        guard !requiresRelease else { startedAt = nil; return false }
        if startedAt == nil {
            let origin = pressedAt ?? time
            // A delayed first sample is valid when its origin follows the confirmed release.
            guard origin.isFinite, origin <= time,
                  let lastReleasedAt, origin > lastReleasedAt else {
                requiresRelease = true
                return false
            }
            startedAt = origin
        }
        guard let startedAt else { return false }
        guard time - startedAt >= Self.duration else { return false }
        requiresRelease = true
        self.startedAt = nil
        return true
    }
}
