import SwiftUI

struct LifecycleSettingsView: View {
    @ObservedObject var controller: LifecycleController

    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动 T-Cube", isOn: Binding(
                    get: { controller.loginEnabled },
                    set: { controller.setLoginEnabled($0) }
                ))
                Text(controller.loginStatusDescription)
                    .font(.callout).foregroundStyle(.secondary)
                if let error = controller.loginError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                Button("打开系统登录项设置…") { controller.openLoginSettings() }
            }
            if !controller.updatesAvailable {
                ReleaseReminderSettingsView(model: controller.reminder, check: controller.checkForUpdates, openReleases: controller.openReleases)
            } else {
                Section("软件更新") {
                    Toggle("自动检查新版本", isOn: Binding(
                        get: { controller.automaticallyChecksForUpdates },
                        set: { controller.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .disabled(!controller.updatesAvailable)
                    Text("新版本安装前会显示提示，并验证更新包签名。")
                        .font(.callout).foregroundStyle(.secondary)
                    if let issue = controller.updateIssue {
                        Text(issue).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    HStack {
                        Button("检查更新…") { controller.checkForUpdates() }
                            .disabled(!controller.canCheckForUpdates)
                        Button("查看发布页面…") { controller.openReleases() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { controller.start() }
    }
}

private struct ReleaseReminderSettingsView: View {
    @ObservedObject var model: ReleaseReminderModel
    let check: () -> Void
    let openReleases: () -> Void

    var body: some View {
        Section("版本提醒") {
            Toggle("自动检查新版本（仅提醒）", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                .disabled(!model.preferencesHealthy)
            Text("开启后每 6 小时检查 GitHub Releases，发现新版本时显示一次提醒。请从发布页手动下载安装。")
                .font(.callout).foregroundStyle(.secondary)
            Text("当前版本 \(model.currentVersion)").font(.callout)
            if let release = model.availableRelease {
                Text("可用版本 \(release.version)").font(.headline)
            }
            Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if let date = model.lastChecked {
                Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(model.isChecking ? "正在检查…" : "检查新版本…", action: check)
                    .disabled(model.isChecking || !model.preferencesHealthy)
                Button("查看发布页面…", action: openReleases)
            }
        }
    }
}
