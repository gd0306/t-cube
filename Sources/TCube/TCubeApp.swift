import AppKit
import SwiftUI
import CubeCore

@main
enum TCubeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class CubePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var panel: CubePanel!
    private var cubeView: CubeView!
    private var surface: CubeSurfaceView!
    private var faceExpansion: FaceExpansionController!
    private var hoverController: CubeHoverController?
    private var statusItem: NSStatusItem!
    private var editor: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private let snippetLibrary = SnippetLibraryController()
    private let lifecycle = LifecycleController()
    private let performanceSettings = PerformanceSettings()
    private var desktopPlacement: DesktopPlacementCoordinator?
    private var accessibilityObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.recoverIfNeeded()
        cubeView = CubeView(model: model)
        surface = CubeSurfaceView(cubeView: cubeView)
        surface.contentCaptureRequested = { [weak self] text in self?.snippetLibrary.capture(text) }
        panel = CubePanel(contentRect: NSRect(origin: .zero, size: CubeTheme.windowSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "T-Cube"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = surface
        surface.autoresizingMask = [.width, .height]
        cubeView.editRequested = { [weak self] in self?.showEditor() }
        faceExpansion = FaceExpansionController(model: model)
        cubeView.faceRequested = { [weak self] face, rect in
            guard let self else { return }
            self.faceExpansion.show(face: face, from: self.cubeView, rect: rect)
        }
        cubeView.launchRequested = { [weak self] slot, face in self?.model.launch(slot: slot, face: face) }
        model.onChange = { [weak self, weak surface] in
            self?.cubeView.refreshTextures()
            self?.applySize()
            if let self { surface?.input.updateInteractionHelp(expandsFaces: self.model.configuration.expandsFacesOnClick) }
        }
        model.onAppearanceChange = { [weak self] in self?.cubeView.refreshAppearance() }
        applySize(restoring: true)
        let hover = CubeHoverController(window: panel, settings: model.configuration.hover)
        hoverController = hover
        model.onPlacementRequested = { [weak self] in self?.placeCube(at: $0) }
        model.onConfigurationRestored = { [weak self] in
            guard let self, let hover = self.hoverController else { return }
            if let position = self.model.configuration.windowPosition {
                hover.restoreRestingFrame(at: NSPoint(x: position.x, y: position.y))
                do { try self.desktopPlacement?.recordRestingPosition() }
                catch { self.model.report(error) }
            }
            self.surface.synchronizeRenderingVisibility()
        }
        hover.onHoverChange = { [weak self] in self?.cubeView.setHovered($0) }
        hover.onRestingPositionChange = { [weak self] in self?.model.savePosition($0) }
        hover.onRestingFrameCommitted = { [weak self] in
            do { try self?.desktopPlacement?.recordRestingPosition() }
            catch { self?.model.report(error) }
        }
        do { desktopPlacement = try DesktopPlacementCoordinator(hoverController: hover, panel: panel) }
        catch { model.report(error) }
        surface.input.hoverChanged = { [weak hover] _ in hover?.checkPointer() }
        surface.input.hoverPointChanged = { [weak hover] in hover?.pointerChanged(to: $0) }
        surface.input.modifierFlagsChanged = { [weak hover] in hover?.modifierFlagsChanged($0, at: $1) }
        cubeView.interactionChanged = { [weak hover] active in
            if !active { hover?.checkPointer() }
            hover?.setInteractionActive(active)
        }
        cubeView.positionCommitted = { [weak hover] in hover?.commitMovedFrame($0) }
        cubeView.idlePowerSavingEnabled = performanceSettings.idlePowerSavingEnabled
        performanceSettings.onChange = { [weak self] enabled in self?.cubeView.idlePowerSavingEnabled = enabled }
        surface.enableRenderingManagement()
        panel.orderFrontRegardless()
        surface.synchronizeRenderingVisibility()
        hover.startTrackingPointer()
        createMenu()
        snippetLibrary.start()
        lifecycle.start()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.surface.resumeRendering() }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySize()
                self?.desktopPlacement?.screenTopologyChanged()
                self?.surface.synchronizeRenderingVisibility()
            }
        }
        if model.isFirstLaunch { showEditor() }
        if ProcessInfo.processInfo.arguments.contains("--content-library") { snippetLibrary.show() }
    }

    private func applySize(restoring: Bool = false) {
        let size = NSSize(width: CubeTheme.windowSize.width * model.configuration.scale, height: CubeTheme.windowSize.height * model.configuration.scale)
        if let hoverController {
            hoverController.configure(baseSize: size, settings: model.configuration.hover)
            return
        }
        var origin = panel.frame.origin
        if restoring {
            if let stored = model.configuration.windowPosition { origin = NSPoint(x: stored.x, y: stored.y) }
            else if let visible = NSScreen.main?.visibleFrame { origin = NSPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 35) }
        } else {
            origin.x += (panel.frame.width - size.width) / 2
            origin.y += (panel.frame.height - size.height) / 2
        }
        origin = WindowPlacement.clamp(origin, size: size, screens: NSScreen.screens.map(\.visibleFrame))
        let frame = NSRect(origin: origin, size: size)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            if !restoring { model.savePosition(origin) }
        }
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "T-Cube.StatusItem"
        let icon = NSImage(systemSymbolName: "cube.transparent", accessibilityDescription: "T-Cube") ?? NSImage(systemSymbolName: "cube", accessibilityDescription: "T-Cube")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = icon
        statusItem.button?.setAccessibilityLabel("T-Cube 菜单")
        statusItem.button?.toolTip = "T-Cube · 桌面立方体启动器"
        let menu = NSMenu()
        menu.delegate = self
        func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; menu.addItem(item); return item
        }
        _ = item("隐藏立方体", #selector(toggleCube))
        _ = item("常用内容…    ⌘⇧Space", #selector(openContentLibrary))
        _ = item("剪贴板历史…", #selector(openClipboardHistory))
        _ = item("暂停剪贴板记录", #selector(pauseClipboardHistory))
        _ = item("设置…", #selector(openEditor), key: ",")
        _ = item("检查更新…", #selector(checkUpdates))
        let placement = NSMenuItem(title: "快捷位置", action: nil, keyEquivalent: "")
        placement.submenu = CubePlacementMenu { [weak self] in self?.placeCube(at: $0) }
        menu.addItem(placement)
        menu.addItem(.separator())
        let size = NSMenuItem(title: "尺寸", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, scale) in [("迷你", 0.8), ("小巧", 1.0), ("舒适", 1.2)] {
            let option = NSMenuItem(title: title, action: #selector(changeSize(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = scale
            submenu.addItem(option)
        }
        size.submenu = submenu; menu.addItem(size)
        let help = NSMenuItem(title: "左键移动 · 右键旋转 · 滚动旋转 · 点击使用入口", action: nil, keyEquivalent: "")
        menu.addItem(help)
        menu.addItem(.separator())
        _ = item("退出 T-Cube", #selector(quit), key: "q")
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "T-Cube")
        appMenu.delegate = self
        let contentItem = NSMenuItem(title: "常用内容…", action: #selector(openContentLibrary), keyEquivalent: " ")
        contentItem.keyEquivalentModifierMask = [.command, .shift]
        contentItem.target = self
        appMenu.addItem(contentItem)
        let historyItem = NSMenuItem(title: "剪贴板历史…", action: #selector(openClipboardHistory), keyEquivalent: "")
        historyItem.target = self
        appMenu.addItem(historyItem)
        let pauseHistoryItem = NSMenuItem(title: "暂停剪贴板记录", action: #selector(pauseClipboardHistory), keyEquivalent: "")
        pauseHistoryItem.target = self
        appMenu.addItem(pauseHistoryItem)
        let settings = NSMenuItem(title: "设置…", action: #selector(openEditor), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 T-Cube", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(toggleCube) })?.title = panel.isVisible ? "隐藏立方体" : "显示立方体"
        menu.items.first(where: { $0.action == #selector(openClipboardHistory) })?.title =
            snippetLibrary.history.isEnabled ? "剪贴板历史…（记录中）" : "剪贴板历史…"
        menu.items.first(where: { $0.action == #selector(pauseClipboardHistory) })?.isHidden = !snippetLibrary.history.isEnabled
        if let options = menu.items.first(where: { $0.title == "尺寸" })?.submenu?.items {
            for item in options { item.state = (item.representedObject as? Double) == model.configuration.scale ? .on : .off }
        }
    }
    @objc private func toggleCube() {
        faceExpansion.close()
        if panel.isVisible { hoverController?.resetHover(); cubeView.setHovered(false); panel.orderOut(nil) }
        else { panel.ignoresMouseEvents = false; panel.orderFrontRegardless(); hoverController?.checkPointer() }
        surface.synchronizeRenderingVisibility()
    }
    @objc private func changeSize(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Double else { return }
        model.change { $0.scale = scale }
    }
    @objc private func openContentLibrary() { snippetLibrary.show() }
    @objc private func openClipboardHistory() { snippetLibrary.showHistory() }
    @objc private func pauseClipboardHistory() { snippetLibrary.history.pause() }
    @objc private func checkUpdates() { lifecycle.checkForUpdates() }
    @objc private func openEditor() { showEditor() }

    private func placeCube(at placement: CubePlacement) {
        faceExpansion.close()
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        hoverController?.place(at: placement)
        hoverController?.checkPointer()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        snippetLibrary.stop()
        model.stopThemeCycle()
        cubeView.suspendAnimationUpdates()
        hoverController?.stopTrackingPointer()
        faceExpansion?.close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    private func showEditor() {
        faceExpansion?.close()
        if editor == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "T-Cube · 设置"
            window.minSize = NSSize(width: 760, height: 540)
            window.contentView = NSHostingView(rootView: EditorView(model: model, lifecycle: lifecycle, performance: performanceSettings))
            window.isReleasedWhenClosed = false
            window.center()
            editor = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editor?.makeKeyAndOrderFront(nil)
    }
}
