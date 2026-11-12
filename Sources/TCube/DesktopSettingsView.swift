import SwiftUI
import CubeCore

/// Every control on this page saves immediately. Appearance edits stay on their own page.
struct DesktopSettingsView: View {
    @ObservedObject var model: AppModel
    var desktop: DesktopAutoHideSettings?
    var performance: PerformanceSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("本页设置立即生效并保存。")
                .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.top, 16)
            Form {
                if let desktop { DesktopAutoHideSettingsView(settings: desktop) }
                Section {
                    HStack(spacing: 8) {
                        ForEach(CubePlacement.allCases) { placement in
                            Button(placement.title, systemImage: placement.symbol) {
                                model.onPlacementRequested?(placement)
                            }
                            .help("将立方体放到所在屏幕的\(placement.title)")
                        }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("快捷位置")
                } footer: {
                    Text("放到所在屏幕，避开菜单栏和 Dock。也可从状态栏菜单调整。")
                }
                if let performance { PerformanceSettingsSection(settings: performance) }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
