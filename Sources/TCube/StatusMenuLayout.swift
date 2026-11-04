import AppKit

struct StatusMenuActions {
    let toggleCube: Selector
    let contentLibrary: Selector
    let clipboardHistory: Selector
    let pauseClipboard: Selector
    let settings: Selector
    let checkUpdates: Selector
    let changeSize: Selector
    let quit: Selector
}

@MainActor
enum StatusMenuLayout {
    private static let layoutID = NSUserInterfaceItemIdentifier("TCube.layout")
    private static let sizeID = NSUserInterfaceItemIdentifier("TCube.size")

    static func make(target: AnyObject, actions: StatusMenuActions, placementMenu: NSMenu) -> NSMenu {
        let menu = NSMenu()
        func command(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            return item
        }
        menu.addItem(command("隐藏立方体", actions.toggleCube))
        let layout = NSMenuItem(title: "立方体布局", action: nil, keyEquivalent: "")
        layout.identifier = layoutID
        let layoutMenu = NSMenu(title: layout.title)
        let placement = NSMenuItem(title: "快捷位置", action: nil, keyEquivalent: "")
        placement.submenu = placementMenu
        layoutMenu.addItem(placement)
        let size = NSMenuItem(title: "尺寸", action: nil, keyEquivalent: "")
        size.identifier = sizeID
        let sizeMenu = NSMenu(title: size.title)
        for (title, scale) in [("迷你", 0.8), ("小巧", 1.0), ("舒适", 1.2)] {
            let option = command(title, actions.changeSize)
            option.representedObject = scale
            sizeMenu.addItem(option)
        }
        size.submenu = sizeMenu
        layoutMenu.addItem(size)
        layout.submenu = layoutMenu
        menu.addItem(layout)
        menu.addItem(.separator())

        let content = command("常用内容…", actions.contentLibrary, key: " ")
        content.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(content)
        menu.addItem(command("剪贴板历史…", actions.clipboardHistory))
        menu.addItem(command("暂停剪贴板记录", actions.pauseClipboard))
        menu.addItem(.separator())

        menu.addItem(command("设置…", actions.settings, key: ","))
        menu.addItem(command("检查更新…", actions.checkUpdates))
        let help = NSMenuItem(title: "操作说明", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: help.title)
        for text in ["左键拖动：移动立方体", "右键拖动或滚动：旋转立方体", "点击：按设置展开入口或打开目标", "按住 Ctrl：恢复原大小"] {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            helpMenu.addItem(item)
        }
        help.submenu = helpMenu
        menu.addItem(help)
        menu.addItem(.separator())
        menu.addItem(command("退出 T-Cube", actions.quit, key: "q"))
        return menu
    }

    static func updateSizeSelection(in menu: NSMenu, scale: Double) {
        let layout = menu.items.first { $0.identifier == layoutID }?.submenu
        let sizes = layout?.items.first { $0.identifier == sizeID }?.submenu
        for item in sizes?.items ?? [] {
            item.state = (item.representedObject as? Double) == scale ? .on : .off
        }
    }
}
