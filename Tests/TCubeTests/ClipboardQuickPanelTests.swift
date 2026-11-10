import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ClipboardQuickPanelTests {
    @Test func singleClickCopiesTheCurrentEditedTextWithoutRecordingItAgain() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeQuickTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let library = SnippetLibraryController(pasteboard: board, history: history,
            model: SnippetLibraryModel(store: SnippetStore(url: directory.appendingPathComponent("content.json"))))
        defer { library.stop() }
        history.enable()
        board.clearContents(); board.setString("原文", forType: .string); history.poll()
        let entry = try #require(history.entries.first)
        let quick = library.quickHistory
        quick.show()
        #expect(quick.isVisible)
        #expect(quick.beginEditing(entry.id))
        quick.draft = "修改后的历史"
        #expect(quick.saveEdit())
        #expect(board.string(forType: .string) == "原文")
        #expect(history.entries.first?.id == entry.id)
        #expect(quick.copyText(entry.id))
        #expect(board.string(forType: .string) == "修改后的历史")
        #expect(!quick.isVisible)
        history.poll()
        #expect(history.entries.map(\.text) == ["修改后的历史"])
    }

    @Test func openingDoesNotEnableRecordingAndDraftsSurviveDismissal() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeQuickTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let quick = ClipboardQuickController(history: history, copyText: { _ in true }, copyImage: { _ in true }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        quick.show()
        #expect(!history.isEnabled)
        history.enable()
        board.clearContents(); board.setString("需要编辑", forType: .string); history.poll()
        let id = try #require(history.entries.first?.id)
        #expect(quick.beginEditing(id))
        quick.draft = "未保存的草稿"
        quick.dismiss()
        quick.show()
        #expect(quick.editingID == id)
        #expect(quick.draft == "未保存的草稿")
        quick.draft = " "
        #expect(!quick.saveEdit())
        #expect(history.entries.first?.text == "需要编辑")
        quick.cancelEditing()
        #expect(quick.editingID == nil)
        #expect(quick.draft.isEmpty)
        #expect(!quick.copyText(UUID()))
        #expect(quick.isVisible)
    }

    @Test func panelStaysWithinTheSelectedDisplayAndUsesAClearWindow() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeQuickTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let screen = NSRect(x: -640, y: 20, width: 640, height: 450)
        let quick = ClipboardQuickController(history: history, copyText: { _ in false }, copyImage: { _ in false }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        quick.show(at: NSPoint(x: -1, y: 469), visibleScreens: [screen])
        let panel = try #require(quick.panel)
        #expect(screen.contains(panel.frame))
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor.alphaComponent == 0)
        #expect(panel.canBecomeKey)
        #expect(!quick.dismissIfOutside(panel))
        #expect(quick.dismissIfOutside(nil))
        #expect(!quick.isVisible)
    }

    @Test func deletingOrClearingHistoryAlsoReleasesAnyHiddenEditDraft() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeQuickTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let quick = ClipboardQuickController(history: history, copyText: { _ in true }, copyImage: { _ in true }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        history.enable()
        for clear in [false, true] {
            board.clearContents(); board.setString("只保留在历史中的原文", forType: .string); history.poll()
            let id = try #require(history.entries.first?.id)
            #expect(quick.beginEditing(id))
            quick.draft = "需要释放的未保存内容"
            quick.dismiss()
            if clear { history.clearText() } else { history.delete(id) }
            #expect(quick.editingID == nil)
            #expect(quick.draft.isEmpty)
        }
    }
}
