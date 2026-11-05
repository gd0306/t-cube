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
@MainActor @Suite(.serialized) struct DisplayInputControllerTests {
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
        #expect(controller.rows.isEmpty)
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
