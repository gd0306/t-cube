import Foundation
import CoreGraphics
import Testing
@testable import CubeCore

struct AppBoundaryTests {
    private func item(_ name: String) -> LauncherItem {
        LauncherItem(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, kind: .application)
    }

    private func sparseConfiguration() throws -> CubeConfiguration {
        var configuration = CubeConfiguration()
        for name in ["A", "B", "C"] { try configuration.add(item(name), to: .front) }
        try configuration.remove(from: .front, slot: 0)
        return configuration
    }

    @Test func explicitEmptySlotInsertionPreservesUnrelatedSparseSlots() throws {
        var configuration = try sparseConfiguration()
        let before = configuration.group(for: .front).slots
        let added = item("D")
        try configuration.place(added, to: .front, slot: 3)
        #expect(configuration.group(for: .front).slots == [nil, before[1], before[2], added])
    }

    @Test func explicitReplacementPreservesUnrelatedSparseSlots() throws {
        var configuration = try sparseConfiguration()
        let before = configuration.group(for: .front).slots
        let replacement = item("D")
        try configuration.place(replacement, to: .front, slot: 2, replacing: true)
        #expect(configuration.group(for: .front).slots == [nil, before[1], replacement, nil])
    }

    @Test func duplicateReplacementPreservesOriginalConfiguration() throws {
        var configuration = try sparseConfiguration()
        let before = configuration
        #expect(throws: ConfigurationError.duplicateItem) {
            try configuration.place(item("B"), to: .front, slot: 2, replacing: true)
        }
        #expect(configuration == before)
    }

    @Test func occupiedPlacementRequiresExplicitReplacement() throws {
        var configuration = try sparseConfiguration()
        let before = configuration
        #expect(throws: ConfigurationError.occupiedSlot) {
            try configuration.place(item("D"), to: .front, slot: 2)
        }
        #expect(configuration == before)
    }

    @Test func invalidExplicitPlacementPreservesOriginalConfiguration() throws {
        var configuration = try sparseConfiguration()
        let before = configuration
        for slot in [-1, 4] {
            #expect(throws: ConfigurationError.invalidSlot) {
                try configuration.place(item("D"), to: .front, slot: slot, replacing: true)
            }
            #expect(configuration == before)
        }
        let unsupported = LauncherItem(url: URL(string: "https://example.com")!, name: "Remote", kind: .folder)
        #expect(throws: ConfigurationError.invalidItem) {
            try configuration.place(unsupported, to: .front, slot: 2, replacing: true)
        }
        #expect(configuration == before)
    }

    @Test func faceSlotsAreRowMajorAndExcludeTitleAndGaps() {
        #expect(FaceLayout.slot(at: SIMD2<Float>(-0.25, 0.12)) == 0)
        #expect(FaceLayout.slot(at: SIMD2<Float>(0.25, 0.12)) == 1)
        #expect(FaceLayout.slot(at: SIMD2<Float>(-0.25, -0.28)) == 2)
        #expect(FaceLayout.slot(at: SIMD2<Float>(0.25, -0.28)) == 3)
        #expect(FaceLayout.slot(at: SIMD2<Float>(0, 0.4)) == nil)
        #expect(FaceLayout.slot(at: SIMD2<Float>(0, 0)) == nil)
        #expect(FaceLayout.slot(at: SIMD2<Float>(0.6, 0)) == nil)
        #expect(FaceLayout.slot(at: SIMD2<Float>(.nan, 0)) == nil)
    }

    @Test func restoredPanelFitsNearestAttachedScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1200, y: 100, width: 1200, height: 800)]
        #expect(WindowPlacement.clamp(CGPoint(x: -900, y: 300), size: CGSize(width: 350, height: 350), screens: screens) == CGPoint(x: -900, y: 300))
        #expect(WindowPlacement.clamp(CGPoint(x: 2000, y: -200), size: CGSize(width: 350, height: 350), screens: screens) == CGPoint(x: 1090, y: 0))
        #expect(WindowPlacement.clamp(CGPoint(x: -1900, y: 1100), size: CGSize(width: 350, height: 350), screens: screens) == CGPoint(x: -1200, y: 550))
        #expect(WindowPlacement.clamp(.zero, size: CGSize(width: 500, height: 500), screens: [CGRect(x: 20, y: 30, width: 300, height: 200)]) == CGPoint(x: 20, y: 30))
    }

    @Test func targetValidationAcceptsFoldersAndAppsButRejectsFilesAndMissingTargets() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let app = temporary.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let file = temporary.appendingPathComponent("note.txt")
        try Data("Hello".utf8).write(to: file)
        #expect(try LocalTarget.kind(at: temporary) == .folder)
        #expect(try LocalTarget.kind(at: app) == .application)
        #expect(throws: LocalTargetError.self) { try LocalTarget.kind(at: file) }
        #expect(throws: LocalTargetError.self) { try LocalTarget.kind(at: temporary.appendingPathComponent("missing")) }
        #expect(throws: LocalTargetError.self) { try LocalTarget.kind(at: URL(string: "https://example.com")!) }
    }
}
