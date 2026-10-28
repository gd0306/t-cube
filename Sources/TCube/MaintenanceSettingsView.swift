import SwiftUI
import CubeCore

struct MaintenanceSettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var maintenance: ConfigurationMaintenance

    init(model: AppModel) {
        self.model = model
        _maintenance = StateObject(wrappedValue: ConfigurationMaintenance(model: model))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("备份与修复").font(.title2.weight(.semibold))
                    Text("保存入口与内容，重新连接已移动的应用或文件夹。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("备份包含全部入口、外观和内容库。导入会替换当前数据，并先自动备份。")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("导出备份…", systemImage: "square.and.arrow.up") { maintenance.exportCurrent() }
                            Button("导入 / 从文件恢复…", systemImage: "square.and.arrow.down") { maintenance.chooseImport() }
                        }
                        Text("备份包含内容正文和本地路径，请只导入可信的 T-Cube 备份。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                } label: { Label("导入与导出", systemImage: "externaldrive") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(maintenance.backupFiles.count) 份本地备份").font(.callout.weight(.medium))
                            Spacer()
                            Button("立即备份") { maintenance.createBackup() }
                            Button("显示备份文件夹") { maintenance.revealBackups() }
                        }
                        if maintenance.backupFiles.isEmpty {
                            Text("导入前的自动备份和手动备份会保存在这里。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(maintenance.backupFiles.prefix(5)), id: \.self) { url in
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 4)
                                    Button("显示") { maintenance.reveal(url) }
                                    Button("恢复…") { maintenance.prepareImport(from: url) }
                                }
                            }
                            if maintenance.backupFiles.count > 5 {
                                Text("最近 5 份显示在此处，更多备份请打开文件夹。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                } label: { Label("自动与手动备份", systemImage: "clock.arrow.circlepath") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("检查六个面的应用和文件夹入口。")
                            Spacer()
                            Button("重新检查", systemImage: "arrow.clockwise") { maintenance.scanLaunchers() }
                        }
                        if maintenance.hasScanned && maintenance.brokenLaunchers.isEmpty {
                            Label("所有入口均可访问", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                        }
                        ForEach(maintenance.brokenLaunchers) { issue in
                            Divider()
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(model.configuration.group(for: issue.face).name) · \(faceName(issue.face)) · 位置 \(issue.slot + 1) · \(issue.item.name)")
                                        .font(.callout.weight(.medium))
                                    Text(issue.reason).font(.caption).foregroundStyle(.secondary)
                                    Text(issue.item.url.path).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle).help(issue.item.url.path)
                                }
                                Spacer(minLength: 8)
                                Button("重新选择…") { maintenance.chooseReplacement(for: issue) }
                            }
                        }
                        Text("修复只替换你选择的位置，保留自定义名称。不会自动删除失效入口。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                } label: { Label("失效入口", systemImage: "link") }
                if let error = maintenance.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red).font(.callout).textSelection(.enabled)
                }
                Text(maintenance.status).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }
        .onAppear { maintenance.refreshBackups(); maintenance.scanLaunchers() }
        .sheet(isPresented: Binding(get: { maintenance.pendingImport != nil },
                                    set: { if !$0 { maintenance.cancelImport() } })) {
            if let pending = maintenance.pendingImport { importPreview(pending) }
        }
    }

    private func importPreview(_ pending: PendingConfigurationImport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认恢复备份").font(.title2.weight(.semibold))
            Text(pending.url.lastPathComponent).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            LabeledContent("备份时间", value: pending.archive.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("入口", value: "\(pending.archive.launcherCount) 个 / 六个面")
            LabeledContent("内容库", value: "\(pending.archive.contentCount) 条")
            Text(CubeFace.allCases.map { pending.archive.configuration.group(for: $0).name }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text("当前入口、外观设置和内容库将全部替换。恢复前会自动保存当前数据的备份；目标路径在此 Mac 上可能需要重新选择。")
                .fixedSize(horizontal: false, vertical: true)
            if let error = maintenance.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { maintenance.cancelImport() }.keyboardShortcut(.cancelAction)
                Button("备份当前数据并恢复", role: .destructive) { maintenance.confirmImport() }
            }
        }.padding(24).frame(width: 460)
    }

    private func faceName(_ face: CubeFace) -> String {
        switch face {
        case .front: "正面"
        case .right: "右面"
        case .back: "背面"
        case .left: "左面"
        case .top: "顶面"
        case .bottom: "底面"
        }
    }
}
