import AppKit
import SwiftUI
import CubeCore

struct EditorView: View {
    @ObservedObject var model: AppModel
    var lifecycle: LifecycleController? = nil
    var performance: PerformanceSettings? = nil
    var desktop: DesktopAutoHideSettings? = nil

    @State private var selection: SettingsPage = .launchers

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selection.title).font(.system(size: 28, weight: .semibold))
                    Text(selection.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 18)

                // Keep page navigation from resetting disclosures and local editing state.
                ZStack {
                    page(.launchers) { FaceSettingsView(model: model) }
                    page(.appearance) { AppearanceSettingsView(model: model) }
                    if desktop != nil || performance != nil {
                        page(.desktop) { DesktopSettingsView(model: model, desktop: desktop, performance: performance) }
                    }
                    page(.maintenance) { MaintenanceSettingsView(model: model) }
                    if let lifecycle {
                        page(.lifecycle) { LifecycleSettingsView(controller: lifecycle) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(SettingsGlass(material: .underWindowBackground))
        }
        .background(SettingsGlass(material: .sidebar).ignoresSafeArea())
        .frame(minWidth: 960, idealWidth: 1020, minHeight: 600, idealHeight: 700)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("T-Cube").font(.system(size: 19, weight: .semibold))
                    Text("让常用，触手可及").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.top, 10)
            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases) { item in
                    if isAvailable(item) {
                        Button { selection = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 17, weight: .medium)).frame(width: 24)
                                    .foregroundStyle(selection == item ? Color.accentColor : Color.secondary)
                                Text(item.title).font(.system(size: 13, weight: selection == item ? .semibold : .medium))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 13)
                            .background(selection == item ? Color.accentColor.opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == item ? .isSelected : [])
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text("左键拖动位置 · 右键拖动旋转")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("退出 T-Cube", systemImage: "power") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("退出应用并移除悬浮立方体")
            }.padding(10)
        }
        .padding(14).frame(width: 210)
    }

    private func isAvailable(_ page: SettingsPage) -> Bool {
        switch page {
        case .desktop: desktop != nil || performance != nil
        case .lifecycle: lifecycle != nil
        default: true
        }
    }

    private func page<Content: View>(_ page: SettingsPage, @ViewBuilder content: () -> Content) -> some View {
        content()
            .scrollContentBackground(.hidden)
            .opacity(selection == page ? 1 : 0)
            .allowsHitTesting(selection == page)
            .disabled(selection != page)
            .accessibilityHidden(selection != page)
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case launchers, appearance, desktop, maintenance, lifecycle
    var id: Self { self }
    var title: String {
        switch self {
        case .launchers: "立方体入口"
        case .appearance: "外观"
        case .desktop: "桌面与性能"
        case .maintenance: "配置与备份"
        case .lifecycle: "启动与更新"
        }
    }
    var subtitle: String {
        switch self {
        case .launchers: "把常用的应用、文件与网页，放到顺手的一面。"
        case .appearance: "选择材质、颜色与动效，打造你的桌面立方体。"
        case .desktop: "让立方体融入桌面，兼顾流畅与节能。"
        case .maintenance: "备份你的设置，管理与修复本地入口。"
        case .lifecycle: "管理登录启动，获取 T-Cube 的新版本。"
        }
    }
    var symbol: String {
        switch self {
        case .launchers: "cube"
        case .appearance: "paintpalette"
        case .desktop: "desktopcomputer"
        case .maintenance: "externaldrive"
        case .lifecycle: "arrow.triangle.2.circlepath"
        }
    }
}

/// Native desktop blur follows system appearance and accessibility preferences.
struct SettingsGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.wantsLayer = true
        view.layer?.backgroundColor = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
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
                            .font(InterfaceTypography.title)
                            .textFieldStyle(.plain)
                            .onSubmit { saveTitle() }
                            .accessibilityLabel("分组名称")
                        Button("保存名称") { saveTitle() }
                            .disabled(!canSaveTitle)
                    }
                    Text("为\(face.settingsName)设置四个常用入口。可混放应用、文件夹、文件、网页与系统设置。")
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
                    Text("也可以从 Finder 拖到立方体添加。移除入口会保留原来的目标。")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(InterfaceTypography.detail).foregroundStyle(.secondary)
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
                            Text(face.settingsName).font(InterfaceTypography.detail).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("\(model.configuration.group(for: face).slots.compactMap { $0 }.count)/4")
                            .font(InterfaceTypography.value).foregroundStyle(.secondary)
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
                    Text(item.targetDescription).font(InterfaceTypography.detail).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(item.targetDescription)
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
                    .accessibilityLabel("在位置\(slot + 1)添加入口")
            }
        }
        .buttonStyle(.borderless)
        .frame(height: 68)
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
