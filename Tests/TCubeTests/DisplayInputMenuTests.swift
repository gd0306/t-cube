import AppKit
import Testing
import CubeCore
@testable import TCube

private final class InputPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor @Suite(.serialized) struct DisplayInputMenuTests {
    @Test func readyAndUnknownRowsExposeControlsAndSource() throws {
        _ = NSApplication.shared
        let target = DisplayBrightnessTarget(id: 2, uuid: UUID().uuidString, name: "Example", isBuiltIn: false)
        let mapping = DisplayInputMapping(typeC: 7, hdmi: 5)!
        let row = DisplayInputMenuRow(row: .init(target: target, mapping: mapping, current: 5, busy: false), change: { _, _ in }, configure: { _ in }, reload: {})
        let slider = try #require(row.subviews.compactMap { $0 as? NSSlider }.first)
        #expect(slider.isEnabled && slider.doubleValue == 1)
        #expect(slider.accessibilityHelp()?.contains("HDMI") == true)
        #expect(row.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "当前：HDMI" })
        #expect(row.subviews.compactMap { $0 as? NSButton }.filter { !$0.isEnabled }.isEmpty)
        row.apply(.init(target: target, current: 16, busy: false))
        #expect(!slider.isEnabled)
        #expect(row.subviews.compactMap { $0 as? NSButton }.filter { !$0.isEnabled }.isEmpty)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_INPUT_PREVIEWS"] == "1"))
    func exportInputRows() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/display-input-previews")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 304, height: 405)); content.wantsLayer = true
            let window = InputPreviewPanel(contentRect: content.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = content
            window.appearance?.performAsCurrentDrawingAppearance { content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
            let target = DisplayBrightnessTarget(id: 2, uuid: UUID().uuidString, name: "27C1U-D", isBuiltIn: false)
            let rows = [DisplayInputRow(target: target, mapping: DisplayInputMapping(typeC: 7, hdmi: 5), current: 7, busy: false), DisplayInputRow(target: target, mapping: DisplayInputMapping(typeC: 7, hdmi: 5), current: 5, busy: false), DisplayInputRow(target: target, current: 16, busy: false, message: "当前输入代码 16；请设置映射"), DisplayInputRow(target: target, busy: false, message: "命令已发送，无法确认")]
            for (index, state) in rows.enumerated() {
                let row = DisplayInputMenuRow(row: state, change: { _, _ in }, configure: { _ in }, reload: {})
                row.frame.origin = CGPoint(x: 8, y: 305 - 96 * index); content.addSubview(row)
            }
            window.makeKeyAndOrderFront(nil); NSApp.activate(); content.layoutSubtreeIfNeeded()
            defer { window.orderOut(nil); window.contentView = nil }
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("input-menu-\(name).png"))
        }
    }
}
