import AppKit
import CubeCore

@MainActor
enum LauncherTargetPicker {
    static func chooseKind(replacing: Bool, current: LauncherItem.Kind?) -> LauncherItem.Kind? {
        let alert = NSAlert()
        alert.messageText = replacing ? "重新选择入口目标" : "添加入口"
        alert.informativeText = "选择入口类型。"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        popup.addItems(withTitles: LauncherItem.Kind.allCases.map(\.title))
        if let current, let index = LauncherItem.Kind.allCases.firstIndex(of: current) { popup.selectItem(at: index) }
        popup.setAccessibilityLabel("入口类型")
        alert.accessoryView = popup
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return LauncherItem.Kind.allCases[popup.indexOfSelectedItem]
    }

    static func website(current: LauncherItem?) -> LauncherItem? {
        let alert = NSAlert()
        alert.messageText = "网页入口"
        alert.informativeText = "输入名称与完整的 HTTP 或 HTTPS 网址。"
        let title = NSTextField(string: current?.kind == .website ? current!.name : "")
        title.placeholderString = "名称，例如：项目文档"
        title.setAccessibilityLabel("网页名称")
        let address = NSTextField(string: current?.kind == .website ? current!.url.absoluteString : "")
        address.placeholderString = "https://example.com"
        address.setAccessibilityLabel("网页网址")
        let stack = NSStackView(views: [NSTextField(labelWithString: "名称"), title,
                                         NSTextField(labelWithString: "网址"), address])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 110)
        for field in [title, address] { field.widthAnchor.constraint(equalToConstant: 340).isActive = true }
        alert.accessoryView = stack
        alert.addButton(withTitle: "保存入口")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = title
        while alert.runModal() == .alertFirstButtonReturn {
            do { return try WebsiteTarget.item(title: title.stringValue, address: address.stringValue) }
            catch { alert.informativeText = error.localizedDescription }
        }
        return nil
    }

    static func settings(current: LauncherItem?) -> LauncherItem? {
        let alert = NSAlert()
        alert.messageText = "系统设置入口"
        alert.informativeText = "选择要打开的系统设置页面。"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        popup.addItems(withTitles: SystemSettingsTarget.allCases.map(\.title))
        if let current, let index = SystemSettingsTarget.allCases.firstIndex(where: { $0.url == current.url }) {
            popup.selectItem(at: index)
        }
        popup.setAccessibilityLabel("系统设置页面")
        alert.accessoryView = popup
        alert.addButton(withTitle: "保存入口")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return SystemSettingsTarget.allCases[popup.indexOfSelectedItem].item
    }
}
