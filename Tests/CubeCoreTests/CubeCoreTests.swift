import Foundation
import Testing
import simd
@testable import CubeCore

private func item(_ name: String, kind: LauncherItem.Kind = .application) -> LauncherItem {
    LauncherItem(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, kind: kind)
}

@Test func fullGroupRefusesFifthItemWithoutMutation() throws {
    var config = CubeConfiguration()
    for name in ["A", "B", "C", "D"] { try config.add(item(name), to: .front) }
    let before = config
    #expect(throws: ConfigurationError.groupFull) { try config.add(item("E"), to: .front) }
    #expect(config == before)
}

@Test func duplicatesAreRejectedOnlyWithinTheSameGroup() throws {
    var config = CubeConfiguration()
    try config.add(item("A"), to: .front)
    let before = config
    #expect(throws: ConfigurationError.duplicateItem) { try config.add(item("A"), to: .front) }
    #expect(config == before)
    try config.add(item("A"), to: .back)
    #expect(config.group(for: .back).slots[0]?.name == "A")
}

@Test func reorderingAndRemovalPreserveFixedSlots() throws {
    var config = CubeConfiguration()
    for name in ["A", "B", "C"] { try config.add(item(name), to: .front) }
    try config.move(in: .front, from: 0, to: 2)
    #expect(config.group(for: .front).slots.map { $0?.name } == ["B", "C", "A", nil])
    try config.remove(from: .front, slot: 1)
    #expect(config.group(for: .front).slots.map { $0?.name } == ["B", nil, "A", nil])
    try config.add(item("D"), to: .front)
    #expect(config.group(for: .front).slots.map { $0?.name } == ["B", "D", "A", nil])
}

@Test func invalidEditsLeaveConfigurationUnchanged() throws {
    var config = CubeConfiguration()
    let before = config
    #expect(throws: ConfigurationError.invalidSlot) { try config.remove(from: .front, slot: 4) }
    #expect(throws: ConfigurationError.emptySlot) { try config.move(in: .front, from: 0, to: 1) }
    #expect(throws: ConfigurationError.invalidName) { try config.rename(.front, to: " \n") }
    #expect(config == before)
    try config.rename(.front, to: " 开发工具 ")
    #expect(config.group(for: .front).name == "开发工具")
}

@Test func applicationAndFolderRoundTripWithBookmark() throws {
    for kind in [LauncherItem.Kind.application, .folder] {
        let original = LauncherItem(url: URL(fileURLWithPath: "/tmp/example"), name: "示例", kind: kind, bookmark: Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(LauncherItem.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}

@Test func diskStoreRoundTripsPositionScaleAndEntries() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
    #expect(try store.load() == CubeConfiguration())
    var config = CubeConfiguration()
    config.windowPosition = WindowPosition(x: -320, y: 245)
    config.scale = 1.25
    try config.add(item("A"), to: .top)
    try store.save(config)
    #expect(try store.load() == config)
}

@Test func corruptConfigurationIsNeverReplacedBySave() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = Data("{broken JSON".utf8)
    try bytes.write(to: url)
    let store = ConfigurationStore(url: url)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(throws: (any Error).self) { try store.save(CubeConfiguration()) }
    #expect(try Data(contentsOf: url) == bytes)
}

@Test func malformedGroupsAndUnsupportedVersionsAreRejected() throws {
    #expect(throws: ConfigurationError.invalidSlotCount) { try FaceGroup(name: "Group", slots: [nil]) }
    let encoded = try JSONEncoder().encode(CubeConfiguration())
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json["version"] = 99
    #expect(throws: ConfigurationError.unsupportedVersion(99)) {
        try JSONDecoder().decode(CubeConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

@Test func sixCanonicalFacesHaveHandCheckedNormalsAndUprightAxes() {
    let fixtures: [(CubeFace, SIMD3<Float>, SIMD3<Float>)] = [
        (.front, [0, 0, 1], [0, 1, 0]), (.right, [1, 0, 0], [0, 1, 0]),
        (.back, [0, 0, -1], [0, 1, 0]), (.left, [-1, 0, 0], [0, 1, 0]),
        (.top, [0, 1, 0], [0, 0, -1]), (.bottom, [0, -1, 0], [0, 0, 1])
    ]
    for (face, normal, up) in fixtures {
        #expect(simd_distance(face.normal, normal) < 0.0001)
        #expect(simd_distance(face.orientation.act([0, 0, 1]), normal) < 0.0001)
        #expect(simd_distance(face.orientation.act([0, 1, 0]), up) < 0.0001)
        #expect(simd_distance(face.localUp, up) < 0.0001)
    }
}

@Test func snappingMakesEveryFaceUprightWithTheSameBalancedDisplayTilt() {
    for face in CubeFace.allCases {
        let snapped = CubeRotation.snapped(to: face)
        #expect(CubeRotation.nearestFace(to: snapped) == face)
        // Independently calculated yaw -0.66, pitch 0.52; all faces remain upright.
        #expect(simd_distance(snapped.act(face.normal), [-0.532075, -0.496880, 0.685570]) < 0.001)
        #expect(simd_distance(snapped.act(face.localUp), [-0.304646, 0.867819, 0.392531]) < 0.001)
    }
    #expect(CubeRotation.nearestFace(to: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])) == .left)
}

@Test func dragUsesInitialOrientationAndKeepsQuaternionNormalized() {
    let start = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
    let unchanged = CubeRotation.dragged(from: start, translation: .zero)
    #expect(abs(simd_dot(unchanged.vector, start.vector)) > 0.9999)
    let dragged = CubeRotation.dragged(from: simd_quatf(real: 1, imag: .zero), translation: [100, 0])
    #expect(abs(simd_length(dragged.vector) - 1) < 0.0001)
    #expect(dragged.act([0, 0, 1]).x > 0.5)
}

@Test func movingOutAndBackRemainsADrag() {
    var tracker = PointerDragTracker(threshold: 5)
    tracker.start(at: [10, 10])
    let belowThreshold = tracker.update(to: [12, 11])
    let crossedThreshold = tracker.update(to: [16, 10])
    let returnedToOrigin = tracker.end(at: [10, 10])
    #expect(!belowThreshold)
    #expect(crossedThreshold)
    #expect(returnedToOrigin == .drag)
    tracker.start(at: .zero)
    let click = tracker.end(at: [2, 2])
    #expect(click == .click)
    tracker.start(at: .zero)
    let atThreshold = tracker.end(at: [5, 0])
    #expect(atThreshold == .drag)
}
