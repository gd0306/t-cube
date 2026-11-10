import AppKit
import Combine
import CubeCore

@MainActor
final class ClipboardHistoryModel: ObservableObject {
    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var images: [ClipboardHistoryImage] = []
    @Published private(set) var isEnabled = false
    @Published var query = ""
    @Published var status = "剪贴板历史默认关闭；启用后只记录新复制的文本和图片。"
    private var history = ClipboardHistory()
    private var recorder: ClipboardHistoryRecorder?

    init(pasteboard: NSPasteboard = .general, schedulesPolling: Bool = true) {
        recorder = ClipboardHistoryRecorder(reader: PasteboardHistoryReader(pasteboard: pasteboard),
            schedule: schedulesPolling ? ClipboardHistoryRecorder.schedulePolling : nil,
            receivedImage: { [weak self] image in self?.receive(image) },
            receivedImageIssue: { [weak self] issue in self?.status = issue },
            receivedText: { [weak self] text in self?.receive(text) })
    }

    var visibleEntries: [ClipboardHistoryEntry] { history.filtered(query: query) }
    var totalUTF8Bytes: Int { history.totalUTF8Bytes }
    var totalImageBytes: Int { history.totalImageBytes }

    func mergedText(selectedIDs: Set<UUID>, trimLines: Bool, collapseBlankLines: Bool) -> String? {
        history.mergedText(selectedIDs: selectedIDs, query: query, trimLines: trimLines, collapseBlankLines: collapseBlankLines)
    }

    func enable() {
        guard !isEnabled else { return }
        recorder?.start()
        isEnabled = true
        status = "正在记录新复制的文本和图片，仅在本次运行的内存中保留。"
    }

    func pause() {
        recorder?.stop()
        isEnabled = false
        status = "已暂停记录；已有历史保留在本次运行的内存中。"
    }

    func poll() { recorder?.poll() }
    func markSelfWrite() { recorder?.markSelfWrite() }

    @discardableResult
    func updateText(id: UUID, text: String) -> Bool {
        guard history.updateText(id: id, text: text) else {
            status = "无法保存：记录可能已删除，或文字为空、含无效字符、超过单条 64 KiB／总计 2 MiB 上限。"
            return false
        }
        entries = history.entries
        status = "已保存修改；系统剪贴板保持原样。"
        return true
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard history.delete(id) else { return false }
        entries = history.entries
        status = "已删除这条历史。"
        return true
    }

    @discardableResult
    func deleteImage(_ id: UUID) -> Bool {
        guard history.deleteImage(id) else { return false }
        images = history.images
        status = "已删除这张图片。"
        return true
    }

    func clearText() {
        recorder?.clearTextCapture()
        history.clearText()
        entries = []
        status = "文字历史已清空；图片历史保留。"
    }

    func clearImages() {
        recorder?.clearImageCapture()
        history.clearImages()
        images = []
        status = "图片历史已清空；文字历史保留。"
    }

    func clear() {
        // Consume any change made before Clear so the next tick cannot re-add it.
        recorder?.markSelfWrite()
        history.clear()
        entries = []
        images = []
        status = "剪贴板历史已清空。"
    }

    func shutdown() {
        pause()
        clear()
        query = ""
    }

    private func receive(_ image: ClipboardHistoryImagePayload) {
        guard history.recordImage(pngData: image.pngData, thumbnailPNG: image.thumbnailPNG,
            width: image.width, height: image.height) else { return }
        images = history.images
        status = "已记录新的图片，共 \(images.count) 张。"
    }

    private func receive(_ text: String) {
        guard history.record(text) else { return }
        entries = history.entries
        status = "已记录新的文本，共 \(entries.count) 条。"
    }
}
