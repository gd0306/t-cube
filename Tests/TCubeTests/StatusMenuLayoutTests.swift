import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
private final class MenuActionRecorder: NSObject {
    var calls: [String] = []
    @objc func recordMenuCommand(_ sender: NSMenuItem) { calls.append(sender.title) }
}

@MainActor
struct StatusMenuLayoutTests {
    private func makeMenu(_ target: MenuActionRecorder, place: @escaping (CubePlacement) -> Void = { _ in }) -> NSMenu {
        let action = #selector(MenuActionRecorder.recordMenuCommand(_:))
        return StatusMenuLayout.make(target: target, actions: .init(
            toggleCube: action, contentLibrary: action, clipboardHistory: action,
            pauseClipboard: action, settings: action, checkUpdates: action, changeSize: action, quit: action),
            placementMenu: CubePlacementMenu(selection: place))
    }

    @Test func contentShortcutUsesNativeModifiersAndDispatchesToItsOwner() throws {
        _ = NSApplication.shared
        let target = MenuActionRecorder()
        let menu = makeMenu(target)
        let item = try #require(menu.item(withTitle: "常用内容…"))
        #expect(item.keyEquivalent == " " && item.keyEquivalentModifierMask == [.command, .shift])
        guard let action = item.action else { Issue.record("Content action is missing"); return }
        #expect(NSStringFromSelector(action) == "recordMenuCommand:")
        let dispatched = NSApp.sendAction(action, to: item.target, from: item)
        #expect(dispatched)
        #expect(target.calls == ["常用内容…"])
    }

    @Test func nestedLayoutKeepsPlacementRoutingAndRefreshesSizeCheckmarks() throws {
        _ = NSApplication.shared
        let target = MenuActionRecorder()
        var placed: CubePlacement?
        let menu = makeMenu(target) { placed = $0 }
        let layout = try #require(menu.item(withTitle: "立方体布局")?.submenu)
        let placements = try #require(layout.item(withTitle: "快捷位置")?.submenu)
        let position = try #require(placements.items.first)
        guard let placementAction = position.action else { Issue.record("Placement action is missing"); return }
        let placementDispatched = NSApp.sendAction(placementAction, to: position.target, from: position)
        #expect(placementDispatched)
        #expect(placed == .topLeft)
        let sizes = try #require(layout.item(withTitle: "尺寸")?.submenu)
        StatusMenuLayout.updateSizeSelection(in: menu, scale: 0.8)
        #expect(sizes.items.filter { $0.state == .on }.map { $0.representedObject as? Double } == [0.8])
        StatusMenuLayout.updateSizeSelection(in: menu, scale: 1.2)
        #expect(sizes.items.filter { $0.state == .on }.map { $0.representedObject as? Double } == [1.2])
        let size = try #require(sizes.items.last)
        guard let sizeAction = size.action else { Issue.record("Size action is missing"); return }
        let sizeDispatched = NSApp.sendAction(sizeAction, to: size.target, from: size)
        #expect(sizeDispatched)
        #expect(target.calls == ["舒适"])
    }
}
