import AppKit
import CoreGraphics
import CubeCore

/// A topology fallback changes presentation, never the user's remembered display.
@MainActor
final class DesktopPlacementCoordinator {
    private let hoverController: CubeHoverController
    private weak var panel: NSWindow?
    private let store: DesktopPositionStore
    private let screens: @MainActor () -> [DesktopDisplay]
    private var state: DesktopPlacementState

    init(hoverController: CubeHoverController, panel: NSWindow,
         store: DesktopPositionStore = DesktopPositionStore(),
         screens: @escaping @MainActor () -> [DesktopDisplay] = DesktopPlacementCoordinator.currentDisplays) throws {
        self.hoverController = hoverController
        self.panel = panel
        self.store = store
        self.screens = screens
        state = try store.load()
        if state.preferredDisplayID == nil, !screens().isEmpty {
            try recordRestingPosition()
        }
        screenTopologyChanged()
    }

    /// Call only for deliberate drag commits and quick-placement commands.
    func recordRestingPosition() throws {
        let displays = screens()
        guard !displays.isEmpty else { return }
        var updated = state
        try updated.record(frame: hoverController.restingFrame, displays: displays)
        try store.save(updated)
        state = updated
    }

    func screenTopologyChanged() {
        guard panel != nil else { return }
        let displays = screens()
        if let frame = state.restoredFrame(size: hoverController.restingFrame.size, displays: displays) {
            hoverController.restoreRestingFrame(at: frame.origin)
        } else {
            let current = hoverController.restingFrame
            let origin = WindowPlacement.clamp(current.origin, size: current.size, screens: displays.map(\.visibleFrame))
            hoverController.restoreRestingFrame(at: origin)
        }
    }

    static func currentDisplays() -> [DesktopDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let identity: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                identity = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
            } else {
                identity = "display-\(displayID)"
            }
            return DesktopDisplay(id: identity, visibleFrame: screen.visibleFrame)
        }
    }
}
