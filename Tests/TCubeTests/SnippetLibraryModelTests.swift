import Foundation
import CubeCore
import Testing
@testable import TCube

@MainActor
struct SnippetLibraryModelTests {
    @Test func savingEditingAndDeletingPersistBeforePublishing() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SnippetStore(url: url)
        let model = SnippetLibraryModel(store: store)
        var snippet = TextSnippet(title: "公司信息", group: "工作", body: "上海办公室")

        #expect(model.save(snippet))
        #expect(try store.load().items == [snippet])
        #expect(model.selectedID == snippet.id)
        snippet.body = "北京办公室"
        #expect(model.save(snippet))
        #expect(model.items.count == 1)
        #expect(try store.load().items.first?.body == "北京办公室")
        #expect(model.delete(snippet.id))
        #expect(model.items.isEmpty)
        #expect(try store.load().items.isEmpty)
    }

    @Test func failedSaveKeepsPublishedLibraryAndSelection() throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(url: url)
        let original = TextSnippet(title: "已保存", body: "原始文本")
        try store.save(SnippetLibrary(items: [original]))
        let model = SnippetLibraryModel(store: store)
        model.selectedID = original.id
        try FileManager.default.removeItem(at: directory)
        try Data("阻止写入".utf8).write(to: directory)

        #expect(!model.save(TextSnippet(title: "新内容", body: "不能写入")))
        #expect(model.items == [original])
        #expect(model.selectedID == original.id)
        #expect(model.error != nil)
    }

    @Test func corruptLibraryDisablesMutationsAndPreservesOriginalBytes() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{ broken content".utf8)
        try original.write(to: url)
        let model = SnippetLibraryModel(store: SnippetStore(url: url))

        #expect(!model.mutationsEnabled)
        #expect(model.error != nil)
        #expect(!model.save(TextSnippet(title: "新内容", body: "内容")))
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func favoritesPersistAndCannotMoveAcrossFavoriteBoundary() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SnippetStore(url: url)
        let first = TextSnippet(title: "第一项", body: "一")
        let second = TextSnippet(title: "第二项", body: "二")
        try store.save(SnippetLibrary(items: [first, second]))
        let model = SnippetLibraryModel(store: store)

        #expect(model.toggleFavorite(second.id))
        #expect(model.visibleItems.map(\.id) == [second.id, first.id])
        #expect(try store.load().items.last?.isFavorite == true)
        #expect(!model.canMove(second.id, by: 1))
        #expect(!model.canMove(first.id, by: -1))
        #expect(!model.move(second.id, by: -1))
        #expect(try store.load().items.map(\.id) == [first.id, second.id])
    }

    @Test func movingInterleavedFavoritesChangesVisibleOrderAndPreservesNormalPositions() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SnippetStore(url: url)
        let first = TextSnippet(title: "收藏一", body: "一", isFavorite: true)
        let normalOne = TextSnippet(title: "普通一", body: "二")
        let normalTwo = TextSnippet(title: "普通二", body: "三")
        let second = TextSnippet(title: "收藏二", body: "四", isFavorite: true)
        try store.save(SnippetLibrary(items: [first, normalOne, normalTwo, second]))
        let model = SnippetLibraryModel(store: store)

        #expect(!model.canMove(first.id, by: -1))
        #expect(!model.canMove(second.id, by: 1))
        #expect(model.move(second.id, by: -1))
        #expect(model.visibleItems.map(\.id) == [second.id, first.id, normalOne.id, normalTwo.id])
        #expect(try store.load().items.map(\.id) == [second.id, normalOne.id, normalTwo.id, first.id])
    }

    @Test func movingWithinFilteredResultsLeavesHiddenItemsInPlace() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SnippetStore(url: url)
        let first = TextSnippet(title: "工作一", group: "工作", body: "一", isFavorite: true)
        let hidden = TextSnippet(title: "个人", group: "个人", body: "二", isFavorite: true)
        let second = TextSnippet(title: "工作二", group: "工作", body: "三", isFavorite: true)
        try store.save(SnippetLibrary(items: [first, hidden, second]))
        let model = SnippetLibraryModel(store: store)
        model.selectedGroup = "工作"

        #expect(!model.canMove(first.id, by: -1))
        #expect(!model.canMove(second.id, by: 1))
        #expect(model.move(second.id, by: -1))
        #expect(model.visibleItems.map(\.id) == [second.id, first.id])
        #expect(try store.load().items.map(\.id) == [second.id, hidden.id, first.id])
    }

    @Test func searchGroupAndFavoritesCombineAndGroupsRemainAvailable() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let wanted = TextSnippet(title: "银行", group: "工作", fields: [SnippetField(label: "账号", value: "12345")], isFavorite: true)
        let other = TextSnippet(title: "私人银行", group: "个人", body: "12345")
        let store = SnippetStore(url: url)
        try store.save(SnippetLibrary(items: [wanted, other]))
        let model = SnippetLibraryModel(store: store)
        model.query = "12345"
        model.selectedGroup = "工作"
        model.favoritesOnly = true

        #expect(model.visibleItems.map(\.id) == [wanted.id])
        #expect(Set(model.groups) == Set(["工作", "个人"]))
        model.query = "不存在"
        #expect(model.visibleItems.isEmpty)
        #expect(model.items.count == 2)
    }

    @Test func savingRevealsContentExcludedByCurrentFilters() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = SnippetLibraryModel(store: SnippetStore(url: url))
        model.query = "旧内容"
        model.selectedGroup = "工作"
        model.favoritesOnly = true
        let snippet = TextSnippet(title: "新地址", group: "个人", body: "上海")

        #expect(model.save(snippet))
        #expect(model.selectedSnippet?.id == snippet.id)
        #expect(model.visibleItems.map(\.id) == [snippet.id])
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TCube-SnippetModel-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("content-library.json")
    }
}
