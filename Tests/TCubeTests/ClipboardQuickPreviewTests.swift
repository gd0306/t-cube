import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ClipboardQuickPreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_CLIPBOARD_PREVIEWS"] == "1"))
    func exportNativeGlassListAndEditor() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeQuickPreview-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let quick = ClipboardQuickController(history: history, copyText: { _ in true }, copyImage: { _ in true }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        history.enable()
        for text in ["会议记录：周三下午三点，确认本周设计稿。", "https://github.com/gd0306/t-cube", "长按 Ctrl 2 秒，单击任意历史内容复制。", "项目说明\n可在历史中编辑、保存或删除文字。"] {
            board.clearContents(); board.setString(text, forType: .string); history.poll()
        }
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/clipboard-quick-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            quick.show()
            let panel = try #require(quick.panel)
            panel.appearance = NSAppearance(named: appearance)
            for editing in [false, true] {
                if editing { quick.beginEditing(try #require(history.entries.first?.id)) }
                try await Task.sleep(for: .milliseconds(250))
                let content = try #require(panel.contentView)
                content.layoutSubtreeIfNeeded(); content.displayIfNeeded()
                let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let suffix = editing ? "editor" : "list"
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("clipboard-quick-\(suffix)-\(name).png"))
                if editing { quick.cancelEditing() }
            }
            quick.dismiss()
        }
    }
}
