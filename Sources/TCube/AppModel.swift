import AppKit
import SwiftUI
import CubeCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var configuration = CubeConfiguration()
    @Published private(set) var activeTheme: CubeThemePreset?
    @Published var selectedFace: CubeFace = .front
    var onChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var onPlacementRequested: ((CubePlacement) -> Void)?
    var onConfigurationRestored: (() -> Void)?
    private let store: ConfigurationStore
    private var applyingPersistedConfiguration = false
    private var themeCycleTask: Task<Void, Never>?
    let isFirstLaunch: Bool
    private(set) var loadFailure: Error?

    var displayedAppearance: CubeAppearance {
        activeTheme?.appearance(glowIntensity: configuration.appearance.glowIntensity,
                                material: configuration.appearance.material) ?? configuration.appearance
    }

    init(store: ConfigurationStore = ConfigurationStore(url: ConfigurationStore.defaultURL)) {
        self.store = store
        isFirstLaunch = !FileManager.default.fileExists(atPath: store.url.path)
        do { configuration = try store.load() }
        catch { loadFailure = error }
        restartThemeCycle()
    }

    deinit { themeCycleTask?.cancel() }

    func advanceTheme() {
        guard let next = configuration.themeCycle.next(after: activeTheme), next != activeTheme else { return }
        activeTheme = next
        onAppearanceChange?()
    }

    func stopThemeCycle() {
        themeCycleTask?.cancel()
        themeCycleTask = nil
    }

    private func restartThemeCycle() {
        stopThemeCycle()
        activeTheme = configuration.themeCycle.next(after: nil)
        onAppearanceChange?()
        guard configuration.themeCycle.isEnabled else { return }
        let interval = configuration.themeCycle.intervalSeconds
        themeCycleTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.advanceTheme()
            }
        }
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

    var configurationStoreURL: URL { store.url }

    func applyPersistedConfiguration(_ configuration: CubeConfiguration) {
        applyingPersistedConfiguration = true
        defer { applyingPersistedConfiguration = false }
        self.configuration = configuration
        loadFailure = nil
        restartThemeCycle()
        onChange?()
        onConfigurationRestored?()
    }

    func change(_ edit: (inout CubeConfiguration) throws -> Void) {
        do {
            var candidate = configuration
            try edit(&candidate)
            try store.save(candidate)
            let cycleChanged = candidate.themeCycle != configuration.themeCycle
            configuration = candidate
            if cycleChanged { restartThemeCycle() }
            onChange?()
        } catch { report(error) }
    }

    func savePosition(_ point: NSPoint) {
        guard !applyingPersistedConfiguration else { return }
        // Position changes do not require regenerating six face textures.
        do {
            var candidate = configuration
            candidate.windowPosition = WindowPosition(x: point.x, y: point.y)
            try store.save(candidate)
            configuration = candidate
        } catch { report(error) }
    }

    func add(_ urls: [URL], to face: CubeFace, preferredSlot: Int? = nil, replacing: Bool = false, preservingName: String? = nil, expectedKind: LauncherItem.Kind? = nil) {
        var candidate = configuration
        var failures: [String] = []
        var added = false
        for url in urls {
            do {
                var item = try LauncherService.item(for: url, expectedKind: expectedKind)
                if let preservingName { item.name = preservingName }
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

    func add(_ item: LauncherItem, to face: CubeFace, preferredSlot: Int? = nil, replacing: Bool = false) {
        change {
            if let preferredSlot { try $0.place(item, to: face, slot: preferredSlot, replacing: replacing) }
            else { try $0.add(item, to: face) }
        }
    }

    func choose(for face: CubeFace, slot: Int? = nil, replacing: Bool = false) {
        let current = slot.flatMap { configuration.group(for: face).slots[$0] }
        guard let kind = LauncherTargetPicker.chooseKind(replacing: replacing, current: current?.kind) else { return }
        if !kind.isLocal {
            let item = kind == .website ? LauncherTargetPicker.website(current: current) : LauncherTargetPicker.settings(current: current)
            if let item { add(item, to: face, preferredSlot: slot, replacing: replacing) }
            return
        }
        let picker = NSOpenPanel()
        picker.title = "选择" + kind.title
        picker.prompt = replacing ? "替换" : "添加"
        picker.canChooseFiles = kind != .folder
        picker.canChooseDirectories = kind == .folder
        picker.treatsFilePackagesAsDirectories = false
        picker.allowsMultipleSelection = slot == nil
        picker.directoryURL = kind == .application ? URL(fileURLWithPath: "/Applications", isDirectory: true) : nil
        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK {
            add(picker.urls, to: face, preferredSlot: slot, replacing: replacing, expectedKind: kind)
        }
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
    static func item(for url: URL, expectedKind: LauncherItem.Kind? = nil) throws -> LauncherItem {
        guard url.isFileURL else { throw LocalTargetError.unsupported }
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let kind = try LocalTarget.kind(at: canonical)
        if let expectedKind, kind != expectedKind { throw LocalTargetError.unsupported }
        let bookmark = try canonical.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        return LauncherItem(url: canonical, name: FileManager.default.displayName(atPath: canonical.path), kind: kind, bookmark: bookmark)
    }

    static func resolved(_ item: LauncherItem) throws -> URL {
        guard item.kind.isLocal, let bookmark = item.bookmark else { return item.url }
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func open(_ item: LauncherItem,
                     openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) },
                     failure: @escaping @MainActor (Error) -> Void) throws {
        try item.validate()
        guard item.kind.isLocal else {
            guard openURL(item.url) else { throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "无法打开此入口，请检查默认浏览器或系统设置。"]) }
            return
        }
        let url = try resolved(item)
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            guard try LocalTarget.kind(at: url) == item.kind else { throw LocalTargetError.unsupported }
        }
        catch { if scoped { url.stopAccessingSecurityScopedResource() }; throw error }
        if item.kind == .application {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if scoped { url.stopAccessingSecurityScopedResource() }
                if let error { Task { @MainActor in failure(error) } }
            }
        } else {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard openURL(url) else { throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "无法打开此文件或文件夹，请检查默认应用或重新选择入口。"] ) }
        }
    }

    static func icon(for item: LauncherItem) -> NSImage {
        if !item.kind.isLocal {
            let symbol = item.kind == .website ? "globe" :
                (SystemSettingsTarget.allCases.first { $0.url == item.url }?.symbol ?? "gearshape.fill")
            let configuration = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
                .applying(.init(paletteColors: [.systemBlue]))
            return NSImage(systemSymbolName: symbol, accessibilityDescription: item.name)?
                .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 48, height: 48))
        }
        return NSWorkspace.shared.icon(forFile: (try? resolved(item).path) ?? item.url.path)
    }
}
