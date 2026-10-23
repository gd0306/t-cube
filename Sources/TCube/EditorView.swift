import AppKit
import SwiftUI
import CubeCore

struct EditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            FaceSettingsView(model: model)
                .tabItem { Label("立方体入口", systemImage: "cube") }
            AppearanceSettingsView(model: model)
                .tabItem { Label("外观", systemImage: "paintpalette") }
        }
        .padding(16)
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
    @State private var scale = 1.0

    private struct Preset: Identifiable {
        let id: String
        let name: String
        let primary: String
        let secondary: String
    }

    private let presets = [
        Preset(id: "aurora", name: "极光", primary: "#65DEFF", secondary: "#B793FF"),
        Preset(id: "ocean", name: "海洋", primary: "#4CB8FF", secondary: "#3EE4CF"),
        Preset(id: "sunset", name: "晚霞", primary: "#FFAA73", secondary: "#EE79B5")
    ]

    private var stagedAppearance: CubeAppearance {
        CubeAppearance(primaryHex: NSColor(primary).hexRGB,
                       secondaryHex: NSColor(secondary).hexRGB,
                       glowIntensity: glowIntensity)
    }

    private var selectedPreset: String {
        let appearance = stagedAppearance
        return presets.first {
            $0.primary.caseInsensitiveCompare(appearance.primaryHex) == .orderedSame &&
            $0.secondary.caseInsensitiveCompare(appearance.secondaryHex) == .orderedSame
        }?.id ?? "custom"
    }

    private var hasChanges: Bool {
        stagedAppearance != model.configuration.appearance || abs(scale - model.configuration.scale) > 0.001
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("配色预设") {
                        HStack(spacing: 10) {
                            ForEach(presets) { preset in presetButton(preset) }
                        }
                    }
                    ColorPicker("主色", selection: $primary, supportsOpacity: false)
                    ColorPicker("辅助色", selection: $secondary, supportsOpacity: false)
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
                    Text("静置时显示透明立方体与渐变光晕；鼠标移入后显示应用图标。")
                }
                Section("立方体尺寸") {
                    LabeledContent("大小") {
                        HStack(spacing: 12) {
                            Slider(value: $scale, in: CubeConfiguration.scaleRange, step: 0.05)
                                .accessibilityLabel("立方体大小")
                            Text(scale, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        }.frame(width: 270)
                    }
                }
                Section("操作方式") {
                    Label("右键拖动立方体，调整桌面位置", systemImage: "cursorarrow.motionlines")
                    Label("触控板横向或纵向滚动，沿对应方向旋转", systemImage: "hand.draw")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text(hasChanges ? "外观有未应用的更改" : "外观已保存")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("还原更改") { loadAppearance() }.disabled(!hasChanges)
                Button("应用外观") { applyAppearance() }
                    .buttonStyle(.borderedProminent).disabled(!hasChanges)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .onAppear { loadAppearance() }
    }

    private func presetButton(_ preset: Preset) -> some View {
        Button {
            primary = Color(nsColor: NSColor(hexRGB: preset.primary) ?? .cyan)
            secondary = Color(nsColor: NSColor(hexRGB: preset.secondary) ?? .purple)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: [
                        Color(nsColor: NSColor(hexRGB: preset.primary) ?? .cyan),
                        Color(nsColor: NSColor(hexRGB: preset.secondary) ?? .purple)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 13, height: 13)
                Text(preset.name)
                if selectedPreset == preset.id { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
            }
        }
        .buttonStyle(.bordered)
        .accessibilityAddTraits(selectedPreset == preset.id ? .isSelected : [])
    }

    private func loadAppearance() {
        let appearance = model.configuration.appearance
        primary = Color(nsColor: NSColor(hexRGB: appearance.primaryHex) ?? .cyan)
        secondary = Color(nsColor: NSColor(hexRGB: appearance.secondaryHex) ?? .purple)
        glowIntensity = appearance.glowIntensity
        scale = model.configuration.scale
    }

    private func applyAppearance() {
        let appearance = stagedAppearance
        let themeID = selectedPreset
        model.change {
            $0.appearance = appearance
            $0.scale = scale
            $0.themeID = themeID
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
