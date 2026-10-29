import AppKit
import Combine
import CubeCore
import UniformTypeIdentifiers

extension Notification.Name {
    static let tCubeLibraryDidRestore = Notification.Name("TCubeLibraryDidRestore")
}

struct BrokenLauncher: Identifiable, Equatable {
    let face: CubeFace
    let slot: Int
    let item: LauncherItem
    let reason: String
    var id: String { "\(face.rawValue)-\(slot)-\(item.id)" }
}

@MainActor
enum BrokenLauncherScanner {
    static func scan(_ configuration: CubeConfiguration) -> [BrokenLauncher] {
        var issues: [BrokenLauncher] = []
        for face in CubeFace.allCases {
            for (slot, item) in configuration.group(for: face).slots.enumerated() {
                guard let item, item.kind.isLocal else { continue }
                do {
                    let url = try LauncherService.resolved(item)
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let actual = try LocalTarget.kind(at: url)
                    if actual != item.kind {
                        issues.append(BrokenLauncher(face: face, slot: slot, item: item,
                            reason: "目标类型已变化，请重新选择\(item.kind.title)。"))
                    }
                } catch {
                    issues.append(BrokenLauncher(face: face, slot: slot, item: item, reason: error.localizedDescription))
                }
            }
        }
        return issues
    }
}

struct PendingConfigurationImport: Identifiable {
    let url: URL
    let archive: ConfigurationArchive
    var id: URL { url }
}

@MainActor
final class ConfigurationMaintenance: ObservableObject {
    @Published private(set) var pendingImport: PendingConfigurationImport?
    @Published private(set) var backupFiles: [URL] = []
    @Published private(set) var brokenLaunchers: [BrokenLauncher] = []
    @Published private(set) var hasScanned = false
    @Published var status = "导出包含六面入口、外观设置和内容库的 JSON 备份。"
    @Published var error: String?

    private let model: AppModel
    let archiveStore: ConfigurationArchiveStore

    init(model: AppModel, archiveStore: ConfigurationArchiveStore? = nil) {
        self.model = model
        let configurationURL = model.configurationStoreURL
        self.archiveStore = archiveStore ?? ConfigurationArchiveStore(configurationURL: configurationURL,
            contentLibraryURL: configurationURL.deletingLastPathComponent().appendingPathComponent("content-library.json"))
        refreshBackups()
    }

    func refreshBackups() {
        do { backupFiles = try archiveStore.backups() }
        catch { self.error = error.localizedDescription }
    }

    func scanLaunchers() {
        brokenLaunchers = BrokenLauncherScanner.scan(model.configuration)
        hasScanned = true
        status = brokenLaunchers.isEmpty ? "本地入口检查完成，未发现失效目标。" : "发现 \(brokenLaunchers.count) 个需要重新选择的入口，原入口已保留。"
    }

    func prepareImport(from url: URL) {
        pendingImport = nil
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let archive = try ConfigurationArchive.decode(Data(contentsOf: url))
            // Damaged live data requires separate recovery; never silently replace it during import.
            _ = try archiveStore.currentArchive()
            pendingImport = PendingConfigurationImport(url: url, archive: archive)
            error = nil
        } catch { self.error = "无法导入：\(error.localizedDescription)" }
    }

    func cancelImport() { pendingImport = nil }

    @discardableResult
    func confirmImport() -> Bool {
        guard let pendingImport else { return false }
        do {
            let backup = try archiveStore.restore(pendingImport.archive)
            model.applyPersistedConfiguration(pendingImport.archive.configuration)
            NotificationCenter.default.post(name: .tCubeLibraryDidRestore, object: archiveStore.contentLibraryURL)
            self.pendingImport = nil
            error = nil
            refreshBackups()
            brokenLaunchers = BrokenLauncherScanner.scan(model.configuration)
            hasScanned = true
            status = "已恢复 \(pendingImport.archive.launcherCount) 个入口和 \(pendingImport.archive.contentCount) 条内容。原数据已备份为 \(backup.lastPathComponent)。"
            return true
        } catch {
            self.error = "恢复未完成：\(error.localizedDescription)"
            refreshBackups()
            return false
        }
    }

    func chooseImport() {
        let panel = NSOpenPanel()
        panel.title = "选择 T-Cube JSON 备份"
        panel.prompt = "预览导入"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { prepareImport(from: url) }
    }

    func exportCurrent() {
        let panel = NSSavePanel()
        panel.title = "导出 T-Cube 备份"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "T-Cube-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try archiveStore.export(to: url)
            error = nil
            status = "已导出到 \(url.path)。备份包含内容正文，请妥善保存。"
        } catch { self.error = "导出未完成：\(error.localizedDescription)" }
    }

    func createBackup() {
        do {
            let url = try archiveStore.makeBackup()
            refreshBackups()
            error = nil
            status = "已备份到 \(url.lastPathComponent)。"
        } catch { self.error = "备份未完成：\(error.localizedDescription)" }
    }

    func revealBackups() {
        do {
            try FileManager.default.createDirectory(at: archiveStore.backupsURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(archiveStore.backupsURL)
        } catch { self.error = error.localizedDescription }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func chooseReplacement(for issue: BrokenLauncher) {
        // A stale scan must never overwrite a slot edited elsewhere in settings.
        guard model.configuration.group(for: issue.face).slots[issue.slot]?.id == issue.item.id else {
            scanLaunchers()
            return
        }
        let panel = NSOpenPanel()
        panel.title = "重新选择「\(issue.item.name)」的目标"
        panel.prompt = "替换此入口"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let originalDisplayName = FileManager.default.displayName(atPath: issue.item.url.path)
        let customName = issue.item.name == originalDisplayName ? nil : issue.item.name
        model.add([url], to: issue.face, preferredSlot: issue.slot, replacing: true, preservingName: customName, expectedKind: issue.item.kind)
        scanLaunchers()
    }
}
