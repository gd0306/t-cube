import AppKit
import Combine
import SwiftUI

@MainActor
final class PerformanceSettings: ObservableObject {
    private static let key = "TCube.idlePowerSaving"
    @Published private(set) var idlePowerSavingEnabled: Bool
    private let defaults: UserDefaults
    var onChange: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        idlePowerSavingEnabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func setIdlePowerSaving(_ enabled: Bool) {
        idlePowerSavingEnabled = enabled
        defaults.set(enabled, forKey: Self.key)
        onChange?(enabled)
    }
}

struct PerformanceSettingsView: View {
    @ObservedObject var settings: PerformanceSettings

    var body: some View {
        Form {
            PerformanceSettingsSection(settings: settings)
        }.formStyle(.grouped)
    }
}

struct PerformanceSettingsSection: View {
    @ObservedObject var settings: PerformanceSettings

    var body: some View {
        Section("桌面性能") {
            Toggle("静置时省电（推荐）", isOn: Binding(
                get: { settings.idlePowerSavingEnabled }, set: { settings.setIdlePowerSaving($0) }
            ))
            Text("空闲时暂停绘制、旋转和流光，鼠标移入后恢复。")
                .font(.callout).foregroundStyle(.secondary)
            Text("关闭后保留空闲动态效果；隐藏或完全遮挡时仍会暂停。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
