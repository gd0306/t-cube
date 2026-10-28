import Combine
import CubeCore
import Foundation

@MainActor
final class SnippetLibraryModel: ObservableObject {
    @Published private(set) var library = SnippetLibrary()
    @Published var query = ""
    @Published var selectedGroup: String?
    @Published var favoritesOnly = false
    @Published var selectedID: UUID?
    @Published var pendingCapture: String?
    @Published var status = "选择内容，复制或粘贴到原来的输入框。"
    @Published var error: String?
    @Published private(set) var mutationsEnabled = true

    private let store: SnippetStore

    init(store: SnippetStore = SnippetStore(url: SnippetStore.defaultURL)) {
        self.store = store
        do {
            library = try store.load()
            selectedID = library.filtered(query: "").first?.id
        } catch {
            self.error = "无法读取内容库：\(error.localizedDescription)"
            status = "原文件已保留。请修复内容库文件后重新打开应用。"
            mutationsEnabled = false
        }
    }

    func reloadIfMatchingStore(_ url: URL) {
        guard url.standardizedFileURL == store.url.standardizedFileURL else { return }
        do {
            let restored = try store.load()
            library = restored
            query = ""
            selectedGroup = nil
            favoritesOnly = false
            selectedID = restored.filtered(query: "").first?.id
            error = nil
            mutationsEnabled = true
            status = "内容库已从导入或备份更新。"
        } catch {
            self.error = "无法读取恢复后的内容库：\(error.localizedDescription)"
            mutationsEnabled = false
        }
    }

    var items: [TextSnippet] { library.items }

    var visibleItems: [TextSnippet] {
        library.filtered(query: query, group: selectedGroup, favoritesOnly: favoritesOnly)
    }

    var groups: [String] {
        Array(Set(items.map(\.group).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var selectedSnippet: TextSnippet? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    @discardableResult
    func save(_ snippet: TextSnippet) -> Bool {
        var candidate = library
        var saved = snippet
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.group = saved.group.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = candidate.items.firstIndex(where: { $0.id == saved.id }) {
            candidate.items[index] = saved
        } else {
            candidate.items.append(saved)
        }
        guard persist(candidate, status: "已保存「\(saved.title)」。") else { return false }
        if !candidate.filtered(query: query).contains(where: { $0.id == saved.id }) { query = "" }
        if let selectedGroup, selectedGroup != saved.group { self.selectedGroup = nil }
        if favoritesOnly && !saved.isFavorite { favoritesOnly = false }
        selectedID = saved.id
        return true
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        var candidate = library
        candidate.items.removeAll { $0.id == id }
        guard persist(candidate, status: "已删除内容。") else { return false }
        if let selectedGroup, !groups.contains(selectedGroup) { self.selectedGroup = nil }
        if selectedID == id { selectedID = visibleItems.first?.id }
        return true
    }

    @discardableResult
    func toggleFavorite(_ id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var candidate = library
        candidate.items[index].isFavorite.toggle()
        return persist(candidate, status: candidate.items[index].isFavorite ? "已加入收藏。" : "已取消收藏。")
    }

    func canMove(_ id: UUID, by offset: Int) -> Bool {
        mutationsEnabled && movementIndices(id, by: offset) != nil
    }

    @discardableResult
    func move(_ id: UUID, by offset: Int) -> Bool {
        guard mutationsEnabled, let (source, destination) = movementIndices(id, by: offset) else { return false }
        var candidate = library
        candidate.items.swapAt(source, destination)
        return persist(candidate, status: "已调整内容顺序。收藏内容始终优先显示。")
    }

    private func movementIndices(_ id: UUID, by offset: Int) -> (Int, Int)? {
        guard offset == -1 || offset == 1 else { return nil }
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }),
              visible.indices.contains(index + offset),
              visible[index].isFavorite == visible[index + offset].isFavorite,
              let source = items.firstIndex(where: { $0.id == id }),
              let destination = items.firstIndex(where: { $0.id == visible[index + offset].id }) else { return nil }
        return (source, destination)
    }

    private func persist(_ candidate: SnippetLibrary, status: String) -> Bool {
        guard mutationsEnabled else { return false }
        do {
            try store.save(candidate)
            library = candidate
            error = nil
            self.status = status
            return true
        } catch {
            self.error = "保存失败：\(error.localizedDescription)"
            return false
        }
    }
}
