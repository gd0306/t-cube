import AppKit
import CubeCore
import Darwin
import Testing
@testable import TCube

/// Opt-in diagnostic. Uses temporary configuration, never the installed app's data.
@MainActor
struct BackgroundThemeMemoryProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_BACKGROUND_MEMORY_PROBE"] == "1"))
    func hiddenThemeChanges() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        var config = CubeConfiguration()
        config.autoRotatesWhenIdle = false
        config.themeCycle = CubeThemeCycle(isEnabled: true, themes: [.prism, .moonstone, .auroraFlow])
        try store.save(config)
        let model = AppModel(store: store)
        model.stopThemeCycle()
        let view = CubeView(model: model)
        view.idlePowerSavingEnabled = true
        let surface = CubeSurfaceView(cubeView: view)
        let window = NSPanel(contentRect: NSRect(x: 50, y: 50, width: 164, height: 164),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        model.onAppearanceChange = { [weak view] in view?.refreshAppearance() }
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        window.orderFrontRegardless()
        _ = surface.resumeRendering(forInput: true)
        try await Task.sleep(for: .seconds(2))
        window.orderOut(nil)
        surface.synchronizeRenderingVisibility()
        var measurements: [[String: Any]] = []
        func record(_ stage: String) {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS {
                measurements.append(["stage": stage, "footprintBytes": info.phys_footprint,
                    "peakBytes": info.ledger_phys_footprint_peak])
            }
        }
        record("hiddenStart")
        for index in 1...180 {
            autoreleasepool { model.advanceTheme() }
            try await Task.sleep(for: .milliseconds(50))
            if index % 30 == 0 { record("hiddenThemes\(index)") }
        }
        try await Task.sleep(for: .seconds(2))
        record("hiddenSettled")
        let startBytes = try #require(measurements.first?["footprintBytes"] as? UInt64)
        let endBytes = try #require(measurements.last?["footprintBytes"] as? UInt64)
        #expect(endBytes < startBytes + 32 * 1024 * 1024,
            "Hidden theme cycling must not accumulate graphics allocations")
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        if let output = ProcessInfo.processInfo.environment["TCUBE_MEMORY_PROFILE_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: output))
        }
        print("BACKGROUND_MEMORY_PROFILE \(String(decoding: data, as: UTF8.self))")
    }
}
