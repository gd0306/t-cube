import Foundation
import Testing
import CubeCore
@testable import TCube

private actor BrightnessFixture: DisplayBrightnessHardware {
    var fraction = 0.37
    var reads = 0
    var writes: [(String, Double)] = []
    var activeWrites = 0
    var maximumActiveWrites = 0
    var failWrites = false
    var unsupported = false
    var holdReads = false
    var holdWrites = false
    var readWaiter: CheckedContinuation<Void, Never>?
    var writeWaiter: CheckedContinuation<Void, Never>?
    func configure(reads: Bool = false, writes: Bool = false, failure: Bool = false, unsupported: Bool = false) {
        holdReads = reads; holdWrites = writes; failWrites = failure; self.unsupported = unsupported
    }
    func resumeRead() { holdReads = false; readWaiter?.resume(); readWaiter = nil }
    func resumeWrite() { holdWrites = false; writeWaiter?.resume(); writeWaiter = nil }
    func read(_ target: DisplayBrightnessTarget) async throws -> DisplayBrightnessSample {
        reads += 1
        if unsupported { throw DisplayBrightnessFailure.unsupported }
        let captured = fraction
        if holdReads { await withCheckedContinuation { readWaiter = $0 } }
        return .init(fraction: captured, backend: .ddc)
    }
    func write(_ fraction: Double, to target: DisplayBrightnessTarget, using backend: DisplayBrightnessBackend) async throws -> DisplayBrightnessSample {
        activeWrites += 1; maximumActiveWrites = max(maximumActiveWrites, activeWrites)
        writes.append((target.uuid, fraction))
        defer { activeWrites -= 1 }
        if holdWrites { await withCheckedContinuation { writeWaiter = $0 } }
        if failWrites { throw DisplayBrightnessFailure.writeFailed }
        self.fraction = fraction
        return .init(fraction: fraction, backend: backend)
    }
}
private actor BrightnessGate {
    var waiter: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { waiter = $0 } }
    func release() { waiter?.resume(); waiter = nil }
    var isWaiting: Bool { waiter != nil }
}
@MainActor private final class BrightnessTargets {
    var values: [DisplayBrightnessTarget] = [.init(id: 2, uuid: "screen-A", name: "External", isBuiltIn: false)]
}

@MainActor
@Suite(.serialized)
struct DisplayBrightnessControllerTests {
    private func until(_ check: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !(await check()), Date() < deadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await check(), "Brightness operation did not settle")
    }
    private func open(_ controller: DisplayBrightnessController) async throws {
        controller.beginTracking()
        try await until { controller.rows.first?.isLoading == false }
    }

    @Test func openingReadsHardwareAndClosingDoesNotPollOrWrite() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: {})
        #expect(await hardware.reads == 0)
        try await open(controller)
        #expect(controller.rows.first?.fraction == 0.37)
        controller.endTracking()
        #expect(await hardware.reads == 1)
        #expect(await hardware.writes.isEmpty)
        controller.stop()
    }

    @Test func draggingRetainsOnlyOneInFlightWriteAndTheLatestPendingValue() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets(), gate = BrightnessGate()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: { await gate.wait() })
        try await open(controller)
        controller.setFraction(0.1, for: "screen-A"); controller.setFraction(0.2, for: "screen-A"); controller.setFraction(0.3, for: "screen-A")
        try await until { await gate.isWaiting }
        await hardware.configure(writes: true); await gate.release()
        try await until { await hardware.writes.count == 1 }
        controller.setFraction(0.4, for: "screen-A"); controller.setFraction(0.5, for: "screen-A")
        #expect(controller.rows.first?.fraction == 0.5)
        await hardware.resumeWrite()
        try await until { await gate.isWaiting }; await gate.release()
        try await until { controller.rows.first?.isWriting == false }
        #expect(await hardware.writes.map(\.1) == [0.3, 0.5])
        #expect(await hardware.maximumActiveWrites == 1)
        #expect(controller.rows.first?.fraction == 0.5)
        controller.stop()
    }

    @Test func closingMenuStillAppliesTheFinalUserValue() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets(), gate = BrightnessGate()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: { await gate.wait() })
        try await open(controller)
        controller.setFraction(0.6, for: "screen-A"); controller.endTracking()
        try await until { await gate.isWaiting }; await gate.release()
        try await until { await hardware.writes.count == 1 }
        #expect(await hardware.writes.first?.1 == 0.6)
        #expect(controller.isMenuOpen == false)
        controller.stop()
    }

    @Test func delayedRefreshCannotOverwriteANewerUserWrite() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: {})
        try await open(controller)
        await hardware.configure(reads: true); controller.refresh()
        try await until { await hardware.readWaiter != nil }
        controller.setFraction(0.8, for: "screen-A")
        try await until { await hardware.writes.count == 1 }
        await hardware.resumeRead()
        try await until { controller.rows.first?.isLoading == false && controller.rows.first?.isWriting == false }
        #expect(controller.rows.first?.fraction == 0.8)
        controller.stop()
    }

    @Test func failedWriteShowsAnErrorAndRestoresActualHardwareValue() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: {})
        try await open(controller); await hardware.configure(failure: true)
        controller.setFraction(0.8, for: "screen-A")
        try await until { controller.rows.first?.message != nil }
        #expect(controller.rows.first?.fraction == 0.37)
        #expect(controller.rows.first?.isEnabled == true)
        #expect(controller.rows.first?.isWriting == false)
        controller.stop()
    }

    @Test func unsupportedScreensAndInvalidValuesNeverTriggerPhysicalWrites() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets()
        await hardware.configure(unsupported: true)
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: {})
        try await open(controller)
        controller.setFraction(0.8, for: "screen-A")
        #expect(controller.rows.first?.isEnabled == false && controller.rows.first?.message != nil)
        #expect(await hardware.writes.isEmpty)
        controller.stop()
    }

    @Test func anOldActiveWriteCannotOverwriteTheReplacementScreen() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: {})
        try await open(controller); await hardware.configure(writes: true)
        controller.setFraction(0.8, for: "screen-A")
        try await until { await hardware.writeWaiter != nil }
        targets.values = [.init(id: 2, uuid: "screen-B", name: "Replacement", isBuiltIn: false)]
        controller.screenParametersChanged()
        try await until { controller.rows.first?.target.uuid == "screen-B" && controller.rows.first?.isLoading == false }
        await hardware.resumeWrite()
        try await until { await hardware.activeWrites == 0 }
        #expect(controller.rows.first?.target.uuid == "screen-B" && controller.rows.first?.fraction == 0.37)
        #expect(controller.rows.first?.isWriting == false)
        controller.stop()
    }

    @Test func failedOldWriteReadbackDoesNotReplaceANewerPendingEdit() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: {})
        try await open(controller); await hardware.configure(reads: true, failure: true)
        controller.setFraction(0.6, for: "screen-A")
        try await until { await hardware.readWaiter != nil }
        await hardware.configure(); controller.setFraction(0.8, for: "screen-A")
        await hardware.resumeRead()
        try await until { await hardware.writes.count == 2 && controller.rows.first?.isWriting == false }
        #expect(await hardware.writes.map(\.1) == [0.6, 0.8])
        #expect(controller.rows.first?.fraction == 0.8 && controller.rows.first?.message == nil)
        controller.stop()
    }

    @Test func reconnectingAReusedDisplayIDCannotApplyAnOldPendingWrite() async throws {
        let hardware = BrightnessFixture(), targets = BrightnessTargets(), gate = BrightnessGate()
        let controller = DisplayBrightnessController(hardware: hardware, targets: { targets.values }, debounce: { await gate.wait() })
        try await open(controller); controller.setFraction(0.8, for: "screen-A")
        try await until { await gate.isWaiting }
        targets.values = [.init(id: 2, uuid: "screen-B", name: "Replacement", isBuiltIn: false)]
        controller.screenParametersChanged(); await gate.release()
        try await until { controller.rows.first?.target.uuid == "screen-B" && controller.rows.first?.isLoading == false }
        #expect(await hardware.writes.isEmpty)
        controller.setFraction(.nan, for: "screen-B"); controller.setFraction(1.1, for: "screen-B")
        #expect(await hardware.writes.isEmpty)
        controller.stop()
    }
}
