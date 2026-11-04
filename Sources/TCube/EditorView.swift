import AppKit
import SwiftUI
import CubeCore

struct EditorView: View {
    @ObservedObject var model: AppModel
    var lifecycle: LifecycleController? = nil
    var performance: PerformanceSettings? = nil
    var desktop: DesktopAutoHideSettings? = nil

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                FaceSettingsView(model: model)
                    .tabItem { Label("立方体入口", systemImage: "cube") }
                AppearanceSettingsView(model: model)
                    .tabItem { Label("外观", systemImage: "paintpalette") }
                if desktop != nil || performance != nil {
                    DesktopSettingsView(model: model, desktop: desktop, performance: performance)
                        .tabItem { Label("桌面与性能", systemImage: "desktopcomputer") }
                }
                MaintenanceSettingsView(model: model)
                    .tabItem { Label("配置与备份", systemImage: "externaldrive") }
                if let lifecycle {
                    LifecycleSettingsView(controller: lifecycle)
                        .tabItem { Label("启动与更新", systemImage: "arrow.triangle.2.circlepath") }
                }
            }
            .padding(16)
            Divider()
            HStack {
                Text("左键拖动位置 · 右键拖动旋转")
                    .font(InterfaceTypography.detail).foregroundStyle(.secondary)
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
