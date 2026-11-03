import Foundation

public enum DesktopAutoHideGeometry {
    public static func handle(resting: CGRect, screens: [CGRect], physicalScreens: [CGRect]? = nil) -> CGRect? {
        guard resting.width > 0, resting.height > 0,
              let screen = WindowPlacement.visibleScreen(for: resting, screens: screens),
              screen.width >= 10, screen.height >= 56 else { return nil }
        let left = abs(resting.minX - screen.minX) <= 32
        let right = abs(resting.maxX - screen.maxX) <= 32
        guard left || right else { return nil }
        let x = left ? screen.minX : screen.maxX - 10
        let y = min(screen.maxY - 56, max(screen.minY, resting.midY - 28))
        // A seam between two displays is not an exposed desktop edge.
        let physical = physicalScreens?.count == screens.count ? physicalScreens! : screens
        let physicalScreen = physical[screens.firstIndex(of: screen)!]
        let shared = physical.contains { other in
            other != physicalScreen && other.maxY > y && other.minY < y + 56 &&
                (left ? abs(other.maxX - physicalScreen.minX) <= 2 : abs(other.minX - physicalScreen.maxX) <= 2)
        }
        return shared ? nil : CGRect(x: x, y: y, width: 10, height: 56)
    }

    public static func isFullscreen(window: CGRect, screen: CGRect, safeTop: CGFloat = 0) -> Bool {
        guard window.width.isFinite, window.height.isFinite, screen.width > 0, screen.height > 0 else { return false }
        let tolerance: CGFloat = 2
        return abs(window.minX - screen.minX) <= tolerance && abs(window.maxX - screen.maxX) <= tolerance &&
            abs(window.minY - screen.minY) <= tolerance &&
            (abs(window.maxY - screen.maxY) <= tolerance ||
                (safeTop > 0 && abs(window.maxY - (screen.maxY - safeTop)) <= tolerance))
    }
}

/// Presentation state never owns or writes the saved resting frame.
public struct DesktopAutoHideState: Sendable {
    public enum Presentation: Equatable, Sendable { case cube, edge, hidden }
    public private(set) var userVisible = true
    private var collapsed = false
    private var outsideSince: TimeInterval?
    private var wasFullscreen = false
    private var fullscreenOverride = false

    public init() {}

    public mutating func setUserVisible(_ value: Bool) {
        userVisible = value
        collapsed = false; outsideSince = nil
        if !value { fullscreenOverride = false }
    }

    public mutating func reveal() {
        userVisible = true; collapsed = false; outsideSince = nil
        fullscreenOverride = true
    }

    public mutating func update(edgeEnabled: Bool, edgeAvailable: Bool, fullscreen: Bool,
                                pointerInside: Bool, busy: Bool, now: TimeInterval) -> Presentation {
        if !fullscreen { fullscreenOverride = false }
        wasFullscreen = fullscreen
        guard userVisible, !fullscreen || fullscreenOverride else { outsideSince = nil; return .hidden }
        guard edgeEnabled, edgeAvailable, !pointerInside, !busy else {
            collapsed = false; outsideSince = nil; return .cube
        }
        if collapsed { return .edge }
        if let outsideSince, now >= outsideSince, now - outsideSince >= 0.8 { collapsed = true; return .edge }
        if outsideSince == nil || now < outsideSince! { outsideSince = now }
        return .cube
    }
}
