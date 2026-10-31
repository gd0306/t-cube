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
                ClipboardHistoryView(model: history, isActive: navigation.mode == .history, libraryStatus: library.status, canSave: library.mutationsEnabled, useText: useText) { text in
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
    @ObservedObject var model: ClipboardHistoryModel
    let isActive: Bool
    let libraryStatus: String
    let canSave: Bool
    let useText: (String, Bool) -> Void
    let saveText: (String) -> Void
    @State private var selectedID: UUID?
    @State private var confirmingClear = false
    @FocusState private var searchFocused: Bool

    private var selected: ClipboardHistoryEntry? {
        model.visibleEntries.first { $0.id == selectedID } ?? model.visibleEntries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("剪贴板历史").font(.title2.weight(.semibold))
                    Text("每次启动默认暂停，启用后仅在内存中保存，退出即清除，不包含在备份中。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("最多 100 条，每条 64 KiB，总计 2 MiB。会尽力跳过标记为敏感或临时的内容，但无法识别所有敏感信息。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.isEnabled ? "暂停记录" : "启用记录") {
                    if model.isEnabled { model.pause() } else { model.enable() }
                }.buttonStyle(.borderedProminent)
            }.padding(20)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    TextField("搜索剪贴板历史", text: $model.query)
                        .textFieldStyle(.roundedBorder).focused($searchFocused).accessibilityLabel("搜索剪贴板历史")
                        .padding(.horizontal, 14).padding(.top, 14)
                    if model.visibleEntries.isEmpty {
                        Text(model.entries.isEmpty ? "还没有记录" : "没有匹配的内容")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $selectedID) {
                            ForEach(model.visibleEntries) { entry in
                                Text(String(entry.text.prefix(160)).replacingOccurrences(of: "\n", with: " "))
                                    .lineLimit(2).padding(.vertical, 5).tag(entry.id)
                            }
                        }.listStyle(.sidebar).accessibilityLabel("剪贴板历史列表")
                    }
                    HStack {
                        Text("\(model.visibleEntries.count) 条记录")
                        Spacer()
                        Button("清空") { confirmingClear = true }.disabled(model.entries.isEmpty)
                    }.font(.caption).padding(.horizontal, 14).padding(.bottom, 12)
                }.frame(width: 290)
                Divider()
                if let entry = selected {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("记录内容").font(.headline)
                            Spacer()
                            Button("删除", role: .destructive) {
                                model.delete(entry.id)
                                selectedID = nil
                            }
                        }
                        HStack {
                            Button("粘贴", systemImage: "arrow.up.doc.on.clipboard") { useText(entry.text, true) }
                                .buttonStyle(.borderedProminent)
                            Button("复制", systemImage: "doc.on.doc") { useText(entry.text, false) }
                            Button("存为常用内容", systemImage: "plus") { saveText(entry.text) }.disabled(!canSave)
                        }
                        Divider()
                        ScrollView {
                            Text(entry.text).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text("选择一条记录查看内容")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            Text("\(model.status) \(libraryStatus)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.vertical, 11)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 800, idealWidth: 920, minHeight: 540, idealHeight: 640)
        .onChange(of: isActive) { _, active in searchFocused = active }
        .onChange(of: model.visibleEntries.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedID }) { selectedID = ids.first }
        }
        .confirmationDialog("清空剪贴板历史？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { model.clear(); selectedID = nil }
            Button("取消", role: .cancel) {}
        } message: { Text("仅清除本次运行的历史记录，无法撤销。") }
    }
}
