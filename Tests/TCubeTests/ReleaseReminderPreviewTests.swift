import AppKit
import CubeCore
import SwiftUI
import Testing
@testable import TCube

@MainActor
struct ReleaseReminderPreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_REMINDER_PREVIEW"] == "1"))
    func reminderSettingsShowManualDownloadFlowWithoutCredentialsOrNetwork() async throws {
        _ = NSApplication.shared
        let data = try JSONSerialization.data(withJSONObject: ["tag_name": "v0.20.0", "draft": false, "prerelease": false,
            "html_url": "https://github.com/gd0306/t-cube/releases/tag/v0.20.0"])
        let model = ReleaseReminderModel(currentVersion: "0.19.0", store: ReminderMemoryStore(),
            fetch: { try ReleaseNotice.decode(data) })
        await model.check(manual: true)
        let controller = LifecycleController(reminder: model)
        defer { controller.stop() }
        let hosting = NSHostingView(rootView: LifecycleSettingsView(controller: controller).environment(\.colorScheme, .light))
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 680, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting; window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(250))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/release-reminder-verification/settings-preview.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
        #expect(!model.enabled && model.availableRelease?.version.description == "0.20.0")
    }
}
