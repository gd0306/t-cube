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
            Section("桌面性能") {
                Toggle("静置时省电（推荐）", isOn: Binding(
                    get: { settings.idlePowerSavingEnabled }, set: { settings.setIdlePowerSaving($0) }
                ))
                Text("操作后保留静态画面并暂停实时绘制；鼠标移入立即恢复。开启时暂停持续的空闲旋转和流动光效。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("需要持续动态展示时可关闭此项。隐藏或完全遮挡后仍会暂停，未交互时以较低频率更新动画。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
