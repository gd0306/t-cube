import AppKit
import Combine
import CubeCore
import SwiftUI

final class ClipboardQuickPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

private final class ClipboardQuickHostingView: NSHostingView<ClipboardQuickView> {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rootView.controller.isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

@MainActor
final class ClipboardQuickController: ObservableObject {
    let history: ClipboardHistoryModel
    @Published var query = ""
    @Published var draft = ""
    @Published var isDark = false
    @Published private(set) var editingID: UUID?
    @Published private(set) var status = ""
    private(set) var panel: ClipboardQuickPanel?
    private var hostingView: NSView?
    private let writeText: (String) -> Bool
    private let writeImage: (ClipboardHistoryImage) -> Bool
    private let openManager: () -> Void
    private var localClicks: Any?
    private var globalClicks: Any?
    private var activationObserver: NSObjectProtocol?
    private var entriesSubscription: AnyCancellable?
    var isVisible: Bool { panel?.isVisible == true }

    init(history: ClipboardHistoryModel, copyText: @escaping (String) -> Bool,
         copyImage: @escaping (ClipboardHistoryImage) -> Bool, openManager: @escaping () -> Void) {
        self.history = history
        writeText = copyText; writeImage = copyImage; self.openManager = openManager
        entriesSubscription = history.$entries.sink { [weak self] entries in
            guard let self, let editingID = self.editingID, !entries.contains(where: { $0.id == editingID }) else { return }
            self.cancelEditing()
            self.status = "正在编辑的记录已删除。"
        }
    }

    func show(at point: NSPoint = NSEvent.mouseLocation, visibleScreens: [NSRect] = NSScreen.screens.map(\.visibleFrame)) {
        guard !isVisible else { return }
        if panel == nil {
            let window = ClipboardQuickPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "T-Cube · 剪贴板快捷历史"
            window.isReleasedWhenClosed = false
            window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = true; window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.escape = { [weak self] in self?.handleEscape() }
            let hosting = ClipboardQuickHostingView(rootView: ClipboardQuickView(controller: self, history: history))
            hostingView = hosting
            hosting.autoresizingMask = [.width, .height]
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.style = .clear; glass.cornerRadius = 20
                glass.contentView = hosting
                window.contentView = glass
            } else {
                let glass = NSVisualEffectView()
                glass.material = .popover; glass.blendingMode = .behindWindow; glass.state = .active
                glass.wantsLayer = true; glass.layer?.cornerRadius = 20; glass.layer?.masksToBounds = true
                glass.addSubview(hosting)
                window.contentView = glass
            }
            panel = window
        }
        guard let panel, let screen = visibleScreens.first(where: { $0.contains(point) }) ?? visibleScreens.first else { return }
        let size = NSSize(width: min(420, screen.width), height: min(540, screen.height))
        let origin = NSPoint(x: max(screen.minX, min(point.x - size.width / 2, screen.maxX - size.width)),
                             y: max(screen.minY, min(point.y - size.height + 24, screen.maxY - size.height)))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        hostingView?.frame = NSRect(origin: .zero, size: size)
        if editingID == nil { query = ""; status = "" }
        panel.makeKeyAndOrderFront(nil)
        installDismissalObservers()
    }

    func dismiss() {
        panel?.orderOut(nil)
        if let localClicks { NSEvent.removeMonitor(localClicks) }
        if let globalClicks { NSEvent.removeMonitor(globalClicks) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        localClicks = nil; globalClicks = nil; activationObserver = nil
    }

    @discardableResult func dismissIfOutside(_ window: NSWindow?) -> Bool {
        guard isVisible, window !== panel else { return false }
        dismiss(); return true
    }

    func stop() {
        dismiss(); cancelEditing()
        panel?.contentView = nil; panel = nil; hostingView = nil
    }

    func manage() { dismiss(); openManager() }
    func handleEscape() { if editingID != nil { cancelEditing() } else { dismiss() } }

    @discardableResult func copyText(_ id: UUID) -> Bool {
        guard let entry = history.entries.first(where: { $0.id == id }) else { status = "这条记录已删除，请选择其他内容。"; return false }
        guard writeText(entry.text) else { status = "复制失败，请重试。"; return false }
        dismiss(); return true
    }

    @discardableResult func copyImage(_ id: UUID) -> Bool {
        guard let image = history.images.first(where: { $0.id == id }) else { status = "这张图片已删除，请选择其他内容。"; return false }
        guard writeImage(image) else { status = "图片复制失败，请重试。"; return false }
        dismiss(); return true
    }

    @discardableResult func beginEditing(_ id: UUID) -> Bool {
        guard let entry = history.entries.first(where: { $0.id == id }) else { return false }
        editingID = id; draft = entry.text; status = ""
        return true
    }

    @discardableResult func saveEdit() -> Bool {
        guard let editingID, history.updateText(id: editingID, text: draft) else { status = history.status; return false }
        cancelEditing(); status = "已保存修改，点击记录即可复制。"
        return true
    }

    func cancelEditing() { editingID = nil; draft = ""; status = "" }

    private func installDismissalObservers() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClicks = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.dismissIfOutside(event.window); return event
        }
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.dismissIfOutside(nil) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.dismiss() }
            }
        }
    }
}
