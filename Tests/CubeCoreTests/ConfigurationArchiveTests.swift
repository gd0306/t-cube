import Foundation
import Testing
@testable import CubeCore

struct ConfigurationArchiveTests {
    @Test func archiveRoundTripKeepsLauncherAndLibraryData() throws {
        var configuration = CubeConfiguration()
        try configuration.rename(.front, to: "我的应用")
        try configuration.add(LauncherItem(url: URL(fileURLWithPath: "/Applications/Test.app"), name: "Test", kind: .application), to: .front)
        let library = SnippetLibrary(items: [TextSnippet(title: "地址", body: "完整正文")])
        let archive = try ConfigurationArchive(configuration: configuration, contentLibrary: library)
        let restored = try ConfigurationArchive.decode(archive.encoded())
        #expect(restored.configuration == configuration)
        #expect(restored.contentLibrary == library)
        #expect(restored.launcherCount == 1)
        #expect(restored.contentCount == 1)
    }

    @Test func unsupportedAndInvalidArchivesAreRejected() throws {
        let archive = try ConfigurationArchive(configuration: CubeConfiguration(), contentLibrary: SnippetLibrary())
        var json = try #require(JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any])
        json["version"] = 99
        #expect(throws: ConfigurationArchiveError.unsupportedVersion(99)) {
            try ConfigurationArchive.decode(JSONSerialization.data(withJSONObject: json))
        }
        json["version"] = 1
        json["contentLibrary"] = ["version": 1, "items": [["id": UUID().uuidString, "title": "", "group": "", "body": "hello", "fields": [], "isFavorite": false]]]
        #expect(throws: SnippetLibraryError.emptyTitle) {
            try ConfigurationArchive.decode(JSONSerialization.data(withJSONObject: json))
        }
    }

    @Test func exportRejectsLiveFileThroughParentSymlink() throws {
        try withTemporaryStore { store in
            try ConfigurationStore(url: store.configurationURL).save(CubeConfiguration())
            try SnippetStore(url: store.contentLibraryURL).save(SnippetLibrary())
            let originalConfiguration = try Data(contentsOf: store.configurationURL)
            let originalLibrary = try Data(contentsOf: store.contentLibraryURL)
            let directory = store.configurationURL.deletingLastPathComponent()
            let alias = directory.appendingPathComponent("parent-alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
            for liveURL in [store.configurationURL, store.contentLibraryURL] {
                let destination = alias.appendingPathComponent(liveURL.lastPathComponent)
                #expect(throws: (any Error).self) { try store.export(to: destination) }
            }
            #expect(try Data(contentsOf: store.configurationURL) == originalConfiguration)
            #expect(try Data(contentsOf: store.contentLibraryURL) == originalLibrary)
        }
    }

    @Test func exportRejectsHardLinkedLiveFile() throws {
        try withTemporaryStore { store in
            try ConfigurationStore(url: store.configurationURL).save(CubeConfiguration())
            let original = try Data(contentsOf: store.configurationURL)
            let alias = store.configurationURL.deletingLastPathComponent().appendingPathComponent("hard-link.json")
            try FileManager.default.linkItem(at: store.configurationURL, to: alias)
            #expect(throws: (any Error).self) { try store.export(to: alias) }
            #expect(try Data(contentsOf: store.configurationURL) == original)
            #expect(try Data(contentsOf: alias) == original)
        }
    }

    @Test func exportRejectsCaseAliasOnCaseInsensitiveVolume() throws {
        try withTemporaryStore { store in
            try ConfigurationStore(url: store.configurationURL).save(CubeConfiguration())
            let original = try Data(contentsOf: store.configurationURL)
            let alias = store.configurationURL.deletingLastPathComponent().appendingPathComponent("CONFIGURATION.JSON")
            // On a case-sensitive volume this is a distinct, valid export destination.
            guard FileManager.default.fileExists(atPath: alias.path) else { return }
            #expect(throws: (any Error).self) { try store.export(to: alias) }
            #expect(try Data(contentsOf: store.configurationURL) == original)
        }
    }

    @Test func exportRejectsCaseAliasBeforeLiveFileExists() throws {
        try withTemporaryStore { store in
            let directory = store.configurationURL.deletingLastPathComponent()
            let probe = directory.appendingPathComponent("case-probe")
            try Data().write(to: probe)
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("CASE-PROBE").path) else { return }
            let alias = directory.appendingPathComponent("CONFIGURATION.JSON")
            #expect(throws: (any Error).self) { try store.export(to: alias) }
            #expect(!FileManager.default.fileExists(atPath: store.configurationURL.path))
        }
    }

    @Test func replacementCreatesRestorableBackupBeforeChangingBothFiles() throws {
        try withTemporaryStore { store in
            var previous = CubeConfiguration()
            try previous.rename(.front, to: "旧应用")
            let previousLibrary = SnippetLibrary(items: [TextSnippet(title: "旧内容", body: "保留")])
            try ConfigurationStore(url: store.configurationURL).save(previous)
            try SnippetStore(url: store.contentLibraryURL).save(previousLibrary)
            var next = CubeConfiguration()
            try next.rename(.front, to: "新应用")
            let incoming = try ConfigurationArchive(configuration: next, contentLibrary: SnippetLibrary())
            let backup = try store.restore(incoming)
            #expect(try ConfigurationStore(url: store.configurationURL).load() == next)
            #expect(try SnippetStore(url: store.contentLibraryURL).load().items.isEmpty)
            let saved = try ConfigurationArchive.decode(Data(contentsOf: backup))
            #expect(saved.configuration == previous)
            #expect(saved.contentLibrary == previousLibrary)
            let backups = try store.backups()
            #expect(backups.map(\.standardizedFileURL.path) == [backup.standardizedFileURL.path])
            _ = try store.restore(saved)
            #expect(try ConfigurationStore(url: store.configurationURL).load() == previous)
            #expect(try SnippetStore(url: store.contentLibraryURL).load() == previousLibrary)
        }
    }

    @Test func corruptCurrentDataBlocksReplacementAndPreservesOriginalBytes() throws {
        try withTemporaryStore { store in
            let damaged = Data("broken configuration".utf8)
            try damaged.write(to: store.configurationURL)
            let incoming = try ConfigurationArchive(configuration: CubeConfiguration(), contentLibrary: SnippetLibrary())
            #expect(throws: (any Error).self) { try store.restore(incoming) }
            #expect(try Data(contentsOf: store.configurationURL) == damaged)
            #expect(!FileManager.default.fileExists(atPath: store.contentLibraryURL.path))
            #expect(try store.backups().isEmpty)
        }
    }

    @Test func corruptLibraryBlocksReplacementWithoutChangingValidConfiguration() throws {
        try withTemporaryStore { store in
            try ConfigurationStore(url: store.configurationURL).save(CubeConfiguration())
            let original = try Data(contentsOf: store.configurationURL)
            let damaged = Data("{ broken library".utf8)
            try damaged.write(to: store.contentLibraryURL)
            let incoming = try ConfigurationArchive(configuration: CubeConfiguration(), contentLibrary: SnippetLibrary())
            #expect(throws: (any Error).self) { try store.restore(incoming) }
            #expect(try Data(contentsOf: store.configurationURL) == original)
            #expect(try Data(contentsOf: store.contentLibraryURL) == damaged)
            #expect(try store.backups().isEmpty)
        }
    }

    @Test func failedImportIntoNewStoreRemovesNewlyWrittenConfiguration() throws {
        try withTemporaryStore { store in
            let libraryURL = store.contentLibraryURL
            let failing = ConfigurationArchiveStore(configurationURL: store.configurationURL,
                contentLibraryURL: libraryURL, backupsURL: store.backupsURL,
                writeFile: { data, url in
                    if url == libraryURL { throw CocoaError(.fileWriteNoPermission) }
                    try data.write(to: url, options: .atomic)
                })
            let incoming = try ConfigurationArchive(configuration: CubeConfiguration(), contentLibrary: SnippetLibrary())
            #expect(throws: (any Error).self) { try failing.restore(incoming) }
            #expect(!FileManager.default.fileExists(atPath: store.configurationURL.path))
            #expect(!FileManager.default.fileExists(atPath: store.contentLibraryURL.path))
            #expect(try store.backups().count == 1)
        }
    }

    @Test func failedSecondWriteRestoresExactOriginalBytes() throws {
        try withTemporaryStore { store in
            try ConfigurationStore(url: store.configurationURL).save(CubeConfiguration())
            let library = SnippetLibrary(items: [TextSnippet(title: "重要", body: "不能丢失")])
            try SnippetStore(url: store.contentLibraryURL).save(library)
            let configurationBytes = try Data(contentsOf: store.configurationURL)
            let libraryBytes = try Data(contentsOf: store.contentLibraryURL)
            let libraryURL = store.contentLibraryURL
            let failing = ConfigurationArchiveStore(configurationURL: store.configurationURL,
                contentLibraryURL: libraryURL, backupsURL: store.backupsURL,
                writeFile: { data, url in
                    if url == libraryURL { throw CocoaError(.fileWriteNoPermission) }
                    try data.write(to: url, options: .atomic)
                })
            var next = CubeConfiguration()
            try next.rename(.front, to: "不应留下")
            let incoming = try ConfigurationArchive(configuration: next, contentLibrary: SnippetLibrary())
            #expect(throws: (any Error).self) { try failing.restore(incoming) }
            #expect(try Data(contentsOf: store.configurationURL) == configurationBytes)
            #expect(try Data(contentsOf: store.contentLibraryURL) == libraryBytes)
            #expect(try store.backups().count == 1)
        }
    }

    private func withTemporaryStore(_ body: (ConfigurationArchiveStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(ConfigurationArchiveStore(configurationURL: directory.appendingPathComponent("configuration.json"),
            contentLibraryURL: directory.appendingPathComponent("content-library.json"),
            backupsURL: directory.appendingPathComponent("Backups", isDirectory: true)))
    }
}
