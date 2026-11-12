import AppKit
import CubeCore
import SwiftUI

struct ClipboardQuickView: View {
    @ObservedObject var controller: ClipboardQuickController
    @ObservedObject var history: ClipboardHistoryModel
    private var ink: Color { Color(white: controller.isDark ? 0.96 : 0.10) }
    private var muted: Color { Color(white: controller.isDark ? 0.75 : 0.37) }

    private enum Row: Identifiable {
        case text(ClipboardHistoryEntry), image(ClipboardHistoryImage)
        var id: UUID { switch self { case .text(let entry): entry.id; case .image(let image): image.id } }
        var date: Date { switch self { case .text(let entry): entry.capturedAt; case .image(let image): image.capturedAt } }
    }

    private var rows: [Row] {
        let query = controller.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let texts = history.entries.filter { query.isEmpty || $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.map(Row.text)
        let images = history.images.filter { query.isEmpty || "图片 \($0.width) × \($0.height)".contains(query) }.map(Row.image)
        return (texts + images).sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.overlay {
                ClipboardQuickDragRegion().padding(.trailing, 40)
            }.padding(18)
            Divider().padding(.horizontal, 18)
            if controller.processingID != nil { processingPreview }
            else if controller.editingID != nil { editor }
            else { list }
            Divider().padding(.horizontal, 18)
            footer.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.14))
        .foregroundStyle(ink)
        .environment(\.colorScheme, controller.isDark ? .dark : .light)
        .onExitCommand { controller.handleEscape() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clipboard").font(.system(size: 20)).foregroundStyle(muted)
            VStack(alignment: .leading, spacing: 4) {
                Text("剪贴板历史").font(.system(size: 17, weight: .semibold))
                Text(controller.processingID != nil ? "快捷处理 · 原记录保持不变" : controller.editingID == nil ? "单击复制 · 拖动标题移动 · 退出清空" : "编辑文字 · 保存后点选复制")
                    .font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            Button { controller.dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                .buttonStyle(.plain).accessibilityLabel("关闭剪贴板历史").help("关闭（Esc）")
        }
    }

    private var list: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(muted)
                TextField("搜索历史内容", text: $controller.query).textFieldStyle(.plain)
                    .accessibilityLabel("搜索历史内容")
            }.padding(10).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 18).padding(.top, 14)
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 28)).foregroundStyle(muted)
                    Text(controller.query.isEmpty ? (history.isEnabled ? "等待下一次复制" : "剪贴板记录已暂停")
                         : "没有匹配的历史内容").font(.headline)
                    Text(history.isEnabled ? "复制新的文字或图片后，会出现在这里。" : "启用后记录新复制的文字与图片，仅在本次运行中保留。")
                        .font(.system(size: 13)).foregroundStyle(muted).multilineTextAlignment(.center)
                    if !history.isEnabled { Button("启用记录") { history.enable() }.buttonStyle(.borderedProminent) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            historyRow(row)
                            if row.id != rows.last?.id { Divider().padding(.leading, 16) }
                        }
                    }.padding(.horizontal, 8)
                }
                .accessibilityLabel("剪贴板历史，单击记录复制")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func historyRow(_ row: Row) -> some View {
        HStack(spacing: 4) {
            Button {
                switch row {
                case .text(let entry): controller.copyText(entry.id)
                case .image(let image): controller.copyImage(image.id)
                }
            } label: {
                HStack(spacing: 12) {
                    switch row {
                    case .text(let entry):
                        Image(systemName: "text.alignleft").foregroundStyle(muted).frame(width: 36)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.text.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 13)).lineLimit(2)
                            Text(entry.capturedAt, style: .time).font(.system(size: 11)).foregroundStyle(muted)
                        }
                    case .image(let image):
                        if let thumbnail = NSImage(data: image.thumbnailPNG) {
                            Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 48, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("图片 · \(image.width) × \(image.height)").font(.system(size: 13))
                            Text(image.capturedAt, style: .time).font(.system(size: 11)).foregroundStyle(muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ink).padding(.vertical, 12).padding(.leading, 10)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(ClipboardRowButtonStyle()).help("复制这条历史并收起面板")
            if case .text(let entry) = row {
                Menu {
                    ForEach(ClipboardTextAction.allCases) { action in
                        Button(action.title) { controller.beginProcessing(entry.id, action: action) }
                    }
                } label: { Image(systemName: "text.badge.checkmark").frame(width: 24, height: 32) }
                .menuStyle(.borderlessButton).fixedSize().help("快捷处理文字").accessibilityLabel("快捷处理文字")
                Button { controller.beginEditing(entry.id) } label: { Image(systemName: "pencil").frame(width: 28, height: 32) }
                    .buttonStyle(.plain).help("编辑这条文字").accessibilityLabel("编辑这条文字")
            }
            Button {
                switch row { case .text(let entry): history.delete(entry.id); case .image(let image): history.deleteImage(image.id) }
            } label: { Image(systemName: "trash").frame(width: 28, height: 32) }
                .buttonStyle(.plain).foregroundStyle(muted).help("删除这条历史").accessibilityLabel("删除这条历史")
        }.padding(.trailing, 4)
    }

    private var processingPreview: some View {
        let result = controller.processingResult
        let output = try? result?.get()
        return VStack(alignment: .leading, spacing: 12) {
            Text(controller.textAction.title + " · 预览").font(.headline)
            Text("复制不改动历史；修改记录不写入剪贴板。URL 编码用于单个参数值，解码保留 +。")
                .font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            if case .failure(let error) = result {
                Text(error.localizedDescription).font(.system(size: 12)).foregroundStyle(muted)
            }
            Group {
                if controller.isEditingProcessing {
                    TextEditor(text: $controller.processingDraft)
                        .font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                        .accessibilityLabel("编辑处理结果")
                } else {
                    ScrollView {
                        Text(output ?? controller.processingDraft)
                            .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(10).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxHeight: .infinity)
            HStack {
                Button("返回列表") { controller.cancelProcessing() }
                    .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(muted.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
                if controller.isEditingProcessing {
                    Button("保存到本条记录") { controller.saveProcessed() }.disabled(output == nil)
                        .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
                        .background(muted.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Button("编辑结果") { controller.isEditingProcessing = true }
                        .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
                        .background(muted.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                Button("复制处理结果") { controller.copyProcessed() }
                    .buttonStyle(.borderedProminent).disabled(output == nil)
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $controller.draft).font(.system(size: 13))
                .scrollContentBackground(.hidden).padding(8)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("编辑历史文字")
            HStack {
                Text("\(controller.draft.utf8.count) / 65536 字节").font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                Button("取消") { controller.cancelEditing() }.buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(muted.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                Button("保存修改") { controller.saveEdit() }.buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
            }
            Text("只修改会话历史，保存不会改动系统剪贴板。")
                .font(.system(size: 12)).foregroundStyle(muted)
        }.padding(18)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !controller.status.isEmpty { Text(controller.status).font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 10) {
                Label(history.isEnabled ? "记录中 · 退出清除" : "已暂停 · 退出清除", systemImage: history.isEnabled ? "record.circle" : "pause.circle")
                    .font(.system(size: 11)).foregroundStyle(muted)
                Spacer(minLength: 0)
                Button(history.isEnabled ? "暂停" : "启用记录") { if history.isEnabled { history.pause() } else { history.enable() } }
                Button("管理…") { controller.manage() }
            }.font(.system(size: 12)).buttonStyle(.plain)
        }
    }
}

private struct ClipboardRowButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.07 : 0.001)), in: RoundedRectangle(cornerRadius: 8))
            .onHover { hovering = $0 }
    }
}
