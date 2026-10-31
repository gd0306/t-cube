import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ClipboardHistoryIntegrationTests {
    @Test func controllerCopiesWithoutRecordingItsOwnClipboardWrite() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("TCubeTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let controller = SnippetLibraryController(pasteboard: board, history: history,
            model: SnippetLibraryModel(store: SnippetStore(url: directory.appendingPathComponent("content.json"))))
        defer { controller.stop() }
        history.enable()
        board.clearContents()
        #expect(board.setString("external copy", forType: .string))
        history.poll()
        #expect(history.entries.map(\.text) == ["external copy"])
        controller.use("test copy", paste: false)
        #expect(board.string(forType: .string) == "test copy")
        history.poll()
        #expect(history.entries.map(\.text) == ["external copy"])
        controller.stop()
        #expect(!history.isEnabled)
        #expect(history.entries.isEmpty)
    }

    @Test func openingHistoryPreservesAnAttachedEditorOrTemplateSheet() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: NSPasteboard.Name("TCubeTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let controller = SnippetLibraryController(pasteboard: board, history: history,
            model: SnippetLibraryModel(store: SnippetStore(url: directory.appendingPathComponent("content.json"))))
        controller.show()
        let panel = try #require(NSApp.windows.first { $0.title == "T-Cube · 常用内容" })
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        panel.beginSheet(sheet)
        defer { panel.endSheet(sheet); panel.orderOut(nil); controller.stop() }
        #expect(panel.attachedSheet === sheet)
        let resets = HistoryNotificationCounter()
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name("TCubeSnippetSearchFocus"), object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { resets.count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        controller.showHistory()
        #expect(panel.attachedSheet === sheet)
        #expect(resets.count == 0)
    }

}

@MainActor
private final class HistoryNotificationCounter { var count = 0 }
