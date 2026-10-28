import Foundation
import Testing
@testable import CubeCore

struct DesktopPlacementTests {
    private let primary = DesktopDisplay(id: "primary", visibleFrame: CGRect(x: 0, y: 40, width: 1000, height: 800))
    private let external = DesktopDisplay(id: "external", visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 900))

    @Test func oldHoverSettingsDecodeWithShortEntryDelay() throws {
        let settings = try JSONDecoder().decode(CubeHoverSettings.self, from: Data(#"{"isEnabled":true,"multiplier":2}"#.utf8))
        #expect(settings.delaySeconds == 0.18)
        for delay in [-1.0, 1.6, .infinity, .nan] {
            #expect(throws: ConfigurationError.self) { try CubeHoverSettings(delaySeconds: delay).validate() }
        }
        try CubeHoverSettings(delaySeconds: 0).validate()
        try CubeHoverSettings(delaySeconds: 1.5).validate()
    }

    @Test func placementTracksDisplayIdentityAcrossRearrangementAndResolutionChange() throws {
        var state = DesktopPlacementState()
        try state.record(frame: CGRect(x: -650, y: 400, width: 100, height: 100), displays: [primary, external])
        let resized = DesktopDisplay(id: "external", visibleFrame: CGRect(x: 1000, y: 40, width: 2300, height: 1700))
        let restored = try #require(state.restoredFrame(size: CGSize(width: 100, height: 100), displays: [primary, resized]))
        #expect(restored == CGRect(x: 2100, y: 840, width: 100, height: 100))
    }

    @Test func disconnectedDisplayFallsBackWithoutLosingItsRememberedPosition() throws {
        var state = DesktopPlacementState()
        try state.record(frame: CGRect(x: -650, y: 400, width: 100, height: 100), displays: [primary, external])
        let fallback = try #require(state.restoredFrame(size: CGSize(width: 100, height: 100), displays: [primary]))
        #expect(fallback == CGRect(x: 450, y: 390, width: 100, height: 100))
        #expect(state.preferredDisplayID == "external")
        #expect(state.restoredFrame(size: CGSize(width: 100, height: 100), displays: [primary, external]) == CGRect(x: -650, y: 400, width: 100, height: 100))
        #expect(state.restoredFrame(size: CGSize(width: 100, height: 100), displays: []) == nil)
    }

    @Test func eachDisplayRetainsItsPositionAndStoreRoundTripsIndependently() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DesktopPositionStore(url: directory.appendingPathComponent("desktop-positions.json"))
        var state = try store.load()
        try state.record(frame: CGRect(x: -650, y: 400, width: 100, height: 100), displays: [primary, external])
        try state.record(frame: CGRect(x: 90, y: 180, width: 100, height: 100), displays: [primary, external])
        try store.save(state)
        let reloaded = try store.load()
        #expect(reloaded.positions.count == 2)
        #expect(reloaded.restoredFrame(size: CGSize(width: 100, height: 100), displays: [primary, external]) == CGRect(x: 90, y: 180, width: 100, height: 100))
        try Data("invalid".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "invalid")
    }

    @Test func oversizedWindowIsClampedAndMalformedStateRejected() throws {
        var state = DesktopPlacementState()
        try state.record(frame: CGRect(x: 900, y: 700, width: 100, height: 100), displays: [primary])
        #expect(state.restoredFrame(size: CGSize(width: 1400, height: 900), displays: [primary]) == CGRect(x: 0, y: 40, width: 1400, height: 900))
        #expect(throws: (any Error).self) { try state.record(frame: CGRect(x: Double.nan, y: 0, width: 100, height: 100), displays: [primary]) }
    }
}
