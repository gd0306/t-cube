import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ShortcutLauncherTests {
    private func fileIdentity(_ url: URL) throws -> UInt64 {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? UInt64)
    }

    @Test func fileSelectionCreatesBookmarkAndOpensThroughDefaultHandler() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let selectedFile = directory.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: selectedFile)
        let file = selectedFile.resolvingSymlinksInPath()
        let item = try LauncherService.item(for: file)
        #expect(item.kind == .file)
        #expect(item.bookmark != nil)
        #expect(try fileIdentity(LauncherService.resolved(item)) == fileIdentity(file))
        var opened: [URL] = []
        try LauncherService.open(item, openURL: { opened.append($0); return true }, failure: { _ in Issue.record("unexpected launch failure") })
        #expect(opened.count == 1)
        #expect(try fileIdentity(#require(opened.first)) == fileIdentity(file))
    }

    @Test func remoteTargetsIgnoreBookmarksAndOpenValidatedURLsWithoutFileChecks() throws {
        let targets = [try WebsiteTarget.item(title: "网站", address: "https://example.com/path"), SystemSettingsTarget.wifi.item]
        var configuration = CubeConfiguration()
        var opened: [URL] = []
        for var item in targets {
            item.bookmark = Data("irrelevant bookmark".utf8)
            try configuration.add(item, to: .front)
            try LauncherService.open(item, openURL: { opened.append($0); return true }, failure: { _ in Issue.record("unexpected launch failure") })
            #expect(LauncherService.icon(for: item).isValid)
        }
        #expect(opened == targets.map(\.url))
        #expect(BrokenLauncherScanner.scan(configuration).isEmpty)
    }

    @Test func typedLocalSelectionRejectsChangingTheKindOfARepairTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: file)
        #expect(try LauncherService.item(for: file, expectedKind: .file).kind == .file)
        #expect(throws: LocalTargetError.self) { try LauncherService.item(for: directory, expectedKind: .file) }
        #expect(throws: LocalTargetError.self) { try LauncherService.item(for: file, expectedKind: .folder) }
        #expect(throws: LocalTargetError.self) { try LauncherService.item(for: file, expectedKind: .application) }
    }

    @Test func missingFilesAreReportedWithoutFlaggingRemoteTargets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: file)
        var configuration = CubeConfiguration()
        let item = try LauncherService.item(for: file)
        try configuration.add(item, to: .front)
        try configuration.add(WebsiteTarget.item(title: "网站", address: "https://example.com"), to: .front)
        try configuration.add(SystemSettingsTarget.displays.item, to: .front)
        #expect(BrokenLauncherScanner.scan(configuration).isEmpty)
        try FileManager.default.removeItem(at: file)
        let issues = BrokenLauncherScanner.scan(configuration)
        #expect(issues.count == 1)
        #expect(issues.first?.item == item)
        #expect(configuration.group(for: .front).slots[0] == item)
    }

    @Test func invalidOrChangedTargetsNeverReachDefaultHandlerAndFailureIsReported() throws {
        var opened = 0
        let bad = LauncherItem(url: URL(string: "javascript:alert(1)")!, name: "bad", kind: .website)
        #expect(throws: ConfigurationError.invalidItem) {
            try LauncherService.open(bad, openURL: { _ in opened += 1; return true }, failure: { _ in })
        }
        let wrongKind = LauncherItem(url: FileManager.default.temporaryDirectory, name: "changed", kind: .file)
        #expect(throws: LocalTargetError.self) {
            try LauncherService.open(wrongKind, openURL: { _ in opened += 1; return true }, failure: { _ in })
        }
        #expect(opened == 0)
        #expect(throws: (any Error).self) {
            try LauncherService.open(SystemSettingsTarget.sound.item, openURL: { _ in false }, failure: { _ in })
        }
    }

    @Test func addAndReplaceRemoteTargetsPersistExactSlotAndPreserveOtherEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        let website = try WebsiteTarget.item(title: "文档", address: "https://example.com/docs")
        let settings = SystemSettingsTarget.keyboard.item
        model.add(website, to: .front, preferredSlot: 2)
        model.add(settings, to: .front, preferredSlot: 0)
        #expect(model.configuration.group(for: .front).slots == [settings, nil, website, nil])
        let replacement = SystemSettingsTarget.privacy.item
        model.add(replacement, to: .front, preferredSlot: 2, replacing: true)
        #expect(model.configuration.group(for: .front).slots == [settings, nil, replacement, nil])
        #expect(try store.load() == model.configuration)
    }

    @Test func catalogPagesHaveInstalledSettingsHandlersAndIcons() throws {
        for target in SystemSettingsTarget.allCases {
            #expect(NSWorkspace.shared.urlForApplication(toOpen: target.url) != nil)
            #expect(LauncherService.icon(for: target.item).isValid)
        }
    }

    @Test func websiteEntryRequiresTitleAndTrimsAddress() throws {
        let item = try WebsiteTarget.item(title: "  文档  ", address: "  https://example.com/docs\n")
        #expect(item.name == "文档")
        #expect(item.url.absoluteString == "https://example.com/docs")
        #expect(throws: ConfigurationError.invalidName) { try WebsiteTarget.item(title: "  ", address: "https://example.com") }
    }
}
