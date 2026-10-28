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
        .formStyle(.grouped)
        .onAppear { controller.start() }
    }
}
