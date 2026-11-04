import AppKit
import Testing
import CubeCore
@testable import TCube

private func restoreBrightness(_ original: DisplayBrightnessSample, target: DisplayBrightnessTarget,
                               hardware: any DisplayBrightnessHardware) async throws -> DisplayBrightnessSample {
    // The temporary-write task may be cancelled. Cleanup must still reach hardware.
    try await Task.detached {
        _ = try await hardware.write(original.fraction, to: target, using: original.backend)
        try await Task.sleep(for: .milliseconds(150))
        return try await hardware.read(target)
    }.value
}

private actor BrightnessRestoreFixture: DisplayBrightnessHardware {
    private var value = 0.38
    func read(_ target: DisplayBrightnessTarget) async throws -> DisplayBrightnessSample { .init(fraction: value, backend: .ddc) }
    func write(_ fraction: Double, to target: DisplayBrightnessTarget, using backend: DisplayBrightnessBackend) async throws -> DisplayBrightnessSample {
        try Task.checkCancellation()
        value = fraction
        return .init(fraction: fraction, backend: backend)
    }
}

@MainActor
@Suite(.serialized)
struct DisplayBrightnessHardwareTests {
    @Test func restorationCompletesEvenWhenTheCallerIsAlreadyCancelled() async throws {
        let hardware = BrightnessRestoreFixture()
        let target = DisplayBrightnessTarget(id: 2, uuid: "fixture", name: "Fixture", isBuiltIn: false)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await restoreBrightness(.init(fraction: 0.37, backend: .ddc), target: target, hardware: hardware)
        }
        let restored = try await operation.value
        #expect(restored.fraction == 0.37)
        #expect(try await hardware.read(target).fraction == 0.37)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_READ_BRIGHTNESS"] == "1"))
    func readsRealConnectedDisplaysThroughTheProductionAdapter() async throws {
        _ = NSApplication.shared
        let targets = DisplayBrightnessMenu.connectedDisplays()
        #expect(!targets.isEmpty)
        let hardware = NativeDisplayBrightnessHardware()
        for target in targets {
            let value = try await hardware.read(target)
            #expect(value.fraction.isFinite && (0...1).contains(value.fraction))
            print("Live brightness read: \(target.name), \(value.backend.rawValue), \(value.fraction)")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_WRITE_BRIGHTNESS"] == "1"))
    func smallPhysicalAdjustmentsAreReadBackAndOriginalBrightnessIsRestored() async throws {
        _ = NSApplication.shared
        let targets = DisplayBrightnessMenu.connectedDisplays()
        #expect(!targets.isEmpty)
        let hardware = NativeDisplayBrightnessHardware()
        for target in targets {
            let original = try await hardware.read(target)
            let temporary = original.fraction > 0.98 ? original.fraction - 0.01 : original.fraction + 0.01
            var operationError: Error?
            do {
                _ = try await hardware.write(temporary, to: target, using: original.backend)
                try await Task.sleep(for: .milliseconds(150))
                let changed = try await hardware.read(target)
                #expect(abs(changed.fraction - temporary) < 0.011)
                #expect(abs(changed.fraction - original.fraction) > 0.004,
                    "The physical value must actually change, not only the slider")
                print("Live brightness changed: \(target.name), \(original.fraction) → \(changed.fraction)")
            } catch { operationError = error }
            // Always restore after any attempted write, including failed verification.
            let restored = try await restoreBrightness(original, target: target, hardware: hardware)
            #expect(abs(restored.fraction - original.fraction) < 0.001,
                "Live test must restore the captured original brightness")
            print("Live brightness restored: \(target.name), \(restored.fraction)")
            if let operationError { throw operationError }
        }
    }
}
