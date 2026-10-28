import Foundation
import Testing
import CubeCore
@testable import TCube

@MainActor
struct SnippetRestoreTests {
    @Test func restoredLibraryReplacesLiveSearchStateOnlyForItsOwnStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SnippetStore(url: folder.appendingPathComponent("library.json"))
        let model = SnippetLibraryModel(store: store)
        model.query = "旧内容"
        model.favoritesOnly = true
        let restored = TextSnippet(title: "收件地址", group: "办公", body: "办公地址")
        try store.save(SnippetLibrary(items: [restored]))
        model.reloadIfMatchingStore(folder.appendingPathComponent("other.json"))
        #expect(model.items.isEmpty)
        model.reloadIfMatchingStore(store.url)
        #expect(model.selectedSnippet == restored)
        #expect(model.query.isEmpty)
        #expect(!model.favoritesOnly)
        try Data("broken".utf8).write(to: store.url)
        model.reloadIfMatchingStore(store.url)
        #expect(!model.mutationsEnabled)
        #expect(model.error != nil)
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "broken")
    }
}
