import AppKit
import CubeCore
import Darwin
import Testing
@testable import TCube

@MainActor
struct MemoryResourceBenchmarkTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_MEMORY_PROFILE"] == "1"))
    func isolatedResourceWorkload() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        configuration.autoRotatesWhenIdle = false
        let apps = ["/System/Applications/Calculator.app", "/System/Applications/Notes.app", "/System/Applications/Preview.app", "/System/Library/CoreServices/Finder.app"]
        for face in CubeFace.allCases {
            for path in apps { try configuration.add(LauncherItem(url: URL(fileURLWithPath: path), name: URL(fileURLWithPath: path).lastPathComponent, kind: .application), to: face) }
        }
        try store.save(configuration)
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        view.idlePowerSavingEnabled = true
        let surface = CubeSurfaceView(cubeView: view)
        let window = NSPanel(contentRect: NSRect(x: 50, y: 50, width: 164, height: 164), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        window.orderFrontRegardless()
        _ = surface.resumeRendering(forInput: true)
        try await Task.sleep(for: .seconds(2))
        var measurements: [[String: Any]] = []
        func record(_ stage: String) {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            if status == KERN_SUCCESS { measurements.append(["stage": stage, "footprintBytes": info.phys_footprint, "peakBytes": info.ledger_phys_footprint_peak]) }
        }
        record("warm")
        for _ in 0..<12 {
            autoreleasepool { view.refreshTextures() }
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .seconds(1))
        record("unchangedRefresh12")
        for _ in 0..<6 {
            model.change { try $0.move(in: .front, from: 0, to: 1) }
            autoreleasepool { view.refreshTextures() }
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .seconds(1))
        record("singleFaceEdits6")
        for side in [656.0, 164, 656, 164, 656, 164] {
            window.setContentSize(NSSize(width: side, height: side))
            _ = surface.resumeRendering(forInput: true)
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: .seconds(1))
        record("resize6")
        for theme in [CubeThemePreset.prism, .auroraFlow, .moonstone, .prism] {
            model.change { $0.appearance = theme.appearance(glowIntensity: 0.7) }
            view.refreshAppearance()
            try await Task.sleep(for: .milliseconds(1100))
        }
        record("themes4")
        window.orderOut(nil)
        surface.synchronizeRenderingVisibility()
        try await Task.sleep(for: .seconds(1))
        record("hidden")
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        if let output = ProcessInfo.processInfo.environment["TCUBE_MEMORY_PROFILE_OUTPUT"] { try data.write(to: URL(fileURLWithPath: output)) }
        print("MEMORY_PROFILE \(String(decoding: data, as: UTF8.self))")
    }
}
