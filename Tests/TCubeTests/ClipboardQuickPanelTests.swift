import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ClipboardQuickPanelTests {
    @Test func launchRecordsNewCopiesAndPreparesThePanelWithoutShowingIt() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeQuickTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("启动前的内容", forType: .string)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let library = SnippetLibraryController(pasteboard: board, history: history,
            model: SnippetLibraryModel(store: SnippetStore(url: directory.appendingPathComponent("content.json"))))
        defer { library.stop() }
        library.start()
        #expect(history.isEnabled)
        history.poll()
        #expect(history.entries.isEmpty)
        let prepared = try #require(library.quickHistory.panel)
        #expect(!prepared.isVisible)
        board.clearContents(); board.setString("启动后新复制的内容", forType: .string); history.poll()
        #expect(history.entries.map(\.text) == ["启动后新复制的内容"])
        library.quickHistory.show()
        #expect(library.quickHistory.panel === prepared)
        #expect(prepared.isVisible)
        history.pause()
        library.quickHistory.dismiss()
        library.quickHistory.show()
        #expect(!history.isEnabled)
    }

    @Test func processingCopiesOnlyThePreviewAndRejectsInvalidOrDeletedSources() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeProcessTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        var copied: String?
        let quick = ClipboardQuickController(history: history, copyText: { copied = $0; return true }, copyImage: { _ in false }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        history.enable()
        board.clearContents(); board.setString("a+b%20c", forType: .string); history.poll()
        let entry = try #require(history.entries.first)
        #expect(quick.beginProcessing(entry.id, action: .urlDecode))
        #expect(copied == nil)
        #expect(board.string(forType: .string) == entry.text)
        #expect(try quick.processingResult?.get() == "a+b c")
        #expect(quick.copyProcessed())
        #expect(copied == "a+b c")
        #expect(history.entries == [entry])
        copied = nil
        #expect(quick.beginProcessing(entry.id, action: .urlDecode))
        #expect(quick.saveProcessed())
        #expect(history.entries.first?.text == "a+b c")
        #expect(history.entries.first?.capturedAt == entry.capturedAt)
        #expect(board.string(forType: .string) == entry.text)
        #expect(!quick.beginProcessing(entry.id, action: .jsonPretty))
        #expect(quick.processingID == nil)
        #expect(quick.status.contains("JSON"))
        #expect(!quick.copyProcessed())
        #expect(copied == nil)
        #expect(quick.beginProcessing(entry.id, action: .uppercase))
        history.delete(entry.id)
        #expect(quick.processingID == nil)
        #expect(!quick.copyProcessed())
    }

    @Test func previewAllowsEditingBeforeCopyWithoutOverwritingHistory() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeProcessEditTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        var copied: String?
        let quick = ClipboardQuickController(history: history, copyText: { copied = $0; return true }, copyImage: { _ in false }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        history.enable(); board.clearContents(); board.setString("hello", forType: .string); history.poll()
        let entry = try #require(history.entries.first)
        #expect(quick.beginProcessing(entry.id, action: .uppercase))
        #expect(copied == nil)
        quick.isEditingProcessing = true; quick.processingDraft = "重新编辑的结果"
        #expect(quick.copyProcessed())
        #expect(copied == "重新编辑的结果")
        #expect(history.entries.first == entry)
        #expect(quick.processingDraft.isEmpty)
        #expect(quick.beginProcessing(entry.id, action: .uppercase))
        history.updateText(id: entry.id, text: "外部改动")
        #expect(quick.processingID == nil)
        #expect(quick.processingDraft.isEmpty)
    }

    @Test func processingPreviewAndEditorStayWithinTheDisplay() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeProcessSizeTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let quick = ClipboardQuickController(history: history, copyText: { _ in true }, copyImage: { _ in false }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        history.enable(); board.clearContents(); board.setString("[" + Array(repeating: "123", count: 40).joined(separator: ",") + "]", forType: .string); history.poll()
        let screen = NSRect(x: 0, y: 0, width: 640, height: 450)
        quick.show(at: NSPoint(x: 320, y: 300), visibleScreens: [screen])
        let panel = try #require(quick.panel)
        let expectedSize = panel.frame.size
        quick.beginProcessing(try #require(history.entries.first?.id), action: .jsonPretty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(panel.frame.size == expectedSize)
        #expect(screen.contains(panel.frame))
        quick.isEditingProcessing = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(panel.frame.size == expectedSize)
        #expect(screen.contains(panel.frame))
    }

    @Test func everyFreshShowReturnsToTheListAndDropsOnlyUnsavedPreviewState() throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeReopenPreview-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let quick = ClipboardQuickController(history: history, copyText: { _ in true }, copyImage: { _ in false }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        history.enable(); board.clearContents(); board.setString("hello", forType: .string); history.poll()
        let entry = try #require(history.entries.first)
        for staysVisible in [false, true] {
            quick.show()
            #expect(quick.beginProcessing(entry.id, action: .uppercase))
            quick.isEditingProcessing = true; quick.processingDraft = "尚未保存"
            if !staysVisible { quick.dismiss() }
            quick.show()
            #expect(quick.processingID == nil)
            #expect(quick.processingDraft.isEmpty)
            #expect(quick.editingID == nil)
            #expect(history.entries == [entry])
            #expect(board.string(forType: .string) == "hello")
        }
    }

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

    @Test func reopeningStartsAtTheListWithoutEnablingRecordingOrSavingDrafts() throws {
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
        #expect(quick.editingID == nil)
        #expect(quick.draft.isEmpty)
        #expect(history.entries.first?.text == "需要编辑")
        #expect(quick.beginEditing(id))
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
