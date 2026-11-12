import AppKit
import SwiftUI
import CubeCore

struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var lastSavedValues: AppearanceSettingsValues?
    @State private var showsCustomAppearance = false
    @State private var showsThemeCycle = false
    @State private var showsInteraction = false
    @State private var showsInstructions = false
    @State private var primary = Color.cyan
    @State private var secondary = Color.purple
    @State private var glowIntensity = 0.55
    @State private var surfaceStyle: CubeSurfaceStyle = .clear
    @State private var material: CubeMaterial = .glass
    @State private var scale = 1.0
    @State private var cycleEnabled = false
    @State private var cycleThemes: [CubeThemePreset] = [.aurora, .ocean, .sunset]
    @State private var cycleInterval = 10
    @State private var hoverEnabled = true
    @State private var hoverMultiplier = 4.0
    @State private var hoverDelay = 0.18
    @State private var expandsFacesOnClick = true
    @State private var autoRotatesWhenIdle = true

    private var stagedAppearance: CubeAppearance {
        CubeAppearance(primaryHex: NSColor(primary).hexRGB,
                       secondaryHex: NSColor(secondary).hexRGB,
                       glowIntensity: glowIntensity, surfaceStyle: surfaceStyle, material: material)
    }

    private var selectedPreset: String {
        let appearance = stagedAppearance
        return CubeThemePreset.allCases.first {
            $0.primaryHex.caseInsensitiveCompare(appearance.primaryHex) == .orderedSame &&
            $0.secondaryHex.caseInsensitiveCompare(appearance.secondaryHex) == .orderedSame && $0.surfaceStyle == appearance.surfaceStyle
        }?.id ?? "custom"
    }

    private var stagedCycle: CubeThemeCycle {
        CubeThemeCycle(isEnabled: cycleEnabled, themes: cycleThemes, intervalSeconds: cycleInterval)
    }

    private var stagedHover: CubeHoverSettings {
        CubeHoverSettings(isEnabled: hoverEnabled, multiplier: hoverMultiplier, delaySeconds: hoverDelay)
    }

    private var values: AppearanceSettingsValues {
        AppearanceSettingsValues(appearance: stagedAppearance, scale: scale, themeID: selectedPreset,
                                 cycle: stagedCycle, hover: stagedHover,
                                 expandsFacesOnClick: expandsFacesOnClick,
                                 autoRotatesWhenIdle: autoRotatesWhenIdle)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("材质", selection: $material) {
                        ForEach(CubeMaterial.allCases) { material in Text(material.name).tag(material) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("立方体材质")
                } footer: {
                    Text(material == .slime ? "鼠标划过时牵引表面，移开后弹性回弹。" : "通透玻璃材质，保留桌面背景。")
                }
                Section {
                    LabeledContent("主题预设") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(CubeThemePreset.allCases) { preset in presetButton(preset) }
                        }
                        .frame(width: 330)
                    }
                    .disabled(cycleEnabled)
                    DisclosureGroup("自定义颜色与光效", isExpanded: $showsCustomAppearance) {
                        Picker("光效样式", selection: $surfaceStyle) {
                            ForEach(CubeSurfaceStyle.allCases) { style in Text(style.name).tag(style) }
                        }
                        .disabled(cycleEnabled)
                        ColorPicker("主色", selection: $primary, supportsOpacity: false)
                            .disabled(cycleEnabled)
                        ColorPicker("辅助色", selection: $secondary, supportsOpacity: false)
                            .disabled(cycleEnabled)
                        LabeledContent("光晕强度") {
                            HStack(spacing: 12) {
                                Slider(value: $glowIntensity, in: 0...1)
                                    .accessibilityLabel("光晕强度")
                                Text(glowIntensity, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                            }.frame(width: 270)
                        }
                    }
                } header: {
                    Text("主题")
                } footer: {
                    Text(cycleEnabled ? "主题轮换已开启；关闭后可选择固定主题。" : "所有主题均可搭配玻璃或史莱姆材质。")
                }
                Section("立方体尺寸") {
                    LabeledContent("静置大小") {
                        HStack(spacing: 12) {
                            Slider(value: $scale, in: CubeConfiguration.scaleRange, step: 0.05)
                                .accessibilityLabel("立方体静置大小")
                            Text(scale, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        }.frame(width: 270)
                    }
                }
                Section {
                    DisclosureGroup(cycleEnabled ? "主题轮换 · 已开启" : "主题轮换", isExpanded: $showsThemeCycle) {
                        Toggle("自动轮换主题", isOn: $cycleEnabled)
                            .disabled(!cycleEnabled && cycleThemes.count < 2)
                        if model.configuration.themeCycle.isEnabled, let activeTheme = model.activeTheme {
                            LabeledContent("当前主题", value: activeTheme.name)
                        }
                        LabeledContent("参与轮换") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
                                ForEach(CubeThemePreset.allCases) { preset in
                                    Toggle(preset.name, isOn: themeSelection(preset))
                                        .toggleStyle(.checkbox)
                                }
                            }
                            .frame(width: 330)
                        }
                        Picker("轮换间隔", selection: $cycleInterval) {
                            Text("10 秒").tag(10)
                            Text("20 秒").tag(20)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!cycleEnabled)

                        Text("按勾选顺序轮换，修改后立即从第一种主题开始。开启时至少保留两种主题。")
                            .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                    }
                    if cycleThemes.count < 2 {
                        Label("请至少选择两种轮换主题。", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    DisclosureGroup("交互与动画", isExpanded: $showsInteraction) {
                        Toggle("鼠标移入时自动放大", isOn: $hoverEnabled)
                        LabeledContent("放大倍率") {
                            HStack(spacing: 12) {
                                Slider(value: $hoverMultiplier, in: 1.1...4, step: 0.1)
                                    .accessibilityLabel("悬停放大倍率")
                                Text("\(hoverMultiplier, specifier: "%.1f")×")
                                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                            }.frame(width: 270)
                        }
                        .disabled(!hoverEnabled)

                        HStack {
                            Text("悬停延迟")
                            Slider(value: $hoverDelay, in: 0...1.5, step: 0.05)
                                .accessibilityLabel("悬停放大延迟")
                            Text(String(format: "%.2f 秒", hoverDelay)).monospacedDigit().frame(width: 65)
                        }
                        Text("移出立即收起；拖动与 Ctrl 操作保持即时响应。")
                            .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                        Toggle("空闲时自动旋转", isOn: $autoRotatesWhenIdle)
                        Text("静置省电或系统减少动态效果开启时，空闲动画暂停。")
                            .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                        Toggle("点击面展开放大", isOn: $expandsFacesOnClick)
                        Text(expandsFacesOnClick ? "先展开该面的四个图标，再点击入口打开。" : "直接点击面上的图标打开。")
                            .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                    }
                }
                Section {
                    DisclosureGroup("操作说明", isExpanded: $showsInstructions) {
                        Label("左键按住拖动调整位置；右键按住拖动旋转立方体", systemImage: "cursorarrow.motionlines")
                        Label("立方体内按住 Ctrl 还原；Ctrl＋左键拖动\n移出立方体后长按 Ctrl 1 秒唤起剪贴板", systemImage: "control")
                        Label(expandsFacesOnClick ? "单击面立即展开；右键单击或从状态栏打开设置" : "单击图标直接打开；右键单击或从状态栏打开设置", systemImage: "square.on.square")
                        Label("触控板横向或纵向滚动，沿对应方向旋转", systemImage: "hand.draw")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Text("修改后立即生效并保存。")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认外观") {
                    let defaults = CubeConfiguration()
                    model.change { AppearanceSettingsValues(configuration: defaults).apply(to: &$0) }
                    loadAppearance(from: model.configuration)
                    lastSavedValues = values
                }
                    .help("恢复本页默认值，保留入口、内容库与其他设置")
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .onAppear {
            loadAppearance(from: model.configuration)
            lastSavedValues = values
        }
        .onChange(of: values) { _, updated in
            guard let lastSavedValues, updated != lastSavedValues else { return }
            model.change { updated.apply(to: &$0) }
            self.lastSavedValues = updated
        }
        .onChange(of: AppearanceSettingsValues(configuration: model.configuration)) { _, _ in
            loadAppearance(from: model.configuration)
            lastSavedValues = values
        }
    }

    private func presetButton(_ preset: CubeThemePreset) -> some View {
        Button {
            primary = Color(nsColor: NSColor(hexRGB: preset.primaryHex) ?? .cyan)
            secondary = Color(nsColor: NSColor(hexRGB: preset.secondaryHex) ?? .purple)
            surfaceStyle = preset.surfaceStyle
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: [
                        Color(nsColor: NSColor(hexRGB: preset.primaryHex) ?? .cyan),
                        Color(nsColor: NSColor(hexRGB: preset.secondaryHex) ?? .purple)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 13, height: 13)
                Text(preset.name).lineLimit(1).minimumScaleFactor(0.85)
                if selectedPreset == preset.id { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
            }
        }
        .buttonStyle(.bordered)
        .accessibilityAddTraits(selectedPreset == preset.id ? .isSelected : [])
    }

    private func themeSelection(_ preset: CubeThemePreset) -> Binding<Bool> {
        Binding {
            cycleThemes.contains(preset)
        } set: { selected in
            if selected {
                if !cycleThemes.contains(preset) { cycleThemes.append(preset) }
            } else {
                guard !cycleEnabled || cycleThemes.count > 2 else { return }
                cycleThemes.removeAll { $0 == preset }
            }
        }
    }

    private func loadAppearance(from configuration: CubeConfiguration) {
        let appearance = configuration.appearance
        primary = Color(nsColor: NSColor(hexRGB: appearance.primaryHex) ?? .cyan)
        secondary = Color(nsColor: NSColor(hexRGB: appearance.secondaryHex) ?? .purple)
        glowIntensity = appearance.glowIntensity
        surfaceStyle = appearance.surfaceStyle
        material = appearance.material
        scale = configuration.scale
        cycleEnabled = configuration.themeCycle.isEnabled
        cycleThemes = configuration.themeCycle.themes
        cycleInterval = configuration.themeCycle.intervalSeconds
        hoverEnabled = configuration.hover.isEnabled
        hoverMultiplier = configuration.hover.multiplier
        hoverDelay = configuration.hover.delaySeconds
        expandsFacesOnClick = configuration.expandsFacesOnClick
        autoRotatesWhenIdle = configuration.autoRotatesWhenIdle
    }

}
