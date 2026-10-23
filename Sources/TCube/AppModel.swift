import AppKit
import SwiftUI
import CubeCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var configuration = CubeConfiguration()
    @Published var selectedFace: CubeFace = .front
    var onChange: (() -> Void)?
    private let store: ConfigurationStore
    let isFirstLaunch: Bool
    private(set) var loadFailure: Error?

    init(store: ConfigurationStore = ConfigurationStore(url: ConfigurationStore.defaultURL)) {
        self.store = store
        isFirstLaunch = !FileManager.default.fileExists(atPath: store.url.path)
        do { configuration = try store.load() }
        catch { loadFailure = error }
    }

    func recoverIfNeeded() {
        guard let error = loadFailure else { return }
        let alert = NSAlert()
        alert.messageText = "无法读取 T-Cube 配置"
        alert.informativeText = "原文件已保留。可以将它备份后新建空配置，也可以退出并手动检查。\n\n\(store.url.path)\n\(error.localizedDescription)"
        alert.addButton(withTitle: "备份并新建")
        alert.addButton(withTitle: "退出")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
        do {
            let backup = store.url.deletingLastPathComponent().appendingPathComponent("configuration-preserved-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: store.url, to: backup)
            try store.save(configuration)
            loadFailure = nil
            message("已保留原配置", detail: "备份位于：\n\(backup.path)")
        } catch { report(error); NSApp.terminate(nil) }
    }

    func change(_ edit: (inout CubeConfiguration) throws -> Void) {
        do {
            var candidate = configuration
            try edit(&candidate)
            try store.save(candidate)
            configuration = candidate
            onChange?()
        } catch { report(error) }
    }

    func savePosition(_ point: NSPoint) {
        // Position changes do not require regenerating six face textures.
        do {
            var candidate = configuration
            candidate.windowPosition = WindowPosition(x: point.x, y: point.y)
            try store.save(candidate)
            configuration = candidate
        } catch { report(error) }
    }

    func add(_ urls: [URL], to face: CubeFace, preferredSlot: Int? = nil, replacing: Bool = false) {
        var candidate = configuration
        var failures: [String] = []
        var added = false
        for url in urls {
            do {
                let item = try LauncherService.item(for: url)
                var next = candidate
                if let preferredSlot {
                    try next.place(item, to: face, slot: preferredSlot, replacing: replacing)
                } else {
                    try next.add(item, to: face)
                }
                candidate = next
                added = true
            } catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        if added { change { $0 = candidate } }
        if !failures.isEmpty { message("部分入口未能添加", detail: failures.joined(separator: "\n")) }
    }

    func choose(for face: CubeFace, slot: Int? = nil, replacing: Bool = false) {
        let picker = NSOpenPanel()
        picker.title = replacing ? "重新选择入口" : "添加应用或文件夹"
        picker.prompt = "添加"
        picker.canChooseFiles = true
        picker.canChooseDirectories = true
        picker.treatsFilePackagesAsDirectories = false
        picker.allowsMultipleSelection = slot == nil
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK { add(picker.urls, to: face, preferredSlot: slot, replacing: replacing) }
    }

    func launch(slot: Int, face: CubeFace) {
        guard let item = configuration.group(for: face).slots[slot] else { choose(for: face, slot: slot); return }
        do { try LauncherService.open(item) { [weak self] error in self?.report(error) } }
        catch { report(error) }
    }

    func report(_ error: Error) { message("操作未完成", detail: error.localizedDescription) }
    func message(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
enum LauncherService {
    static func item(for url: URL) throws -> LauncherItem {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let kind = try LocalTarget.kind(at: canonical)
        let bookmark = try canonical.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        return LauncherItem(url: canonical, name: FileManager.default.displayName(atPath: canonical.path), kind: kind, bookmark: bookmark)
    }

    static func resolved(_ item: LauncherItem) throws -> URL {
        guard let bookmark = item.bookmark else { return item.url }
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func open(_ item: LauncherItem, failure: @escaping @MainActor (Error) -> Void) throws {
        let url = try resolved(item)
        let scoped = url.startAccessingSecurityScopedResource()
        do { _ = try LocalTarget.kind(at: url) }
        catch { if scoped { url.stopAccessingSecurityScopedResource() }; throw error }
        if item.kind == .application {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if scoped { url.stopAccessingSecurityScopedResource() }
                if let error { Task { @MainActor in failure(error) } }
            }
        } else {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard NSWorkspace.shared.open(url) else { throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Finder 无法打开此文件夹，请重新选择入口。"] ) }
        }
    }

    static func icon(for item: LauncherItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: (try? resolved(item).path) ?? item.url.path)
    }
}
