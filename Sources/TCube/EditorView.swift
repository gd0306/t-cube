import AppKit
import SwiftUI
import CubeCore

struct EditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                FaceSettingsView(model: model)
                    .tabItem { Label("立方体入口", systemImage: "cube") }
                AppearanceSettingsView(model: model)
                    .tabItem { Label("外观", systemImage: "paintpalette") }
            }
            .padding(16)
            Divider()
            HStack {
                Text("按住立方体拖动位置 · 单击面展开入口")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出 T-Cube", systemImage: "power") { NSApp.terminate(nil) }
                    .help("退出应用并移除悬浮立方体")
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(minWidth: 760, idealWidth: 800, minHeight: 520, idealHeight: 580)
    }
}

private struct FaceSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var title = ""
    private var face: CubeFace { model.selectedFace }
    private var group: FaceGroup { model.configuration.group(for: face) }

    var body: some View {
        HStack(spacing: 0) {
            faceList
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        TextField("分组名称", text: $title)
                            .font(.title2.weight(.semibold))
                            .textFieldStyle(.plain)
                            .onSubmit { saveTitle() }
                            .accessibilityLabel("分组名称")
                        Button("保存名称") { saveTitle() }
                            .disabled(!canSaveTitle)
                    }
                    Text("为\(face.settingsName)设置四个常用入口。应用和文件夹可以混放。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(0..<4) { slot in
                        slotRow(slot)
                        if slot < 3 { Divider().padding(.leading, 50) }
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("也可以从 Finder 拖到立方体添加。移除入口会保留原来的应用或文件夹。")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { title = group.name }
        .onChange(of: model.selectedFace) { _, _ in title = group.name }
        .onChange(of: group.name) { _, value in title = value }
    }

    private var faceList: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("六个面，六个分组")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.bottom, 10)
            ForEach(CubeFace.allCases) { face in
                Button {
                    model.selectedFace = face
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: face.settingsSymbol)
                            .font(.system(size: 15)).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.configuration.group(for: face).name)
                                .font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(face.settingsName).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("\(model.configuration.group(for: face).slots.compactMap { $0 }.count)/4")
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(model.selectedFace == face ? Color.accentColor.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(face.settingsName)，\(model.configuration.group(for: face).name)")
                .accessibilityAddTraits(model.selectedFace == face ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(width: 194)
    }

    private var canSaveTitle: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != group.name
    }

    private func saveTitle() {
        guard canSaveTitle else { return }
        model.change { try $0.rename(face, to: title) }
    }

    @ViewBuilder private func slotRow(_ slot: Int) -> some View {
        HStack(spacing: 12) {
            if let item = group.slots[slot] {
                Image(nsImage: LauncherService.icon(for: item))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(item.url.path).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    Button { model.change { try $0.move(in: face, from: slot, to: slot - 1) } } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(slot == 0).help("向前移动")
                    .accessibilityLabel("将\(item.name)向前移动")
                    Button { model.change { try $0.move(in: face, from: slot, to: slot + 1) } } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(slot == 3).help("向后移动")
                    .accessibilityLabel("将\(item.name)向后移动")
                }
                Menu {
                    Button("打开") { model.launch(slot: slot, face: face) }
                    Button("重新选择目标…") { model.choose(for: face, slot: slot, replacing: true) }
                    Divider()
                    Button("移除入口", role: .destructive) {
                        model.change { try $0.remove(from: face, slot: slot) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton).frame(width: 22).help("入口选项")
                .accessibilityLabel("\(item.name)的入口选项")
            } else {
                Image(systemName: "plus.app")
                    .font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(.tertiary).frame(width: 36, height: 36)
                Text("入口 \(slot + 1)").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("添加…") { model.choose(for: face, slot: slot) }
                    .accessibilityLabel("在位置\(slot + 1)添加应用或文件夹")
            }
        }
        .buttonStyle(.borderless)
        .frame(height: 68)
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var primary = Color.cyan
    @State private var secondary = Color.purple
    @State private var glowIntensity = 0.55
    @State private var surfaceStyle: CubeSurfaceStyle = .clear
    @State private var scale = 1.0
    @State private var cycleEnabled = false
    @State private var cycleThemes: [CubeThemePreset] = [.aurora, .ocean, .sunset]
    @State private var cycleInterval = 10
    @State private var hoverEnabled = true
    @State private var hoverMultiplier = 4.0
    @State private var expandsFacesOnClick = true

    private var stagedAppearance: CubeAppearance {
        CubeAppearance(primaryHex: NSColor(primary).hexRGB,
                       secondaryHex: NSColor(secondary).hexRGB,
                       glowIntensity: glowIntensity, surfaceStyle: surfaceStyle)
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
        CubeHoverSettings(isEnabled: hoverEnabled, multiplier: hoverMultiplier)
    }

    private var validCycleSelection: Bool { !cycleEnabled || cycleThemes.count >= 2 }

    private var hasChanges: Bool {
        stagedAppearance != model.configuration.appearance || abs(scale - model.configuration.scale) > 0.001 ||
        stagedCycle != model.configuration.themeCycle || stagedHover != model.configuration.hover ||
        expandsFacesOnClick != model.configuration.expandsFacesOnClick
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("主题预设") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(CubeThemePreset.allCases) { preset in presetButton(preset) }
                        }
                        .frame(width: 330)
                    }
                    .disabled(cycleEnabled)
                    Picker("玻璃材质", selection: $surfaceStyle) {
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
                } header: {
                    Text("玻璃与光晕")
                } footer: {
                    Text(cycleEnabled ? "轮换使用所选主题的配色与当前光晕强度；关闭轮换后恢复上方保存的配色。" : "静置时显示透明立方体与渐变光晕；鼠标移入后显示应用图标。")
                }
                Section {
                    Toggle("自动轮换主题", isOn: $cycleEnabled)
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
                    .disabled(!cycleEnabled)
                    Picker("轮换间隔", selection: $cycleInterval) {
                        Text("10 秒").tag(10)
                        Text("20 秒").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!cycleEnabled)
                    if !validCycleSelection {
                        Label("请至少选择两种主题后应用。", systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("主题轮换")
                } footer: {
                    Text("按勾选顺序循环显示，应用后从第一种主题开始。")
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
                }
                Section {
                    Toggle("点击面展开放大", isOn: $expandsFacesOnClick)
                } header: {
                    Text("打开方式")
                } footer: {
                    Text(expandsFacesOnClick ? "先展开该面的四个图标，再点击图标打开应用。" : "直接点击立方体面上的图标打开；点击空白区域不执行操作。")
                }
                Section("操作方式") {
                    Label("鼠标左键、右键或触控板按住拖动，调整桌面位置", systemImage: "cursorarrow.motionlines")
                    Label("按住 Ctrl 恢复原大小；Ctrl＋左键按原大小拖动", systemImage: "control")
                    Label(expandsFacesOnClick ? "单击面立即展开；右键单击或从状态栏打开设置" : "单击图标直接打开；右键单击或从状态栏打开设置", systemImage: "square.on.square")
                    Label("触控板横向或纵向滚动，沿对应方向旋转", systemImage: "hand.draw")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text(!validCycleSelection ? "轮换至少需要两种主题" : hasChanges ? "设置有未应用的更改" : "设置已保存")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("还原更改") { loadAppearance() }.disabled(!hasChanges)
                Button("应用设置") { applyAppearance() }
                    .buttonStyle(.borderedProminent).disabled(!hasChanges || !validCycleSelection)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .onAppear { loadAppearance() }
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
                cycleThemes.removeAll { $0 == preset }
            }
        }
    }

    private func loadAppearance() {
        let appearance = model.configuration.appearance
        primary = Color(nsColor: NSColor(hexRGB: appearance.primaryHex) ?? .cyan)
        secondary = Color(nsColor: NSColor(hexRGB: appearance.secondaryHex) ?? .purple)
        glowIntensity = appearance.glowIntensity
        surfaceStyle = appearance.surfaceStyle
        scale = model.configuration.scale
        cycleEnabled = model.configuration.themeCycle.isEnabled
        cycleThemes = model.configuration.themeCycle.themes
        cycleInterval = model.configuration.themeCycle.intervalSeconds
        hoverEnabled = model.configuration.hover.isEnabled
        hoverMultiplier = model.configuration.hover.multiplier
        expandsFacesOnClick = model.configuration.expandsFacesOnClick
    }

    private func applyAppearance() {
        guard validCycleSelection else { return }
        let appearance = stagedAppearance
        let themeID = selectedPreset
        let cycle = stagedCycle
        let hover = stagedHover
        model.change {
            $0.appearance = appearance
            $0.scale = scale
            $0.themeID = themeID
            $0.themeCycle = cycle
            $0.hover = hover
            $0.expandsFacesOnClick = expandsFacesOnClick
        }
    }
}

private extension CubeFace {
    var settingsName: String {
        switch self {
        case .front: "正面"
        case .right: "右面"
        case .back: "背面"
        case .left: "左面"
        case .top: "顶面"
        case .bottom: "底面"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .front: "square"
        case .right: "rectangle.righthalf.filled"
        case .back: "square.dashed"
        case .left: "rectangle.lefthalf.filled"
        case .top: "rectangle.tophalf.filled"
        case .bottom: "rectangle.bottomhalf.filled"
        }
    }
}
