import AppKit
import CubeCore
import SwiftUI

struct SnippetLibraryView: View {
    @ObservedObject var model: SnippetLibraryModel
    let useText: (String, Bool) -> Void
    @State private var draft: TextSnippet?
    @State private var deleting: TextSnippet?
    @State private var isDropTarget = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                libraryList
                Divider()
                if let snippet = model.selectedSnippet {
                    detail(snippet)
                } else {
                    emptyDetail
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 800, idealWidth: 920, minHeight: 540, idealHeight: 640)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { strings, _ in
            guard model.mutationsEnabled else { return false }
            return createDraft(from: strings.joined(separator: "\n"))
        } isTargeted: { isDropTarget = $0 }
        .sheet(item: $draft) { snippet in
            SnippetEditorSheet(model: model, snippet: snippet)
        }
        .confirmationDialog("删除「\(deleting?.title ?? "")」？", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("删除内容", role: .destructive) {
                if let deleting { model.delete(deleting.id) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: {
            Text("删除后无法撤销。")
        }
        .onAppear {
            searchFocused = true
            consumePendingCapture()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TCubeSnippetSearchFocus"))) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TCubeSnippetCaptureText"))) { notification in
            if let text = notification.userInfo?["text"] as? String { model.pendingCapture = text }
        }
        .onChange(of: model.pendingCapture) { _, _ in
            consumePendingCapture()
        }
        .onChange(of: model.visibleItems.map(\.id)) { _, _ in
            model.selectedID = model.selectedSnippet?.id
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 25)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("常用内容").font(.title2.weight(.semibold))
                Text("⌘ ⇧ 空格 随时唤出 · Esc 关闭")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("从剪贴板新建", systemImage: "clipboard") { captureClipboard() }
                .help("读取当前剪贴板文字，确认后再保存")
                .accessibilityLabel("从剪贴板新建内容")
            Button("新建内容", systemImage: "plus") { draft = TextSnippet() }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .disabled(!model.mutationsEnabled)
    }

    private var libraryList: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索标题、正文或字段", text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("搜索常用内容")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("清除搜索")
                }
            }
            .padding(9)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 14).padding(.top, 14)
            HStack {
                Picker("分组", selection: $model.selectedGroup) {
                    Text("全部分组").tag(nil as String?)
                    ForEach(model.groups, id: \.self) { group in
                        Text(group).tag(Optional(group))
                    }
                }
                .labelsHidden().accessibilityLabel("筛选内容分组")
                Toggle(isOn: $model.favoritesOnly) {
                    Image(systemName: model.favoritesOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button).help("只显示收藏")
                .accessibilityLabel("只显示收藏内容")
            }
            .padding(.horizontal, 14)
            if model.visibleItems.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(model.items.isEmpty ? "还没有常用内容" : "没有匹配的内容")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.visibleItems) { snippet in
                        listRow(snippet).tag(snippet.id)
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("常用内容列表")
            }
            HStack {
                Text("\(model.visibleItems.count) 条内容")
                Spacer()
                Text("收藏优先")
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.bottom, 12)
        }
        .frame(width: 290)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private func listRow(_ snippet: TextSnippet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(snippet.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if snippet.isFavorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange)
                }
            }
            Text(snippet.fullText.replacingOccurrences(of: "\n", with: " "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if !snippet.group.isEmpty {
                Text(snippet.group).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("复制全部") { useText(snippet.fullText, false) }
            Button(snippet.isFavorite ? "取消收藏" : "加入收藏") { model.toggleFavorite(snippet.id) }
                .disabled(!model.mutationsEnabled)
            Button("编辑内容") { draft = snippet }.disabled(!model.mutationsEnabled)
            Divider()
            Button("删除内容", role: .destructive) { deleting = snippet }.disabled(!model.mutationsEnabled)
        }
    }

    private func detail(_ snippet: TextSnippet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(snippet.group.isEmpty ? "未分组" : snippet.group)
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(snippet.title).font(.system(size: 25, weight: .semibold))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 10)
                    Button { model.toggleFavorite(snippet.id) } label: {
                        Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(snippet.isFavorite ? Color.orange : Color.secondary)
                    }
                    .help(snippet.isFavorite ? "取消收藏" : "加入收藏")
                    .accessibilityLabel(snippet.isFavorite ? "取消收藏内容" : "收藏内容")
                    .disabled(!model.mutationsEnabled)
                    Button("编辑", systemImage: "pencil") { draft = snippet }
                        .accessibilityLabel("编辑所选内容").disabled(!model.mutationsEnabled)
                }
                HStack(spacing: 10) {
                    Button("粘贴全部", systemImage: "arrow.up.doc.on.clipboard") { useText(snippet.fullText, true) }
                        .buttonStyle(.borderedProminent)
                        .help("将全部内容粘贴到唤出内容库前的输入框")
                    Button("复制全部", systemImage: "doc.on.doc") { useText(snippet.fullText, false) }
                    Spacer()
                }
            }
            .padding(24)
            Divider().padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !snippet.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("正文").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(snippet.body).font(.system(size: 14)).lineSpacing(5)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if !snippet.fields.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("独立字段").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.bottom, 6)
                            ForEach(snippet.fields) { field in
                                fieldRow(field)
                                if field.id != snippet.fields.last?.id { Divider() }
                            }
                        }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button { model.move(snippet.id, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(!model.canMove(snippet.id, by: -1)).help("向前移动")
                    .accessibilityLabel("向前移动内容")
                Button { model.move(snippet.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(!model.canMove(snippet.id, by: 1)).help("向后移动")
                    .accessibilityLabel("向后移动内容")
                Spacer()
                Button("删除", systemImage: "trash", role: .destructive) { deleting = snippet }
                    .accessibilityLabel("删除所选内容").disabled(!model.mutationsEnabled)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fieldRow(_ field: SnippetField) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(field.label.isEmpty ? "未命名字段" : field.label)
                    .font(.caption).foregroundStyle(.secondary)
                Text(field.value.isEmpty ? "（空）" : field.value)
                    .font(.system(size: 14)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { useText(field.value, false) } label: { Image(systemName: "doc.on.doc") }
                .help("复制字段值").accessibilityLabel("复制字段：\(field.label)")
            Button { useText(field.value, true) } label: { Image(systemName: "arrow.up.doc.on.clipboard") }
                .help("粘贴字段值").accessibilityLabel("粘贴字段：\(field.label)")
        }
        .buttonStyle(.borderless).disabled(field.value.isEmpty)
        .padding(.vertical, 14)
    }

    private var emptyDetail: some View {
        VStack(spacing: 15) {
            Image(systemName: model.items.isEmpty ? "text.badge.plus" : "magnifyingglass")
                .font(.system(size: 42, weight: .light)).foregroundStyle(.secondary)
            Text(model.items.isEmpty ? "让常用信息随手可用" : "换个关键词试试")
                .font(.title3.weight(.medium))
            Text(model.items.isEmpty ? "保存地址、开票信息或常用回复。\n也可以拖入文字，检查后保存。" : "可按标题、分组、正文和字段搜索。")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            if model.items.isEmpty {
                Button("新建第一条内容", systemImage: "plus") { draft = TextSnippet() }
                    .disabled(!model.mutationsEnabled)
            }
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityLabel("内容库错误：\(error)")
            }
            Text(model.status).foregroundStyle(.secondary).textSelection(.enabled)
                .accessibilityLabel("内容库状态：\(model.status)")
        }
        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.vertical, 11)
    }

    private func captureClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), createDraft(from: text) else {
            model.status = "剪贴板中没有可保存的文字。"
            return
        }
    }

    private func consumePendingCapture() {
        guard let text = model.pendingCapture else { return }
        defer { model.pendingCapture = nil }
        guard model.mutationsEnabled else { return }
        guard draft == nil else {
            model.status = "请先保存或取消当前编辑，再拖入新的文字。"
            return
        }
        createDraft(from: text)
    }

    @discardableResult
    private func createDraft(from text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let title = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        draft = TextSnippet(title: String(title.prefix(40)), group: model.selectedGroup ?? "", body: text)
        return true
    }
}

private struct SnippetEditorSheet: View {
    @ObservedObject var model: SnippetLibraryModel
    @State var snippet: TextSnippet
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    private var canSave: Bool {
        !snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !snippet.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.mutationsEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.items.contains(where: { $0.id == snippet.id }) ? "编辑内容" : "新建内容")
                .font(.title2.weight(.semibold))
            Text("检查文字后保存。字段可单独复制或粘贴。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    labeled("标题") {
                        TextField("例如：公司开票信息", text: $snippet.title)
                            .focused($titleFocused).accessibilityLabel("内容标题")
                    }
                    labeled("分组") {
                        HStack {
                            TextField("例如：工作（可留空）", text: $snippet.group)
                                .accessibilityLabel("内容分组")
                            if !model.groups.isEmpty {
                                Menu("已有分组") {
                                    ForEach(model.groups, id: \.self) { group in
                                        Button(group) { snippet.group = group }
                                    }
                                }.fixedSize()
                            }
                        }
                    }
                    labeled("正文") {
                        TextEditor(text: $snippet.body)
                            .font(.system(size: 14)).scrollContentBackground(.hidden)
                            .padding(7).frame(minHeight: 120)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                            .accessibilityLabel("内容正文")
                    }
                    HStack {
                        Text("独立字段").font(.callout.weight(.medium))
                        Spacer()
                        Button("添加字段", systemImage: "plus") { snippet.fields.append(SnippetField()) }
                            .accessibilityLabel("添加独立字段")
                    }
                    ForEach($snippet.fields) { $field in
                        HStack(alignment: .top, spacing: 10) {
                            TextField("字段名", text: $field.label)
                                .frame(width: 120).accessibilityLabel("字段名称")
                            TextField("字段值（支持多行）", text: $field.value, axis: .vertical)
                                .lineLimit(1...5).accessibilityLabel("字段值")
                            Button {
                                snippet.fields.removeAll { $0.id == field.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).help("移除字段")
                                .accessibilityLabel("移除字段：\(field.label)")
                        }
                    }
                    Toggle("加入收藏", isOn: $snippet.isFavorite)
                }
                .textFieldStyle(.roundedBorder).padding(2)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Text("仅保存在这台 Mac 上").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存内容") {
                    if model.save(snippet) { dismiss() }
                }
                .keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(24).frame(width: 620, height: 620)
        .onAppear { titleFocused = true }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.callout.weight(.medium))
            content()
        }
    }
}
