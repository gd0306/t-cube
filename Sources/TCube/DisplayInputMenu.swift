import AppKit
import CubeCore

@MainActor final class DisplayInputMenuRow: NSView {
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let sourceSwitch = NSSegmentedControl(labels: ["Type-C", "HDMI"], trackingMode: .selectOne, target: nil, action: nil)
    private let setup = NSButton(title: "设置…", target: nil, action: nil)
    private let refresh = NSButton(title: "刷新", target: nil, action: nil)
    private var row: DisplayInputRow
    private let change: (String, DisplayInputSource) -> Void
    private let configure: (DisplayInputRow) -> Void
    private let reload: () -> Void
    init(row: DisplayInputRow, change: @escaping (String, DisplayInputSource) -> Void, configure: @escaping (DisplayInputRow) -> Void, reload: @escaping () -> Void) {
        self.row = row; self.change = change; self.configure = configure; self.reload = reload
        super.init(frame: CGRect(x: 0, y: 0, width: 288, height: 92))
        name.font = .systemFont(ofSize: 12, weight: .medium); name.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
        sourceSwitch.segmentStyle = .capsule; sourceSwitch.segmentDistribution = .fillEqually
        sourceSwitch.font = .systemFont(ofSize: 12, weight: .medium)
        sourceSwitch.target = self; sourceSwitch.action = #selector(changed)
        setup.bezelStyle = .inline; setup.controlSize = .small; setup.target = self; setup.action = #selector(openSetup)
        refresh.bezelStyle = .inline; refresh.controlSize = .small; refresh.target = self; refresh.action = #selector(doRefresh)
        [name, detail, sourceSwitch, setup, refresh].forEach(addSubview); apply(row)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        name.frame = NSRect(x: 16, y: 69, width: 160, height: 17)
        setup.frame = NSRect(x: 224, y: 67, width: 50, height: 20)
        refresh.frame = NSRect(x: 178, y: 67, width: 42, height: 20)
        sourceSwitch.frame = NSRect(x: 16, y: 35, width: 258, height: 27)
        detail.frame = NSRect(x: 16, y: 10, width: 258, height: 18)
    }
    func apply(_ row: DisplayInputRow) {
        self.row = row; name.stringValue = "\(row.target.name) · \(row.target.id)"
        name.toolTip = "\(row.target.name)\n显示器 ID：\(row.target.id)\nUUID：\(row.target.uuid)"
        let activeSource = row.current.flatMap { row.mapping?.source(for: $0) }
        sourceSwitch.isEnabled = row.enabled
        sourceSwitch.selectedSegment = activeSource.map { $0 == .typeC ? 0 : 1 } ?? -1
        let currentText = activeSource.map { $0 == .typeC ? "当前：Type-C" : "当前：HDMI" } ?? row.current.map { "当前输入代码：\($0)" } ?? "不可用"
        detail.stringValue = row.message ?? (row.busy ? "正在读取…" : currentText)
        detail.toolTip = detail.stringValue; setup.isEnabled = row.canConfigure; refresh.isEnabled = !row.busy
        sourceSwitch.setAccessibilityLabel("\(row.target.name) 输入源")
        let source = row.current.flatMap { row.mapping?.source(for: $0) }.map { $0 == .typeC ? "Type-C" : "HDMI" } ?? "未知"
        sourceSwitch.setAccessibilityHelp("当前输入：\(source)。\(detail.stringValue)")
    }
    @objc private func changed() {
        let selected = sourceSwitch.selectedSegment
        // Native selection is a request. Keep the confirmed source highlighted
        // until the controller publishes readback, including while disabled.
        apply(row)
        guard row.enabled, selected == 0 || selected == 1 else { return }
        let source: DisplayInputSource = selected == 0 ? .typeC : .hdmi
        guard row.current.flatMap({ row.mapping?.source(for: $0) }) != source else { return }
        change(row.id, source)
    }
    @objc private func openSetup() {
        let selected = row
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [configure] in configure(selected) }
    }
    @objc private func doRefresh() { reload() }
}

@MainActor final class DisplayInputMenu: NSObject {
    let controller: DisplayInputController
    private weak var menu: NSMenu?
    private var items: [NSMenuItem] = []
    private var views: [String: DisplayInputMenuRow] = [:]
    private var observer: NSObjectProtocol?
    init(menu: NSMenu, controller: DisplayInputController? = nil) {
        self.menu = menu
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("T-Cube/display-inputs.json")
        self.controller = controller ?? DisplayInputController(hardware: NativeDisplayInputHardware(), targets: DisplayBrightnessMenu.connectedDisplays, store: DisplayInputStore(url: base))
        super.init()
        self.controller.onChange = { [weak self] in self?.render() }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.screenParametersChanged() }
        }
        render()
    }
    func beginTracking() { controller.beginTracking() }
    func endTracking() { controller.endTracking() }
    private func render() {
        guard let menu else { return }
        let rows = controller.rows
        if !rows.isEmpty, Set(views.keys) == Set(rows.map(\.id)) { for row in rows { views[row.id]?.apply(row) }; return }
        for item in items where menu.index(of: item) >= 0 { menu.removeItem(item) }
        items.removeAll(); views.removeAll()
        let header = NSMenuItem(title: "显示器输入源", action: nil, keyEquivalent: ""); header.isEnabled = false; items.append(header)
        if rows.isEmpty {
            let empty = NSMenuItem(title: controller.isOpen ? "未检测到外接显示器" : "正在读取显示器…", action: nil, keyEquivalent: ""); empty.isEnabled = false; items.append(empty)
        }
        for row in rows {
            let item = NSMenuItem()
            let view = DisplayInputMenuRow(row: row, change: { [weak self] in self?.controller.setSource($1, for: $0) }, configure: { [weak self] in self?.configure($0) }, reload: { [weak self] in self?.controller.refresh() })
            item.view = view; items.append(item); views[row.id] = view
        }
        items.append(.separator())
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
    }
    private func configure(_ row: DisplayInputRow) {
        let alert = DisplayInputSetupView.makeAlert(row: row) { [weak self] in self?.showInputHelp() }
        guard let container = alert.accessoryView as? DisplayInputSetupView else { return }
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        guard let a = UInt16(container.typeC.stringValue), let b = UInt16(container.hdmi.stringValue), let mapping = DisplayInputMapping(typeC: a, hdmi: b) else {
            let error = NSAlert(); error.messageText = "输入代码无效"; error.informativeText = "请输入两个不同的 0–65535 整数。"; error.runModal(); return
        }
        do { try controller.save(mapping, for: row.id) }
        catch {
            let alert = NSAlert(error: error)
            alert.informativeText = error as? DisplayBrightnessFailure == .disconnected
                ? "显示器连接已变化。请关闭设置，重新打开菜单并刷新，再选择对应屏幕。"
                : "无法保存输入映射。请备份并检查 display-inputs.json 后重试。"
            alert.runModal()
        }
    }
    private func showInputHelp() {
        // The setup button already runs inside its modal loop. Enqueuing another
        // main-queue block would defer help until the setup callback returns.
        DisplayInputHelp.makeAlert().runModal()
    }
    func stop() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil; controller.stop(); if let menu { for item in items where menu.index(of: item) >= 0 { menu.removeItem(item) } }; items.removeAll(); views.removeAll() }
}
