import AppKit
import SwiftUI
import ApplicationServices
import Carbon

struct PasteEligibility {
    static func allows(target: pid_t?, frontmost: pid_t?, own: pid_t, trusted: Bool, sameField: Bool) -> Bool {
        trusted && sameField && target != nil && target != own && target == frontmost
    }
}

final class SnippetPanel: NSPanel {
    var dismissed: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismissed?() }
}

@MainActor
final class SnippetLibraryController {
    let model = SnippetLibraryModel()
    private var panel: SnippetPanel?
    private var target: NSRunningApplication?
    private var targetField: AXUIElement?
    private var lastExternal: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var pasteTask: Task<Void, Never>?

    init() {
        rememberExternal()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rememberExternal() }
        }
    }

    private func rememberExternal() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternal = app
        }
    }

    func start() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var received = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &received) == noErr, received.signature == 0x54435542, received.id == 1 else { return OSStatus(eventNotHandledErr) }
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<SnippetLibraryController>.fromOpaque(context).takeUnretainedValue().toggle()
            }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { model.status = "快捷键注册失败，请从菜单打开常用内容。"; return }
        let id = EventHotKeyID(signature: 0x54435542, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { model.status = "⌘⇧Space 已被占用，请从菜单或立方体打开。" }
    }

    func stop() {
        pasteTask?.cancel()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        hotKey = nil; handler = nil
    }

    func toggle() {
        if panel?.isVisible == true { dismiss() }
        else { show() }
    }

    func dismiss() {
        panel?.orderOut(nil)
        if let target, !target.isTerminated { target.activate(options: []) }
    }

    func capture(_ text: String) {
        model.pendingCapture = text
        show()
    }

    func show() {
        pasteTask?.cancel()
        if panel?.isVisible != true {
            rememberExternal()
            target = lastExternal
            targetField = target.flatMap { focusedField(pid: $0.processIdentifier) }
        }
        if panel == nil {
            let window = SnippetPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "T-Cube · 常用内容"
            window.dismissed = { [weak self] in self?.dismiss() }
            window.minSize = NSSize(width: 800, height: 560)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: VStack(spacing: 0) {
                SnippetLibraryView(model: model) { [weak self] text, paste in self?.use(text, paste: paste) }
                Divider()
                HStack {
                    Text("⌘⇧Space 呼出 · Esc 收起 · 内容仅保存在本机")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("允许直接粘贴…") { [weak self] in self?.requestPasteAccess() }
                        .font(.caption)
                }.padding(10)
            })
            panel = window
        }
        if let panel, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let mouse = NSEvent.mouseLocation
            let origin = NSPoint(x: max(visible.minX, min(mouse.x - panel.frame.width / 2, visible.maxX - panel.frame.width)), y: max(visible.minY, min(mouse.y - panel.frame.height / 2, visible.maxY - panel.frame.height)))
            panel.setFrameOrigin(origin)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: Notification.Name("TCubeSnippetSearchFocus"), object: nil)
    }

    func requestPasteAccess() {
        let key = "AXTrustedCheckOptionPrompt"
        if AXIsProcessTrustedWithOptions([key: true] as CFDictionary) {
            model.status = "已允许直接粘贴。请回到输入框，再用 ⌘⇧Space 呼出。"
        } else {
            model.status = "请在系统设置 → 隐私与安全性 → 辅助功能中允许 T-Cube，然后重新呼出内容库。复制功能可直接使用。"
        }
    }

    private func focusedField(pid: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String, ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else { return nil }
        return element
    }

    func use(_ text: String, paste: Bool) {
        guard !text.isEmpty else { return }
        pasteTask?.cancel()
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { model.status = "无法写入剪贴板，请重试。"; return }
        model.status = "已复制"
        guard paste else { return }
        guard AXIsProcessTrusted() else { requestPasteAccess(); return }
        guard let target, !target.isTerminated, let originalField = targetField else {
            model.status = "已复制。请先点中目标输入框，再按 ⌘⇧Space 呼出后粘贴。"; return
        }
        let changeCount = NSPasteboard.general.changeCount
        panel?.orderOut(nil)
        target.activate(options: [])
        pasteTask = Task { [weak self] in
            for _ in 0..<20 {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                let pid = target.processIdentifier
                let focused = self.focusedField(pid: pid)
                if PasteEligibility.allows(target: pid, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                    own: ProcessInfo.processInfo.processIdentifier, trusted: AXIsProcessTrusted(),
                    sameField: focused.map { CFEqual($0, originalField) } ?? false),
                    !target.isTerminated, NSPasteboard.general.changeCount == changeCount {
                    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                          let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { break }
                    down.flags = .maskCommand; up.flags = .maskCommand
                    down.postToPid(pid); up.postToPid(pid)
                    self.model.status = "已向原输入位置发送粘贴"
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.model.status = "原输入位置已变化，内容已复制，可手动粘贴。"
        }
    }
}
