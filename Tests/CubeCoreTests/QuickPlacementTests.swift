import CoreGraphics
import Testing
@testable import CubeCore

struct QuickPlacementTests {
    @Test func fivePositionsUseVisibleScreenBoundsWithAnInset() {
        // AppKit's origin is at the bottom left. This frame excludes menu/Dock.
        let screen = CGRect(x: 100, y: 60, width: 1200, height: 800)
        let cases: [(CubePlacement, CGPoint)] = [
            (.topLeft, CGPoint(x: 124, y: 736)),
            (.topRight, CGPoint(x: 1116, y: 736)),
            (.bottomLeft, CGPoint(x: 124, y: 84)),
            (.bottomRight, CGPoint(x: 1116, y: 84)),
            (.center, CGPoint(x: 620, y: 410))
        ]
        for (position, expected) in cases {
            #expect(WindowPlacement.origin(for: position, size: CGSize(width: 160, height: 100), in: screen) == expected)
        }
    }

    @Test func placementUsesTheCubesScreenIncludingNegativeCoordinates() {
        let screens = [CGRect(x: 0, y: 40, width: 1440, height: 820), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        let selected = WindowPlacement.visibleScreen(for: CGRect(x: -1600, y: 500, width: 164, height: 164), screens: screens)
        #expect(selected == screens[1])
        #expect(WindowPlacement.visibleScreen(for: CGRect(x: 4000, y: 900, width: 164, height: 164), screens: screens) == screens[0])
        #expect(WindowPlacement.visibleScreen(for: .zero, screens: []) == nil)
        #expect(WindowPlacement.origin(for: .topLeft, size: CGSize(width: 164, height: 164), in: screens[1]) == CGPoint(x: -1896, y: 892))
    }

    @Test func smallScreensReduceTheInsetAndOversizedCubesKeepAnAccessibleOrigin() {
        let screen = CGRect(x: -400, y: 30, width: 180, height: 180)
        for position in CubePlacement.allCases {
            #expect(WindowPlacement.origin(for: position, size: CGSize(width: 164, height: 164), in: screen) == CGPoint(x: -392, y: 38))
            #expect(WindowPlacement.origin(for: position, size: CGSize(width: 200, height: 200), in: screen) == screen.origin)
        }
    }
}
