import Foundation

/// A standalone Control hold. Input adapters supply monotonic time and discard key contents.
public struct ControlHoldGesture: Sendable {
    public static let duration: TimeInterval = 2
    private var startedAt: TimeInterval?
    private var lastSample: TimeInterval?
    private var requiresRelease = true

    public init() {}

    /// Returns true once per uninterrupted hold. Gaps cancel instead of firing after wake.
    public mutating func update(controlHeld: Bool, interrupted: Bool, at time: TimeInterval) -> Bool {
        defer { lastSample = time }
        guard time.isFinite else { requiresRelease = true; startedAt = nil; return false }
        guard controlHeld else { requiresRelease = false; startedAt = nil; return false }
        if startedAt != nil, let previous = lastSample, time < previous || time - previous > 0.5 {
            requiresRelease = true
        }
        if interrupted { requiresRelease = true }
        guard !requiresRelease else { startedAt = nil; return false }
        guard let startedAt else { self.startedAt = time; return false }
        guard time - startedAt >= Self.duration else { return false }
        requiresRelease = true
        self.startedAt = nil
        return true
    }
}
