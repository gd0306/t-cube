import Foundation
import Testing
import CubeCore
@testable import TCube

private actor InputFixture: DisplayInputHardware {
    var writes = 0
    var waiter: CheckedContinuation<Void, Never>?
    func read(_ target: DisplayBrightnessTarget) async throws -> UInt16 { 7 }
    func write(_ value: UInt16, target: DisplayBrightnessTarget, mapping: DisplayInputMapping) async throws -> DisplayInputOutcome {
        writes += 1
        await withCheckedContinuation { waiter = $0 }
        return .sentUnconfirmed
    }
    func release() { waiter?.resume(); waiter = nil }
}
private struct OtherInputFixture: DisplayInputHardware {
    func read(_ target: DisplayBrightnessTarget) async throws -> UInt16 { 7 }
    func write(_ value: UInt16, target: DisplayBrightnessTarget, mapping: DisplayInputMapping) async throws -> DisplayInputOutcome { .otherInput(16) }
}
private struct UnreadableInputFixture: DisplayInputHardware {
    func read(_ target: DisplayBrightnessTarget) async throws -> UInt16 { throw DisplayBrightnessFailure.readFailed }
    func write(_ value: UInt16, target: DisplayBrightnessTarget, mapping: DisplayInputMapping) async throws -> DisplayInputOutcome { throw DisplayBrightnessFailure.writeFailed }
}
private actor GenericInputFixture: DisplayInputHardware {
    var reads: [UInt32] = []
    var writes: [UInt32] = []
    func read(_ target: DisplayBrightnessTarget) async throws -> UInt16 {
        reads.append(target.id)
        if target.id == 4 { throw DisplayBrightnessFailure.unsupported }
        return target.id == 3 ? 17 : 15
    }
    func write(_ value: UInt16, target: DisplayBrightnessTarget, mapping: DisplayInputMapping) async throws -> DisplayInputOutcome {
        writes.append(target.id)
        return .confirmed(value)
    }
}
@MainActor @Suite(.serialized) struct DisplayInputControllerTests {
    @Test func everyConnectedExternalDisplayIsVisibleEvenWhenIdentityIsUnavailable() async throws {
        let fixture = GenericInputFixture(), clone = UUID().uuidString
        let displays = [DisplayBrightnessTarget(id: 1, uuid: UUID().uuidString, name: "Built in", isBuiltIn: true),
                        .init(id: 2, uuid: clone, name: "Same model A", isBuiltIn: false),
                        .init(id: 3, uuid: clone.lowercased(), name: "Same model B", isBuiltIn: false),
                        .init(id: 4, uuid: "unsupported:4", name: "No identity", isBuiltIn: false)]
        let controller = DisplayInputController(hardware: fixture, targets: { displays }, store: DisplayInputStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        controller.beginTracking()
        try await Task.sleep(for: .milliseconds(10))
        #expect(controller.rows.count == 3)
        #expect(Set(controller.rows.map(\.id)).count == 3)
        #expect(controller.rows.allSatisfy { !$0.enabled && !$0.busy && $0.message != nil })
        #expect(await fixture.reads.isEmpty)
        controller.stop()
    }
    @Test func genericMonitorsKeepIndependentMappingsAcrossReconnectAndUnsupportedDDC() async throws {
        let fixture = GenericInputFixture(), a = UUID().uuidString, b = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DisplayInputStore(url: dir.appendingPathComponent("display-inputs.json"))
        try store.save(DisplayInputMapping(typeC: 15, hdmi: 16)!, for: a)
        try store.save(DisplayInputMapping(typeC: 18, hdmi: 17)!, for: b)
        let before = try Data(contentsOf: store.url)
        let first = DisplayBrightnessTarget(id: 2, uuid: a, name: "Generic A", isBuiltIn: false)
        let second = DisplayBrightnessTarget(id: 3, uuid: b, name: "Generic B", isBuiltIn: false)
        var targets = [first, second, DisplayBrightnessTarget(id: 4, uuid: UUID().uuidString, name: "No DDC", isBuiltIn: false)]
        let controller = DisplayInputController(hardware: fixture, targets: { targets }, store: store)
        controller.beginTracking()
        for _ in 0..<100 where controller.rows.contains(where: \.busy) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(controller.rows.count == 3)
        #expect(controller.rows[0].enabled && controller.rows[1].enabled)
        #expect(!controller.rows[2].enabled && controller.rows[2].message != nil)
        controller.setSource(.typeC, for: b)
        for _ in 0..<100 where controller.rows[1].busy { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await fixture.writes == [3])
        targets = [second]; controller.screenParametersChanged()
        targets = [first, second]; controller.screenParametersChanged()
        for _ in 0..<100 where controller.rows.contains(where: \.busy) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(controller.rows.map(\.mapping) == [DisplayInputMapping(typeC: 15, hdmi: 16), DisplayInputMapping(typeC: 18, hdmi: 17)])
        #expect(try Data(contentsOf: store.url) == before)
        controller.stop()
    }
    @Test func staleActionsCannotWriteOrSaveAfterDisplayReplacement() async throws {
        let fixture = GenericInputFixture(), id = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DisplayInputStore(url: dir.appendingPathComponent("display-inputs.json"))
        try store.save(DisplayInputMapping(typeC: 15, hdmi: 16)!, for: id)
        let before = try Data(contentsOf: store.url)
        var targets = [DisplayBrightnessTarget(id: 2, uuid: id, name: "Generic", isBuiltIn: false)]
        let controller = DisplayInputController(hardware: fixture, targets: { targets }, store: store)
        controller.beginTracking()
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        targets = [.init(id: 2, uuid: UUID().uuidString, name: "Replacement", isBuiltIn: false)]
        controller.setSource(.hdmi, for: id)
        try await Task.sleep(for: .milliseconds(10))
        #expect(await fixture.writes.isEmpty)
        #expect(throws: (any Error).self) { try controller.save(DisplayInputMapping(typeC: 1, hdmi: 2)!, for: id) }
        #expect(try Data(contentsOf: store.url) == before)
        controller.stop()
    }
    @Test func unexpectedInputShowsItsCodeAndDisablesSwitching() async throws {
        let id = UUID().uuidString, dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DisplayInputStore(url: dir.appendingPathComponent("display-inputs.json"))
        try store.save(DisplayInputMapping(typeC: 7, hdmi: 5)!, for: id)
        let target = DisplayBrightnessTarget(id: 2, uuid: id, name: "Test", isBuiltIn: false)
        let controller = DisplayInputController(hardware: OtherInputFixture(), targets: { [target] }, store: store)
        controller.beginTracking()
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        controller.setSource(.hdmi, for: id)
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        #expect(controller.rows.first?.current == 16)
        #expect(controller.rows.first?.enabled == false)
        #expect(controller.rows.first?.message?.contains("16") == true)
        #expect(controller.rows.first?.message?.contains("未切换") == false)
        controller.stop()
    }
    @Test func corruptStoreGuidanceSurvivesReadFailure() async throws {
        let id = UUID().uuidString, dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("display-inputs.json")
        try Data("{bad".utf8).write(to: url)
        let target = DisplayBrightnessTarget(id: 2, uuid: id, name: "Test", isBuiltIn: false)
        let controller = DisplayInputController(hardware: UnreadableInputFixture(), targets: { [target] }, store: DisplayInputStore(url: url))
        controller.beginTracking()
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        #expect(controller.rows.first?.message?.contains("display-inputs.json") == true)
        #expect(controller.rows.first?.enabled == false)
        controller.stop()
    }
    @Test func closingIgnoresACompletedWrite() async throws {
        let fixture = InputFixture(), id = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DisplayInputStore(url: dir.appendingPathComponent("display-inputs.json"))
        try store.save(DisplayInputMapping(typeC: 7, hdmi: 5)!, for: id)
        let target = DisplayBrightnessTarget(id: 2, uuid: id, name: "Test", isBuiltIn: false)
        let controller = DisplayInputController(hardware: fixture, targets: { [target] }, store: store)
        controller.beginTracking()
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        controller.setSource(.hdmi, for: id)
        for _ in 0..<100 where await fixture.writes == 0 { try await Task.sleep(for: .milliseconds(2)) }
        controller.endTracking(); await fixture.release()
        try await Task.sleep(for: .milliseconds(10))
        #expect(controller.rows.first?.current == 7)
        #expect(controller.rows.first?.message != "命令已发送，无法确认；请在当前显示画面的主机或显示器实体菜单中切回")
        controller.stop()
    }
    @Test func topologyChangeIgnoresOldWriteAndClonedIdentity() async throws {
        let fixture = InputFixture(), id = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DisplayInputStore(url: dir.appendingPathComponent("display-inputs.json"))
        try store.save(DisplayInputMapping(typeC: 7, hdmi: 5)!, for: id)
        let target = DisplayBrightnessTarget(id: 2, uuid: id, name: "Test", isBuiltIn: false)
        var displays = [target]
        let controller = DisplayInputController(hardware: fixture, targets: { displays }, store: store)
        controller.beginTracking()
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        controller.setSource(.hdmi, for: id)
        for _ in 0..<100 where await fixture.writes == 0 { try await Task.sleep(for: .milliseconds(2)) }
        displays.append(DisplayBrightnessTarget(id: 3, uuid: id, name: "Clone", isBuiltIn: false))
        controller.screenParametersChanged(); await fixture.release()
        try await Task.sleep(for: .milliseconds(10))
        #expect(controller.rows.count == 2)
        #expect(controller.rows.allSatisfy { !$0.enabled })
        #expect(await fixture.writes == 1)
        controller.stop()
    }
    @Test func duplicateWritesAndUnconfirmedResults() async throws {
        let fixture = InputFixture(), id = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DisplayInputStore(url: dir.appendingPathComponent("display-inputs.json"))
        try store.save(DisplayInputMapping(typeC: 7, hdmi: 5)!, for: id)
        let target = DisplayBrightnessTarget(id: 2, uuid: id, name: "Test", isBuiltIn: false)
        let controller = DisplayInputController(hardware: fixture, targets: { [target] }, store: store)
        controller.beginTracking()
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        controller.setSource(.typeC, for: id)
        controller.setSource(.hdmi, for: id); controller.setSource(.hdmi, for: id)
        for _ in 0..<100 where await fixture.writes == 0 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await fixture.writes == 1)
        await fixture.release()
        for _ in 0..<100 where controller.rows.first?.busy != false { try await Task.sleep(for: .milliseconds(2)) }
        #expect(controller.rows.first?.current == nil)
        #expect(controller.rows.first?.enabled == false)
        #expect(controller.rows.first?.message?.contains("无法确认") == true)
        controller.stop()
    }
}

import DisplayBrightnessBridge
@Test func inputBridgeRejectsOtherFeatures() {
    let input = DDCInputCodec.writeRequest(value: 5)
    let brightness = DDCBrightnessCodec.writeRequest(value: 5)
    let uuid = UUID().uuidString
    let rejectedByBrightness = uuid.withCString { u in input.withUnsafeBufferPointer { TCBrightnessDDCExchange(0, u, $0.baseAddress, UInt32($0.count), nil, 0) } }
    let rejectedByInput = uuid.withCString { u in brightness.withUnsafeBufferPointer { TCInputDDCExchange(0, u, $0.baseAddress, UInt32($0.count), nil, 0) } }
    #expect(rejectedByBrightness == TCBrightnessInvalidArgument)
    #expect(rejectedByInput == TCBrightnessInvalidArgument)
}
