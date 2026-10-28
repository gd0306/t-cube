import Foundation
import Combine
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ConfigurationMaintenanceTests {
    @Test func scanIdentifiesMissingAndWrongKindSlotsWithoutRemovingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var configuration = CubeConfiguration()
        try configuration.add(LauncherItem(url: root.appendingPathComponent("Missing.app"), name: "丢失", kind: .application), to: .front)
        try configuration.add(LauncherItem(url: folder, name: "类型不符", kind: .application), to: .right)
        try configuration.add(LauncherItem(url: folder, name: "有效", kind: .folder), to: .top)
        let issues = BrokenLauncherScanner.scan(configuration)
        #expect(issues.count == 2)
        #expect(issues.contains { $0.face == .front && $0.slot == 0 && $0.item.name == "丢失" })
        #expect(issues.contains { $0.face == .right && $0.slot == 0 && $0.item.name == "类型不符" })
        #expect(configuration.group(for: .front).slots[0] != nil)
    }

    @Test func previewDoesNotModifyFilesAndCancelClearsIt() throws {
        try withController { controller, model, store, directory in
            let archive = try ConfigurationArchive(configuration: CubeConfiguration(), contentLibrary: SnippetLibrary(items: [TextSnippet(title: "待导入", body: "正文")]))
            let url = directory.appendingPathComponent("incoming.json")
            try archive.encoded().write(to: url)
            controller.prepareImport(from: url)
            #expect(controller.pendingImport?.archive.contentCount == 1)
            #expect(model.configuration.group(for: .front).name == "常用")
            #expect(!FileManager.default.fileExists(atPath: store.contentLibraryURL.path))
            controller.cancelImport()
            #expect(controller.pendingImport == nil)
        }
    }

    @Test func confirmedImportUpdatesModelAndPostsLibraryReloadAfterPersistence() throws {
        try withController { controller, model, store, directory in
            var configuration = CubeConfiguration()
            try configuration.rename(.front, to: "已恢复")
            let library = SnippetLibrary(items: [TextSnippet(title: "内容", body: "正文")])
            let archive = try ConfigurationArchive(configuration: configuration, contentLibrary: library)
            let url = directory.appendingPathComponent("incoming.json")
            try archive.encoded().write(to: url)
            var notifiedURL: URL?
            var notifiedAfterPersistence = false
            let subscription = NotificationCenter.default.publisher(for: .tCubeLibraryDidRestore).sink { notification in
                notifiedURL = notification.object as? URL
                notifiedAfterPersistence = (try? SnippetStore(url: store.contentLibraryURL).load()) == library
            }
            defer { subscription.cancel() }
            controller.prepareImport(from: url)
            #expect(controller.confirmImport())
            #expect(model.configuration == configuration)
            #expect(try ConfigurationStore(url: store.configurationURL).load() == configuration)
            #expect(try SnippetStore(url: store.contentLibraryURL).load() == library)
            #expect(controller.pendingImport == nil)
            #expect(controller.backupFiles.count == 1)
            #expect(notifiedURL == store.contentLibraryURL)
            #expect(notifiedAfterPersistence)
            #expect(controller.error == nil)
        }
    }

    @Test func invalidImportKeepsLiveDataAndReportsInlineError() throws {
        try withController { controller, model, store, directory in
            let original = model.configuration
            let url = directory.appendingPathComponent("damaged.json")
            try Data("broken".utf8).write(to: url)
            controller.prepareImport(from: url)
            #expect(controller.pendingImport == nil)
            #expect(controller.error != nil)
            #expect(model.configuration == original)
            #expect(try store.backups().isEmpty)
        }
    }

    private func withController(_ body: (ConfigurationMaintenance, AppModel, ConfigurationArchiveStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("configuration.json")
        let model = AppModel(store: ConfigurationStore(url: url))
        let store = ConfigurationArchiveStore(configurationURL: url,
            contentLibraryURL: directory.appendingPathComponent("content-library.json"))
        try body(ConfigurationMaintenance(model: model, archiveStore: store), model, store, directory)
        model.stopThemeCycle()
    }
}
