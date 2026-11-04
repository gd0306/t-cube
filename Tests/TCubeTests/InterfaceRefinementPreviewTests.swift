import AppKit
import SwiftUI
import Testing
import CubeCore
@testable import TCube

@MainActor
struct InterfaceRefinementPreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_INTERFACE_PREVIEWS"] == "1"))
    func exportSettingsPagesWithIsolatedPreferencesInBothAppearances() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        try configuration.add(LauncherItem(url: URL(string: "https://example.com/work/projects/long-path")!,
            name: "项目资料与常用工具网页", kind: .website), to: .front)
        try store.save(configuration)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        let suite = "TCube.InterfacePreview.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let desktop = DesktopAutoHideSettings(defaults: defaults)
        let performance = PerformanceSettings(defaults: defaults)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/interface-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua),
                                          ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua)] {
            let pages: [(String, AnyView)] = [
                ("entries", AnyView(EditorView(model: model, performance: performance, desktop: desktop))),
                ("appearance", AnyView(AppearanceSettingsView(model: model))),
                ("desktop", AnyView(DesktopSettingsView(model: model, desktop: desktop, performance: performance)))
            ]
            for (page, root) in pages {
                let hosting = NSHostingView(rootView: root
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme))
                let window = NSPanel(contentRect: NSRect(x: 120, y: 120, width: 800, height: 580),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.contentView = hosting
                window.orderFrontRegardless()
                defer { window.orderOut(nil); window.contentView = nil }
                try await Task.sleep(for: .milliseconds(300))
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("settings-\(page)-\(name).png"))
            }
        }
        #expect(try store.load() == configuration)
        #expect(!desktop.edgeCollapseEnabled && performance.idlePowerSavingEnabled)
    }
}
