import AppKit
import CubeCore
import SwiftUI

@MainActor
final class ClipboardPanelNavigation: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case library = "常用内容"
        case history = "剪贴板历史"
        var id: String { rawValue }
    }
    @Published var mode: Mode = .library
}

struct ClipboardPanelView: View {
    @ObservedObject var navigation: ClipboardPanelNavigation
    @ObservedObject var library: SnippetLibraryModel
    @ObservedObject var history: ClipboardHistoryModel
    let useText: (String, Bool) -> Void
    let useImage: (ClipboardHistoryImage, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("内容类型", selection: $navigation.mode) {
                ForEach(ClipboardPanelNavigation.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .padding(.vertical, 10)
            Divider()
            ZStack {
                SnippetLibraryView(model: library, isActive: navigation.mode == .library, useText: useText)
                    .opacity(navigation.mode == .library ? 1 : 0)
                    .allowsHitTesting(navigation.mode == .library)
                    .disabled(navigation.mode != .library)
                    .accessibilityHidden(navigation.mode != .library)
                ClipboardHistoryView(model: history, isActive: navigation.mode == .history, libraryStatus: library.status, canSave: library.mutationsEnabled, useText: useText, useImage: useImage) { text in
                    navigation.mode = .library
                    library.pendingCapture = text
                }
                .opacity(navigation.mode == .history ? 1 : 0)
                .allowsHitTesting(navigation.mode == .history)
                .disabled(navigation.mode != .history)
                .accessibilityHidden(navigation.mode != .history)
            }
        }
    }
}

struct ClipboardHistoryView: View {
    enum Category: String, CaseIterable, Identifiable {
        case text = "文字"
        case images = "图片"
        var id: String { rawValue }
    }
    private enum ClearScope { case text, images, all }

    @ObservedObject var model: ClipboardHistoryModel
    let isActive: Bool
    let libraryStatus: String
    let canSave: Bool
    let useText: (String, Bool) -> Void
    let useImage: (ClipboardHistoryImage, Bool) -> Void
    let saveText: (String) -> Void
    @State var category: Category = .text
    @State var selectedIDs: Set<UUID> = []
    @State var selectedImageID: UUID?
    @State private var textAction: ClipboardTextAction = .original
    @State private var processingEntryID: UUID?
    @State private var processingDraft = ""
    @State private var processingSource = ""
    @State private var isEditingProcessing = false
    @State var trimLines = false
    @State var collapseBlankLines = false
    @State private var showsRecordingDetails = false
    @State private var showsTextCleanup = false
    @State private var clearScope: ClearScope = .text
    @State private var confirmingClear = false
    @FocusState private var searchFocused: Bool

    private var mergedText: String? {
        model.mergedText(selectedIDs: selectedIDs, trimLines: trimLines, collapseBlankLines: collapseBlankLines)
    }
    private var processedText: Result<String, Error>? {
        if let processingEntryID {
            guard model.entries.contains(where: { $0.id == processingEntryID }) else { return nil }
            return Result { try ClipboardTextAction.original.apply(to: processingDraft) }
        }
        return mergedText.map { .success($0) }
    }
    private var selectedImage: ClipboardHistoryImage? {
        model.images.first { $0.id == selectedImageID }
    }
    private var clearTitle: String {
        switch clearScope {
        case .text: "清空文字历史？"
        case .images: "清空图片历史？"
        case .all: "清空全部剪贴板历史？"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("剪贴板历史").font(InterfaceTypography.title)
                    Label(model.isEnabled ? "正在记录 · 仅本次运行，退出清除" : "记录已暂停 · 本次内容退出清除",
                          systemImage: model.isEnabled ? "record.circle" : "pause.circle")
                        .font(.callout).foregroundStyle(.secondary)
                    DisclosureGroup("记录说明", isExpanded: $showsRecordingDetails) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("每次启动默认记录，可随时暂停；仅在内存中保存新内容，不包含在备份中。")
                            Text("文字最多 100 条 / 2 MiB；图片保留最近 10 张 / 32 MiB。")
                            Text("会尽力跳过敏感、临时和文件拖放内容，无法保证识别所有敏感信息。")
                            Text("单条文字及合并输出最多 64 KiB。")
                        }
                        .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(InterfaceTypography.detail)
                }
                Spacer()
                Button(model.isEnabled ? "暂停记录" : "启用记录") {
                    if model.isEnabled { model.pause() } else { model.enable() }
                }.buttonStyle(.bordered)
            }.padding(.horizontal, 22).padding(.vertical, 16)
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                Group {
                    if category == .text { textDetail }
                    else { imageDetail }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            Text("\(model.status) \(libraryStatus)")
                .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.vertical, 11)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 800, idealWidth: 920, minHeight: 540, idealHeight: 680)
        .onChange(of: isActive) { _, active in searchFocused = active && category == .text }
        .onChange(of: category) { _, value in searchFocused = isActive && value == .text }
        .onChange(of: selectedIDs) { _, ids in
            if let processingEntryID, ids != [processingEntryID] { cancelProcessing() }
        }
        .onChange(of: model.query) { _, _ in selectedIDs.removeAll() }
        .onChange(of: model.visibleEntries.map(\.id)) { _, ids in
            selectedIDs.formIntersection(ids)
        }
        .onChange(of: model.entries) { _, entries in
            if let processingEntryID, entries.first(where: { $0.id == processingEntryID })?.text != processingSource {
                cancelProcessing(); model.status = "原记录已修改或删除，请重新选择处理。"
            }
        }
        .onChange(of: model.images.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedImageID }) { selectedImageID = nil }
        }
        .confirmationDialog(clearTitle, isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("确认清空", role: .destructive) {
                switch clearScope {
                case .text: model.clearText(); selectedIDs.removeAll()
                case .images: model.clearImages(); selectedImageID = nil
                case .all: model.clear(); selectedIDs.removeAll(); selectedImageID = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("仅清除所选类别在本次运行中的记录，无法撤销；系统剪贴板保持原样。") }
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            Picker("历史类别", selection: $category) {
                ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 14).padding(.top, 14)
            Text(category == .text ? "最多 100 条 · 2 MiB" : "最近 10 张 · 32 MiB")
                .font(InterfaceTypography.detail).foregroundStyle(.secondary).padding(.horizontal, 14)
            if category == .text {
                TextField("搜索文字历史", text: $model.query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused).accessibilityLabel("搜索文字历史")
                    .padding(.horizontal, 14)
                Text("按住 ⌘ 或 ⇧ 多选，按列表顺序合并。")
                    .font(InterfaceTypography.detail).foregroundStyle(.secondary).padding(.horizontal, 14)
                if model.visibleEntries.isEmpty {
                    emptyState(model.entries.isEmpty ? "还没有文字记录" : "没有匹配的内容")
                } else {
                    List(selection: $selectedIDs) {
                        ForEach(model.visibleEntries) { entry in
                            HStack {
                                Text(String(entry.text.prefix(160)).replacingOccurrences(of: "\n", with: " "))
                                    .lineLimit(2).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                Menu {
                                    ForEach(ClipboardTextAction.allCases) { action in
                                        Button(action.title) { processEntry(entry.id, action: action) }
                                    }
                                } label: { Image(systemName: "text.badge.checkmark") }
                                .menuStyle(.borderlessButton).fixedSize().help("快捷处理文字").accessibilityLabel("快捷处理文字")
                            }
                            .padding(.vertical, 5).tag(entry.id)
                        }
                    }.listStyle(.inset).accessibilityLabel("文字历史列表，可多选")
                }
            } else if model.images.isEmpty {
                emptyState("还没有图片记录")
            } else {
                List(selection: $selectedImageID) {
                    ForEach(model.images) { image in
                        HStack(spacing: 10) {
                            if let thumbnail = NSImage(data: image.thumbnailPNG) {
                                Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 64, height: 48)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(image.width) × \(image.height)").font(.callout.monospacedDigit())
                                Text(image.capturedAt, style: .time).font(InterfaceTypography.detail)
                                    .foregroundStyle(.secondary)
                            }
                        }.foregroundStyle(.primary)
                            .padding(.vertical, 4)
                            .tag(image.id)
                    }
                }.listStyle(.inset).accessibilityLabel("图片历史列表")
            }
            HStack {
                Text(category == .text ? "\(model.visibleEntries.count) 条 · 已选 \(selectedIDs.count) 条" : "\(model.images.count) / 10 张")
                Spacer()
                Menu("清空…") {
                    Button("清空文字历史…", role: .destructive) { clearScope = .text; confirmingClear = true }.disabled(model.entries.isEmpty)
                    Button("清空图片历史…", role: .destructive) { clearScope = .images; confirmingClear = true }.disabled(model.images.isEmpty)
                    Divider()
                    Button("清空全部历史…", role: .destructive) { clearScope = .all; confirmingClear = true }
                        .disabled(model.entries.isEmpty && model.images.isEmpty)
                }.menuStyle(.borderlessButton).fixedSize()
            }.font(InterfaceTypography.detail).padding(.horizontal, 14).padding(.bottom, 12)
        }.frame(width: 290)
    }

    private var textDetail: some View {
        let result = processedText
        let output = try? result?.get()
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedIDs.count > 1 ? "合并预览 · \(selectedIDs.count) 条" : "文字预览").font(.headline)
                Spacer()
                Button("删除选中", role: .destructive) {
                    for id in selectedIDs { model.delete(id) }
                    selectedIDs.removeAll()
                }.disabled(selectedIDs.isEmpty)
            }
            HStack {
                Button("粘贴", systemImage: "arrow.up.doc.on.clipboard") { if let output { useText(output, true) } }
                    .buttonStyle(.borderedProminent).disabled(output == nil)
                Button("复制", systemImage: "doc.on.doc") { if let output { useText(output, false) } }.disabled(output == nil)
                Button("存为常用内容", systemImage: "plus") { if let output { saveText(output) } }.disabled(!canSave || output == nil)
            }
            if let processingEntryID {
                HStack {
                    Text(textAction.title + " · 预览").font(.callout.weight(.medium))
                    Spacer()
                    if isEditingProcessing {
                        Button("保存到本条记录") {
                            if let output, model.updateText(id: processingEntryID, text: output) { cancelProcessing() }
                        }.disabled(output == nil)
                    } else {
                        Button("编辑结果") { isEditingProcessing = true }
                    }
                    Button("取消处理") { cancelProcessing() }
                }
                Text("复制不改动历史；修改记录不写入剪贴板。URL 编码用于单个参数值，解码保留 +。")
                    .font(InterfaceTypography.detail).foregroundStyle(.secondary)
            }
            DisclosureGroup("整理文字", isExpanded: $showsTextCleanup) {
                HStack(spacing: 18) {
                    Toggle("逐行去除首尾空白", isOn: $trimLines)
                    Toggle("合并连续空行", isOn: $collapseBlankLines)
                }.toggleStyle(.checkbox).font(InterfaceTypography.detail)
                Text("多条记录以换行连接，原记录保持不变。输出最多 64 KiB。")
                    .font(InterfaceTypography.detail).foregroundStyle(.secondary)
            }
            .disabled(processingEntryID != nil)
            Divider()
            if processingEntryID != nil && isEditingProcessing {
                TextEditor(text: $processingDraft).font(InterfaceTypography.body)
                    .accessibilityLabel("编辑处理结果")
            } else if let output {
                ScrollView {
                    Text(output).font(InterfaceTypography.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if case .failure(let error) = result {
                emptyState(error.localizedDescription)
            } else {
                emptyState(selectedIDs.isEmpty ? "选择一条或多条文字记录查看预览" : "合并内容为空或超过 64 KiB，请减少选择或调整清理选项。")
            }
        }.padding(24)
    }

    private func processEntry(_ id: UUID, action: ClipboardTextAction) {
        guard let entry = model.entries.first(where: { $0.id == id }) else { model.status = "这条记录已删除。"; return }
        cancelProcessing()
        do {
            let output = try action.apply(to: entry.text)
            selectedIDs = [id]; processingEntryID = id; textAction = action; processingSource = entry.text
            isEditingProcessing = false; processingDraft = output
            model.status = action.notice(source: entry.text, result: output) ?? "已生成预览，原记录保持不变。"
        } catch { model.status = error.localizedDescription }
    }

    private func cancelProcessing() {
        processingEntryID = nil; textAction = .original; processingDraft = ""; processingSource = ""
        isEditingProcessing = false
    }

    @ViewBuilder private var imageDetail: some View {
        if let image = selectedImage {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("图片预览").font(.headline)
                    Spacer()
                    Button("删除图片", role: .destructive) { model.deleteImage(image.id); selectedImageID = nil }
                }
                HStack {
                    Button("粘贴图片", systemImage: "arrow.up.doc.on.clipboard") { useImage(image, true) }.buttonStyle(.borderedProminent)
                    Button("复制图片", systemImage: "doc.on.doc") { useImage(image, false) }
                }
                Text("\(image.width) × \(image.height) · \(ByteCountFormatter.string(fromByteCount: Int64(image.pngData.count), countStyle: .binary)) · PNG")
                    .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                Text("源数据与 PNG 各上限 8 MiB、1600 万像素；只保存本次运行内最近 10 张图片。")
                    .font(InterfaceTypography.detail).foregroundStyle(.secondary)
                Divider()
                ClipboardHistoryImagePreview(image: image).id(image.id)
            }.padding(24)
        } else {
            emptyState("选择一张图片查看预览")
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

private struct ClipboardHistoryImagePreview: View {
    let image: ClipboardHistoryImage
    @State private var preview: NSImage?

    var body: some View {
        Group {
            if let preview { Image(nsImage: preview).resizable().scaledToFit() }
            else { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: image.id) {
            let data = image.pngData
            let pixels = await ClipboardHistoryImageProcessor.shared.preview(data)
            guard !Task.isCancelled, let pixels else { return }
            preview = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
        }
    }
}
