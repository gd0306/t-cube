import AppKit
import SwiftUI
import CubeCore

@MainActor
final class FaceExpansionController {
    private let model: AppModel
    private var panel: ExpandedFacePanel?
    private var localClicks: Any?
    private var globalClicks: Any?

    init(model: AppModel) {
        self.model = model
    }

    func show(face: CubeFace, from view: NSView, rect: NSRect) {
        close()
        guard let source = view.window else { return }
        let anchor = source.convertToScreen(view.convert(rect, to: nil))
        let size = NSSize(width: 220, height: 220)
        let origin = WindowPlacement.clamp(
            NSPoint(x: source.frame.minX - size.width - 12, y: anchor.midY - size.height / 2),
            size: size, screens: NSScreen.screens.map(\.visibleFrame))
        let panel = self.panel ?? ExpandedFacePanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.title = "T-Cube · 入口"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.dismissRequested = { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: ExpandedFaceView(
            model: model, face: face,
            close: { [weak self] in self?.close() }))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: hosting.frame)
            glass.style = .clear
            glass.tintColor = nil
            glass.cornerRadius = 24
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.contentView = hosting
            panel.contentView = glass
        } else {
            let glass = NSVisualEffectView(frame: hosting.frame)
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 24
            glass.layer?.masksToBounds = true
            glass.addSubview(hosting)
            panel.contentView = glass
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClicks = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            self?.dismissIfOutside(event.window) == true ? nil : event
        }
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            // AppKit invokes mouse event monitors on the application's main thread.
            MainActor.assumeIsolated { _ = self?.dismissIfOutside(nil) }
        }
    }

    @discardableResult func dismissIfOutside(_ window: NSWindow?) -> Bool {
        guard let panel, panel.isVisible, window !== panel else { return false }
        close()
        return true
    }

    func close() {
        if let localClicks { NSEvent.removeMonitor(localClicks) }
        if let globalClicks { NSEvent.removeMonitor(globalClicks) }
        localClicks = nil
        globalClicks = nil
        panel?.orderOut(nil)
    }
}

private final class ExpandedFacePanel: NSPanel {
    var dismissRequested: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismissRequested?() }
}

private struct ExpandedFaceView: View {
    @ObservedObject var model: AppModel
    let face: CubeFace
    let close: () -> Void
    private var group: FaceGroup { model.configuration.group(for: face) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(0..<4) { slot in
                if let item = group.slots[slot] {
                    Button {
                        close()
                        model.launch(slot: slot, face: face)
                    } label: {
                        Image(nsImage: LauncherService.icon(for: item)).resizable()
                            .frame(width: 64, height: 64)
                            .frame(maxWidth: .infinity).frame(height: 88)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开\(item.name)")
                } else {
                    Color.clear.frame(height: 88).accessibilityHidden(true)
                }
            }
        }
        .padding(16).frame(width: 220, height: 220)
        .onExitCommand(perform: close)
    }
}
