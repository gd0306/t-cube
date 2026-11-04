import AppKit
import ColorSync
import CubeCore

@MainActor
final class DisplayBrightnessMenuRow: NSView {
    private let name = NSTextField(labelWithString: "")
    private let percentage = NSTextField(labelWithString: "—")
    private let detail = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let change: (String, Double) -> Void
    private var uuid: String

    init(state: DisplayBrightnessRow, change: @escaping (String, Double) -> Void) {
        self.change = change; uuid = state.id
        super.init(frame: CGRect(x: 0, y: 0, width: 288, height: 72))
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        percentage.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percentage.alignment = .right
        detail.font = .systemFont(ofSize: 10)
        detail.lineBreakMode = .byTruncatingTail
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self; slider.action = #selector(changed)
        [icon, name, percentage, slider, detail].forEach(addSubview)
        apply(state)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        icon.frame = CGRect(x: 15, y: 47, width: 16, height: 16)
        name.frame = CGRect(x: 40, y: 46, width: bounds.width - 100, height: 17)
        percentage.frame = CGRect(x: bounds.width - 58, y: 46, width: 42, height: 16)
        slider.frame = CGRect(x: 38, y: 22, width: bounds.width - 54, height: 20)
        detail.frame = CGRect(x: 40, y: 5, width: bounds.width - 56, height: 14)
    }

    func apply(_ state: DisplayBrightnessRow) {
        uuid = state.id
        name.stringValue = state.target.name; name.toolTip = state.target.name
        name.textColor = .labelColor
        icon.image = NSImage(systemSymbolName: state.target.isBuiltIn ? "laptopcomputer" : "display", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        let fraction = state.fraction.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
        slider.isEnabled = state.isEnabled && fraction != nil
        if let fraction { slider.doubleValue = fraction * 100 }
        percentage.stringValue = fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        percentage.textColor = slider.isEnabled ? .labelColor : .secondaryLabelColor
        detail.stringValue = state.message ?? (state.isLoading ? "正在读取…" : state.isWriting ? "正在调节…" : "")
        detail.textColor = state.message != nil && state.isEnabled ? .systemRed : .secondaryLabelColor
        detail.toolTip = state.message
        slider.toolTip = state.message ?? "调节 \(state.target.name) 的亮度"
        slider.setAccessibilityLabel("\(state.target.name) 亮度")
        slider.setAccessibilityHelp(detail.stringValue)
        needsLayout = true
    }

    @objc private func changed() {
        guard slider.isEnabled, slider.doubleValue.isFinite else { return }
        percentage.stringValue = "\(Int(slider.doubleValue.rounded()))%"
        change(uuid, slider.doubleValue / 100)
    }
}

/// A small native section in the existing status menu; it owns no timer/window.
@MainActor
final class DisplayBrightnessMenu {
    let controller: DisplayBrightnessController
    private weak var menu: NSMenu?
    private var items: [NSMenuItem] = []
    private var views: [String: DisplayBrightnessMenuRow] = [:]
    private var observer: NSObjectProtocol?

    init(menu: NSMenu, controller: DisplayBrightnessController? = nil) {
        self.menu = menu
        self.controller = controller ?? DisplayBrightnessController(hardware: NativeDisplayBrightnessHardware(), targets: Self.connectedDisplays)
        self.controller.onChange = { [weak self] in self?.render() }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller.screenParametersChanged() }
            }
        render()
    }

    func beginTracking() { controller.beginTracking() }
    func endTracking() { controller.endTracking() }

    private func render() {
        guard let menu else { return }
        let rows = controller.rows
        if !rows.isEmpty, Set(views.keys) == Set(rows.map(\.id)) {
            for row in rows { views[row.id]?.apply(row) }
            return
        }
        for item in items where menu.index(of: item) >= 0 { menu.removeItem(item) }
        items.removeAll(); views.removeAll()
        let header = NSMenuItem(title: "显示器亮度", action: nil, keyEquivalent: "")
        header.isEnabled = false; items.append(header)
        if rows.isEmpty {
            let empty = NSMenuItem(title: controller.isMenuOpen ? "未检测到显示器" : "正在读取显示器…", action: nil, keyEquivalent: "")
            empty.isEnabled = false; items.append(empty)
        } else {
            for row in rows {
                let item = NSMenuItem()
                let view = DisplayBrightnessMenuRow(state: row) { [weak self] uuid, fraction in
                    self?.controller.setFraction(fraction, for: uuid)
                }
                item.view = view; items.append(item); views[row.id] = view
            }
        }
        items.append(.separator())
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
    }

    static func connectedDisplays() -> [DisplayBrightnessTarget] {
        let names = Dictionary(NSScreen.screens.compactMap { screen -> (UInt32, String)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (id.uint32Value, screen.localizedName)
        }, uniquingKeysWith: { first, _ in first })
        var ids = [CGDirectDisplayID](repeating: 0, count: 64), count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
            let identity = uuid.map { CFUUIDCreateString(kCFAllocatorDefault, $0) as String } ?? "unsupported:\(id)"
            let builtIn = CGDisplayIsBuiltin(id) != 0
            return .init(id: id, uuid: identity, name: names[id] ?? (builtIn ? "内建显示器" : "显示器 \(id)"), isBuiltIn: builtIn)
        }.sorted { first, second in
            if first.isBuiltIn != second.isBuiltIn { return first.isBuiltIn }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; controller.stop()
        if let menu { for item in items where menu.index(of: item) >= 0 { menu.removeItem(item) } }
        items.removeAll(); views.removeAll()
    }
}
