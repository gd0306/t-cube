import AppKit
import Combine
import CubeCore

@MainActor
final class ClipboardHistoryModel: ObservableObject {
    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var isEnabled = false
    @Published var query = ""
    @Published var status = "剪贴板历史默认关闭；启用后只记录新复制的文本。"
    private var history = ClipboardHistory()
    private var recorder: ClipboardHistoryRecorder?

    init(pasteboard: NSPasteboard = .general, schedulesPolling: Bool = true) {
        recorder = ClipboardHistoryRecorder(reader: PasteboardHistoryReader(pasteboard: pasteboard),
            schedule: schedulesPolling ? ClipboardHistoryRecorder.schedulePolling : nil) { [weak self] text in
                self?.receive(text)
            }
    }

    var visibleEntries: [ClipboardHistoryEntry] { history.filtered(query: query) }
    var totalUTF8Bytes: Int { history.totalUTF8Bytes }

    func enable() {
        guard !isEnabled else { return }
        recorder?.start()
        isEnabled = true
        status = "正在记录新复制的文本，仅在本次运行的内存中保留。"
    }

    func pause() {
        recorder?.stop()
        isEnabled = false
        status = "已暂停记录；已有历史保留在本次运行的内存中。"
    }

    func poll() { recorder?.poll() }
    func markSelfWrite() { recorder?.markSelfWrite() }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard history.delete(id) else { return false }
        entries = history.entries
        status = "已删除这条历史。"
        return true
    }

    func clear() {
        // Consume any change made before Clear so the next tick cannot re-add it.
        recorder?.markSelfWrite()
        history.clear()
        entries = []
        status = "剪贴板历史已清空。"
    }

    func shutdown() {
        pause()
        clear()
        query = ""
    }

    private func receive(_ text: String) {
        guard history.record(text) else { return }
        entries = history.entries
        status = "已记录新的文本，共 \(entries.count) 条。"
    }
}
