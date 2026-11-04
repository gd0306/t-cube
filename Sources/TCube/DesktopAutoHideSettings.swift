import Combine
import Foundation
import SwiftUI

@MainActor
final class DesktopAutoHideSettings: ObservableObject {
    @Published private(set) var edgeCollapseEnabled: Bool
    @Published private(set) var hideInFullscreen: Bool
    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edgeCollapseEnabled = defaults.object(forKey: "TCube.edgeCollapse") as? Bool ?? false
        hideInFullscreen = defaults.object(forKey: "TCube.hideInFullscreen") as? Bool ?? false
    }

    func setEdgeCollapse(_ enabled: Bool) {
        edgeCollapseEnabled = enabled
        defaults.set(enabled, forKey: "TCube.edgeCollapse")
        onChange?()
    }

    func setHideInFullscreen(_ enabled: Bool) {
        hideInFullscreen = enabled
        defaults.set(enabled, forKey: "TCube.hideInFullscreen")
        onChange?()
    }
}

struct DesktopAutoHideSettingsView: View {
    @ObservedObject var settings: DesktopAutoHideSettings
    var body: some View {
        Section("自动收起") {
            Toggle("贴近屏幕左右边缘时收起", isOn: Binding(
                get: { settings.edgeCollapseEnabled }, set: settings.setEdgeCollapse))
            Toggle("全屏应用中自动隐藏", isOn: Binding(
                get: { settings.hideInFullscreen }, set: settings.setHideInFullscreen))
            Text("移出约 0.8 秒后收为窄条，靠近即可展开。全屏隐藏仅影响所在屏幕；手动隐藏后需手动显示。")
                .font(InterfaceTypography.detail).foregroundStyle(.secondary)
        }
    }
}
